import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

Suggestion _typed(
  String name, {
  String? quantity,
  String? brand,
  String? storeId,
  String? categoryId,
  bool deviceParsed = false,
}) => Suggestion(
  SuggestionSource.typed,
  ParsedEntry(
    name: name,
    quantity: quantity,
    brand: brand,
    storeId: storeId,
    categoryId: categoryId,
    deviceParsed: deviceParsed,
  ),
);

Suggestion _history(
  String name, {
  String? quantity,
  String? brand,
  String? storeId,
  String? categoryId,
}) => Suggestion(
  SuggestionSource.history,
  ParsedEntry(
    name: name,
    quantity: quantity,
    brand: brand,
    storeId: storeId,
    categoryId: categoryId,
  ),
);

/// What a row shows and adds.
(SuggestionSource, String, String?, String?, String?, String?, bool) _seen(
  Suggestion s,
) => (
  s.source,
  s.entry.name,
  s.entry.quantity,
  s.entry.brand,
  s.entry.storeId,
  s.entry.categoryId,
  s.entry.deviceParsed,
);

List<Object> _all(List<Suggestion> rows) => [for (final r in rows) _seen(r)];

void main() {
  test('the shown rows keep their order; the server only adds below', () {
    final merged = mergeRows(
      [_typed('Milch', deviceParsed: true), _history('Hafermilch')],
      [
        _typed('Milch'),
        _history('Milchreis'),
        _history('Hafermilch'),
        _history('Milch', brand: 'Weihenstephan'),
      ],
    );
    expect(
      [for (final r in merged) r.entry.name],
      ['Milch', 'Hafermilch', 'Milchreis', 'Milch'],
    );
    expect(merged.last.entry.brand, 'Weihenstephan');
  });

  test("the typed row is the server's when it reads the same", () {
    final server = _typed('milch', storeId: 'lidl', categoryId: 'chilled');
    expect(
      _all(mergeRows([_typed('Milch', deviceParsed: true)], [server])),
      _all([server]),
      reason: 'one key, one quantity: the same on screen',
    );
  });

  test('a typed row the server reads otherwise keeps its text and takes '
      "the server's category and store", () {
    expect(
      _all(
        mergeRows(
          [_typed('Karotten', quantity: '2', deviceParsed: true)],
          [_typed('Karotten', storeId: 'lidl', categoryId: 'produce')],
        ),
      ),
      _all([
        _typed(
          'Karotten',
          quantity: '2',
          storeId: 'lidl',
          categoryId: 'produce',
          deviceParsed: true,
        ),
      ]),
    );
    expect(
      _all(
        mergeRows(
          [_typed('Windeln Pampers', categoryId: 'g', deviceParsed: true)],
          [_typed('Windeln', brand: 'Pampers', categoryId: 'drugstore')],
        ),
      ),
      _all([
        _typed('Windeln Pampers', categoryId: 'drugstore', deviceParsed: true),
      ]),
      reason: "the server's reading of the typed line is not a second row",
    );
  });

  test("the device's guess stays where the server has none", () {
    expect(
      _all(
        mergeRows(
          [_typed('Milch', categoryId: 'chilled', deviceParsed: true)],
          [_typed('Milch', quantity: '1')],
        ),
      ),
      _all([_typed('Milch', categoryId: 'chilled', deviceParsed: true)]),
    );
  });

  // Review 1 of job 274: the device's index can carry a store the
  // household cleared since; the server's "none" is the answer.
  test("a shown row takes the server's no store over the device's store", () {
    expect(
      _all(
        mergeRows(
          [
            _typed('Quarkbä', storeId: 'krume', deviceParsed: true),
            _history('Quarkbällchen', storeId: 'krume', categoryId: 'bakery'),
          ],
          [
            _typed('Quarkbä', quantity: '1', categoryId: 'bakery'),
            _history('Quarkbällchen', categoryId: 'bakery'),
          ],
        ),
      ),
      _all([
        _typed('Quarkbä', categoryId: 'bakery', deviceParsed: true),
        _history('Quarkbällchen', categoryId: 'bakery'),
      ]),
    );
  });

  test("another shown row takes the server's fields but keeps its "
      'quantity', () {
    expect(
      _all(
        mergeRows(
          [_typed('Hafer', deviceParsed: true), _history('Hafermilch')],
          [
            _typed('Hafer'),
            _history(
              'Hafermilch',
              quantity: '2',
              storeId: 'dm',
              categoryId: 'chilled',
            ),
          ],
        ),
      ).last,
      _seen(_history('Hafermilch', storeId: 'dm', categoryId: 'chilled')),
    );
  });

  test('no item twice', () {
    final merged = mergeRows(
      [_typed('Milch', deviceParsed: true), _history('Hafermilch')],
      [
        _history('hafermilch'),
        _history('Hafermilch', quantity: '2'),
        _history('Milch'),
        _history('Kakao'),
        _history('Kakao'),
      ],
    );
    expect(
      [for (final r in merged) r.entry.name],
      ['Milch', 'Hafermilch', 'Kakao'],
    );
  });

  test("without a typed row shown, the server's comes in its place", () {
    expect(
      [
        for (final r in mergeRows(const [], [
          _typed('Milch'),
          _history('Kakao'),
        ]))
          r.entry.name,
      ],
      ['Milch', 'Kakao'],
    );
  });

  test('the server fills up to eight rows, the device rows all stay', () {
    final local = [
      _typed('Milch', deviceParsed: true),
      for (final name in ['Milchreis', 'Milchschnitte', 'Milchzucker'])
        _history(name),
    ];
    final server = [
      _typed('Milch'),
      for (var i = 0; i < 8; i++) _history('Milch', brand: 'Marke $i'),
    ];
    final merged = mergeRows(local, server);
    expect(merged, hasLength(mergedRows));
    expect(merged.take(4).map((r) => r.entry.name), [
      'Milch',
      'Milchreis',
      'Milchschnitte',
      'Milchzucker',
    ]);
    expect(merged.skip(4).map((r) => r.entry.brand), [
      'Marke 0',
      'Marke 1',
      'Marke 2',
      'Marke 3',
    ]);
  });
}
