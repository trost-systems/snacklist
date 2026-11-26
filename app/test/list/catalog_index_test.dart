import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/catalog_index.g.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/category_guess.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:flutter_test/flutter_test.dart';

const _next = '00000000000000ab';

Map<String, Object?> _delta({
  bool full = false,
  Map<String, Object?>? terms,
  Map<String, Object?>? forms,
  Map<String, Object?>? brands,
  Object? homographs,
}) => {
  'version': _next,
  'full': full,
  'terms': ?terms,
  'forms': ?forms,
  'brands': ?brands,
  'homographs': ?homographs,
};

const _none = {'put': <Object?>[], 'drop': <Object?>[]};

void main() {
  final bundled = CatalogIndex.bundled;

  test('the bundled index holds the generated rows under their version', () {
    expect(bundled.version, catalogVersion);
    expect(bundled.terms, hasLength(catalogTerms.length));
    expect(bundled.forms, hasLength(catalogForms.length));
    expect(bundled.brands, hasLength(catalogBrands.length));
    expect(bundled.forms['milch']?.category, 'chilled');
    expect(bundled.brands['tempo']?.product, isNotNull);
    expect(bundled.phraseForms, everyElement(contains(' ')));
    expect(
      bundled.homographs.values.expand((spellings) => spellings),
      hasLength(catalogHomographs.length),
    );
    expect(bundled.homographs['schaufel']?.map((h) => h.category), [
      'garden',
      'meat',
    ]);
  });

  test('an unchanged answer keeps every row under the new version', () {
    final next = bundled.apply(parseCatalogDelta(_delta())!);
    expect(next.version, _next);
    expect(next.terms, bundled.terms);
    expect(next.forms, bundled.forms);
    expect(next.brands, bundled.brands);
    expect(next.homographs, bundled.homographs);
  });

  test("an answer's homographs replace the device's (job 473)", () {
    bool same(String a, String b, CatalogIndex index) =>
        canonicalKeyOf(a, index) == canonicalKeyOf(b, index);
    expect(same('Schäufele', 'Schaufel', bundled), isFalse);
    expect(same('Beeren', 'beer', bundled), isFalse);

    final none = bundled.apply(
      parseCatalogDelta(_delta(homographs: <Object?>[]))!,
    );
    expect(none.homographs, isEmpty);
    expect(same('Schäufele', 'Schaufel', none), isTrue);

    final schaufel = bundled.apply(
      parseCatalogDelta(
        _delta(
          homographs: [
            ['schaufel', 'schaufel', 'schaufel', 'garden', false],
            ['schaufel', 'schäufele', 'schaufele', 'meat', false],
          ],
        ),
      )!,
    );
    expect(same('Schäufele', 'Schaufel', schaufel), isFalse);
    expect(same('Schäufele', 'Schäuferle', schaufel), isTrue);
    expect(same('Beeren', 'beer', schaufel), isTrue, reason: 'beer is gone');
  });

  test('puts and drops change what the guess and the parser know', () {
    expect(lexiconSeed('Zwurbel', bundled), isNull);
    expect(parseEntry('Zwurbel 2').quantity, isNull);
    final delta = parseCatalogDelta(
      _delta(
        terms: {
          'put': [
            ['zwurbel', 'zwurbel', 'produce'],
          ],
          'drop': ['milch'],
        },
        forms: {
          'put': [
            ['zwurbel', 'zwurbel', 'produce', false],
          ],
          'drop': ['milch'],
        },
        brands: {
          'put': [
            ['tempo', 'Tempo', null, 'dm'],
          ],
          'drop': <Object?>[],
        },
      ),
    )!;
    final next = bundled.apply(delta);
    expect(lexiconSeed('Zwurbel', next), 'produce');
    expect(parseEntry('Zwurbel 2', catalogIndex: next).quantity, '2');
    expect(next.forms.containsKey('milch'), isFalse);
    expect(next.terms.containsKey('milch'), isFalse);
    expect(next.terms.keys, orderedEquals(next.terms.keys.toList()..sort()));
    expect(next.brands['tempo'], (
      key: 'tempo',
      brand: 'Tempo',
      product: null,
      storeSeed: 'dm',
    ));
    expect(next.brands, hasLength(bundled.brands.length));
  });

  test('a full answer replaces every row', () {
    final next = bundled.apply(
      parseCatalogDelta(
        _delta(
          full: true,
          terms: {
            'put': [
              ['milch', 'milch', 'chilled'],
            ],
            'drop': <Object?>[],
          },
          forms: _none,
          brands: _none,
        ),
      )!,
    );
    expect(next.terms.keys, ['milch']);
    expect(next.forms, isEmpty);
    expect(next.brands, isEmpty);
  });

  group('anything off rejects the whole answer', () {
    final cases = <String, Object?>{
      'not a map': 'nope',
      'no version': {'full': false},
      'a version that is no digest': {'version': 'v1', 'full': false},
      'no full flag': {'version': _next},
      'a full answer without a table': _delta(
        full: true,
        terms: _none,
        forms: _none,
      ),
      'a table without drops': _delta(terms: {'put': <Object?>[]}),
      'a row of the wrong length': _delta(
        terms: {
          'put': [
            ['milch', 'milch'],
          ],
          'drop': <Object?>[],
        },
      ),
      'a row of the wrong types': _delta(
        forms: {
          'put': [
            ['milch', 'milch', 'chilled', 'yes'],
          ],
          'drop': <Object?>[],
        },
      ),
      'an empty key': _delta(
        brands: {
          'put': [
            ['', 'Tempo', null, null],
          ],
          'drop': <Object?>[],
        },
      ),
      'a text too long': _delta(
        terms: {
          'put': <Object?>[],
          'drop': ['x' * 201],
        },
      ),
      'a drop that is no text': _delta(
        terms: {
          'put': <Object?>[],
          'drop': [1],
        },
      ),
      'homographs that are no list': _delta(homographs: {'put': <Object?>[]}),
      'a homograph row of the wrong length': _delta(
        homographs: [
          ['schaufel', 'schaufel', 'schaufel', 'garden'],
        ],
      ),
      'a homograph row of the wrong types': _delta(
        homographs: [
          ['schaufel', 'schaufel', 'schaufel', 'garden', 'no'],
        ],
      ),
      'an empty homograph spelling': _delta(
        homographs: [
          ['schaufel', '', 'schaufel', 'garden', false],
        ],
      ),
      'too many rows': _delta(
        terms: {
          'put': List.filled(20001, ['a', 'a', 'produce']),
          'drop': <Object?>[],
        },
      ),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () => expect(parseCatalogDelta(value), isNull));
    }
  });
}
