import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/guides/guide_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final page = guidePage('/de/anleitungen/alexa');
  final alexa = File('test/guides/fixtures/de-anleitungen-alexa.md')
      .readAsStringSync();

  test('a guide route is its page on snacklist.app', () {
    expect(page, Uri.parse('https://snacklist.app/de/anleitungen/alexa'));
    expect(guidePage('/en/guides/claude.md').path, '/en/guides/claude');
    expect(guidePage('/en/guides/').path, '/en/guides');
    expect(guideIndexOf(guidePage('/en/guides/claude')), '/en/guides');
    expect(guideIndexOf(page), '/de/anleitungen');
  });

  test("the page's Markdown twin, without its footer for agents", () async {
    final asked = <Uri>[];
    final fetched = await fetchGuide(
      MockClient((request) async {
        asked.add(request.url);
        return http.Response.bytes(
          utf8.encode(alexa),
          200,
          headers: {'content-type': 'text/markdown; charset=utf-8'},
        );
      }),
      page,
    );
    expect(asked, [Uri.parse('https://snacklist.app/de/anleitungen/alexa.md')]);
    final markdown = (fetched as GuideShown).markdown;
    expect(markdown, startsWith('# Snacklist per Alexa: Skill einrichten'));
    expect(markdown, contains('Füllwörter wie „bitte“'));
    expect(markdown, isNot(contains('Canonical URL')));
    expect(markdown.trimRight(), endsWith('verbundenen Unternehmen.'));
  });

  Future<GuideFetch> answer(int status, [String body = '']) =>
      fetchGuide(MockClient((_) async => http.Response(body, status)), page);

  test('a page the site does not have is missing', () async {
    expect(await answer(404, 'Not found'), isA<GuideMissing>());
  });

  test('any other status fails', () async {
    expect(await answer(500), isA<GuideFailed>());
    expect(await answer(403), isA<GuideFailed>());
    expect(await answer(301), isA<GuideFailed>());
  });

  test('no connection fails', () async {
    final fetched = await fetchGuide(
      MockClient((_) => throw http.ClientException('offline')),
      page,
    );
    expect(fetched, isA<GuideFailed>());
  });

  test('a body over the limit fails, one at it is read', () async {
    expect(await answer(200, 'a' * (guideMaxBytes + 1)), isA<GuideFailed>());
    expect(await answer(200, 'a' * guideMaxBytes), isA<GuideShown>());
  });

  test('a body that is no UTF-8 fails', () async {
    final fetched = await fetchGuide(
      MockClient((_) async => http.Response.bytes([0xff, 0xfe, 0x41], 200)),
      page,
    );
    expect(fetched, isA<GuideFailed>());
  });

  test('no answer within the timeout fails', () {
    fakeAsync((async) {
      GuideFetch? fetched;
      unawaited(
        fetchGuide(
          MockClient((_) => Completer<http.Response>().future),
          page,
        ).then((f) => fetched = f),
      );
      async.elapse(guideTimeout - const Duration(milliseconds: 1));
      expect(fetched, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(fetched, isA<GuideFailed>());
    });
  });
}
