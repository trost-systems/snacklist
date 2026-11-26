import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/guides/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// `fixtures/` holds the site build's own output (`site/guide-data.mjs`)
/// for the German Siri guide and index, the guide with a block of a type
/// this app does not know, a heading too deep, and links of every kind
/// appended.
void main() {
  const siri = GuideRef(GuideLocale.de, 'siri-kurzbefehl');
  String fixture(String name) =>
      File('test/guides/fixtures/$name').readAsStringSync();

  group('GuideRef', () {
    test('names the guides paths, the same on the site and in the app', () {
      expect(GuideRef.ofPath('/de/anleitungen')?.path, '/de/anleitungen');
      expect(GuideRef.ofPath('/en/guides/')?.path, '/en/guides');
      expect(
        GuideRef.ofPath('/de/anleitungen/siri-kurzbefehl')?.path,
        siri.path,
      );
      expect(
        GuideRef.ofPath('/en/guides/siri-shortcut')?.dataPath,
        '/data/guides/en/siri-shortcut.json',
      );
      expect(
        const GuideRef(GuideLocale.de).dataPath,
        '/data/guides/de/index.json',
      );
    });

    test(
      'below the guides a Markdown twin is its guide, the rest the index',
      () {
        expect(
          GuideRef.ofPath('/de/anleitungen/siri-kurzbefehl.md')?.path,
          siri.path,
        );
        for (final path in ['/en/guides/Siri', '/en/guides/a/b']) {
          expect(GuideRef.ofPath(path)?.path, '/en/guides', reason: path);
        }
      },
    );

    test('nothing else is a guide', () {
      for (final path in [
        '/',
        '/de',
        '/de/guides',
        '/en/anleitungen/x',
        '/fr/guides',
        '/datenschutz',
      ]) {
        expect(GuideRef.ofPath(path), isNull, reason: path);
      }
    });
  });

  group('linkOf', () {
    test('a guide on the site opens in the app', () {
      final link = linkOf('https://snacklist.app/de/anleitungen/alexa');
      expect(link, isA<InAppLink>());
      expect((link! as InAppLink).ref.path, '/de/anleitungen/alexa');
      final section = linkOf('https://snacklist.app/en/guides/alexa#setup');
      expect((section! as InAppLink).anchor, 'setup');
      expect(
        (linkOf('https://snacklist.app/en/guides')! as InAppLink).ref.path,
        '/en/guides',
      );
    });

    test('an anchor scrolls on the page', () {
      expect((linkOf('#schritt-2')! as AnchorLink).id, 'schritt-2');
      expect(linkOf('#'), isNull);
    });

    test('any other page opens in the browser', () {
      for (final href in [
        'https://snacklist.app/datenschutz',
        'https://snacklist.app/en/changelog#v1-4-1',
        'https://www.snacklist.app/de/anleitungen/alexa',
        'https://app.snacklist.app/more/access',
        'https://claude.ai',
        'mailto:hallo@snacklist.app',
      ]) {
        expect(linkOf(href), isA<WebLink>(), reason: href);
        expect((linkOf(href)! as WebLink).url.toString(), href);
      }
    });

    test('a link the app will not follow is plain text', () {
      for (final href in ['javascript:alert(1)', '/de/anleitungen', 'x:y']) {
        expect(linkOf(href), isNull, reason: href);
      }
    });
  });

  group('parseGuideContent', () {
    test('reads every block type of the site build and skips the rest', () {
      final guide =
          parseGuideContent(siri, fixture('siri-kurzbefehl.json'))! as Guide;
      expect(guide.title, 'Snacklist per Siri: Kurzbefehl einrichten');
      expect(guide.slug, 'siri-kurzbefehl');
      final raw =
          ((jsonDecode(fixture('siri-kurzbefehl.json')) as Map)['blocks']!
                  as List)
              .cast<Map<String, Object?>>();
      // The video and the fifth-level heading are gone, all else stays.
      expect(guide.blocks, hasLength(raw.length - 2));
      expect(guide.blocks.map((b) => b.runtimeType).toSet(), {
        HeadingBlock,
        ParagraphBlock,
        ListBlock,
        QuoteBlock,
        CodeBlock,
        TableBlock,
      });

      final quote = guide.blocks[1] as QuoteBlock;
      final dialog = (quote.blocks.single as ParagraphBlock).text;
      expect(dialog.first.text, 'Du:');
      expect(dialog.first.strong, isTrue);
      expect(dialog[1].strong, isFalse);

      final steps = guide.blocks.whereType<ListBlock>().firstWhere(
        (l) => l.ordered,
      );
      expect(steps.items, hasLength(5));
      expect(
        (steps.items.first.single as ParagraphBlock).text.single.text,
        'Öffne die Snacklist-App.',
      );

      final table = guide.blocks.whereType<TableBlock>().first;
      expect(table.header.map((c) => c.single.text), [
        'Du sagst',
        'Auf der Liste',
      ]);
      expect(table.rows.first.map((c) => c.single.text), [
        'Milch, zwei Gurken und Klopapier',
        'Milch · 2× Gurken · Klopapier',
      ]);

      final code = guide.blocks.whereType<CodeBlock>().single;
      expect(code.text, startsWith('Text diktieren'));
      expect(code.text, contains('\n'));

      final headings = guide.blocks.whereType<HeadingBlock>();
      expect(headings.first.level, 2);
      expect(
        headings.map((h) => h.id).whereType<String>(),
        contains('siri-wieder-abschalten'),
      );

      final links = (guide.blocks.last as ParagraphBlock).text;
      expect(links[1].link, isA<AnchorLink>());
      expect(links[3].em, isTrue);
      expect(links[3].link, isA<InAppLink>());
      expect(links[5].link, isA<WebLink>());
      expect(links[7].text, 'kein Link');
      expect(links[7].link, isNull);
    });

    test('a heading id shows once: the first heading keeps it', () {
      final guide =
          parseGuideContent(
                siri,
                jsonEncode({
                  'schema': 1,
                  'locale': 'de',
                  'slug': 'siri-kurzbefehl',
                  'title': 'T',
                  'blocks': [
                    for (var i = 0; i < 2; i++)
                      {
                        'type': 'heading',
                        'level': 2,
                        'id': 'a',
                        'text': [
                          {'text': 'A'},
                        ],
                      },
                  ],
                }),
              )!
              as Guide;
      expect(guide.blocks.map((b) => (b as HeadingBlock).id), ['a', null]);
    });

    test("reads the index, guides in the site's order", () {
      final index =
          parseGuideContent(
                const GuideRef(GuideLocale.de),
                fixture('index.json'),
              )!
              as GuideIndex;
      expect(index.title, 'Anleitungen');
      expect(index.guides.map((g) => g.slug), [
        'claude',
        'alexa',
        'siri-kurzbefehl',
      ]);
      expect(index.guides.last.description, startsWith('Mit einem Kurzbefehl'));
    });

    test('a file for another place, schema or no JSON is none', () {
      final body = fixture('siri-kurzbefehl.json');
      expect(
        parseGuideContent(const GuideRef(GuideLocale.de, 'alexa'), body),
        isNull,
      );
      expect(
        parseGuideContent(
          const GuideRef(GuideLocale.en, 'siri-kurzbefehl'),
          body,
        ),
        isNull,
      );
      expect(parseGuideContent(const GuideRef(GuideLocale.de), body), isNull);
      expect(
        parseGuideContent(
          siri,
          body.replaceFirst('"schema": 1', '"schema": 2'),
        ),
        isNull,
      );
      expect(parseGuideContent(siri, '<!doctype html>'), isNull);
    });
  });
}
