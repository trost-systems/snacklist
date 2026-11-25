import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/list/item_icons_remote.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final url = Uri.parse('https://snacklist.app/data/item-icons.v1.json');
const bundled = 6;

String file({
  Object? schema = 1,
  Object? revision = 7,
  Map<String, Object?> entries = const {'snacklist': '🐝', 'banane': ''},
}) => jsonEncode({'schema': schema, 'revision': revision, 'entries': entries});

final class _Store() implements ItemIconsStore {
  CachedItemIcons? cached;
  var writes = 0;

  @override
  Future<CachedItemIcons?> cachedItemIcons() async => cached;

  @override
  Future<void> saveCachedItemIcons(CachedItemIcons value) async {
    writes++;
    cached = value;
  }
}

void main() {
  late _Store store;
  late ItemIconsCubit cubit;
  late List<http.BaseRequest> requests;
  var clock = DateTime.utc(2026, 11, 6, 8);

  setUp(() {
    store = _Store();
    cubit = ItemIconsCubit();
    requests = [];
    clock = DateTime.utc(2026, 11, 6, 8);
  });
  tearDown(() => cubit.close());

  Future<void> start(
    Future<http.Response> Function(http.Request request) answer,
  ) => ItemIconsLoader(
    store: store,
    cubit: cubit,
    client: MockClient((request) {
      requests.add(request);
      return answer(request);
    }),
    url: url,
    now: () => clock,
    bundledRevision: bundled,
  ).start();

  Future<http.Response> ok(http.Request _) async =>
      http.Response.bytes(utf8.encode(file()), 200, headers: {'etag': '"v6"'});

  String? icon(String name) => cubit.state.emojiFor(name);

  group('parseItemIconsFile', () {
    test('reads schema 1', () {
      final parsed = parseItemIconsFile(file());
      expect(parsed?.revision, 7);
      expect(parsed?.entries, {'snacklist': '🐝', 'banane': ''});
    });

    test('accepts ZWJ emoji, phrases and whole-word keys', () {
      expect(
        parseItemIconsFile(
          file(
            entries: {
              '=ei': '🥚',
              'ice cream': '🍨',
              'koch': '🧑‍🍳',
              'thermometer': '🌡️',
            },
          ),
        )?.entries.length,
        4,
      );
    });

    for (final (what, body) in [
      ('not JSON', '{"schema": 1,'),
      ('not an object', '[1, 2]'),
      ('schema 2', file(schema: 2)),
      ('schema as text', file(schema: '1')),
      ('revision 0', file(revision: 0)),
      ('revision 1.5', file(revision: 1.5)),
      ('revision as text', file(revision: '7')),
      (
        'entries a list',
        jsonEncode({'schema': 1, 'revision': 7, 'entries': <Object?>[]}),
      ),
      ('a key with digits', file(entries: {'7up': '🥤'})),
      ('a key with a hyphen', file(entries: {'coca-cola': '🥤'})),
      ('a key with capitals', file(entries: {'Banane': '🍌'})),
      ('a key of one letter', file(entries: {'=e': '🥚'})),
      ('a key of four words', file(entries: {'a bb cc dd': '🥚'})),
      ('a value with letters', file(entries: {'banane': 'B🍌'})),
      ('a value with ASCII', file(entries: {'banane': '<b>'})),
      ('a keycap digit', file(entries: {'eins': '1️⃣'})),
      ('a bidi override', file(entries: {'banane': '\u202E🍌'})),
      ('a wide space', file(entries: {'banane': '🍌\u3000'})),
      ('a zero-width space', file(entries: {'banane': '\u200B🍌'})),
      ('a value too long', file(entries: {'banane': '🍌' * 9})),
      ('a value not text', file(entries: {'banane': 1})),
      (
        'over 10,000 entries',
        file(entries: {for (var i = 0; i < 10001; i++) _word(i): '🍌'}),
      ),
      ('over 256 KiB', '${file()}${' ' * itemIconsMaxBytes}'),
    ]) {
      test('rejects $what', () => expect(parseItemIconsFile(body), isNull));
    }
  });

  test('a newer file applies over the bundled table, stops included', () async {
    await start(ok);
    expect(icon('Snacklist'), '🐝');
    expect(icon('Banane'), isNull);
    expect(icon('Ei'), ItemIcons.bundled.emojiFor('Ei'));
    expect(store.cached?.etag, '"v6"');
    expect(store.cached?.checkedAt, clock);
  });

  test('the request carries no names, ids, cookies or own headers', () async {
    await start(ok);
    clock = clock.add(const Duration(hours: 25));
    await start((_) async => http.Response('', 304));
    expect(
      [
        for (final r in requests)
          '${r.method} ${r.url} ${jsonEncode(r.headers)}',
      ],
      ['GET $url {}', 'GET $url {"If-None-Match":"\\"v6\\""}'],
    );
  });

  test('a revision not above the bundled one is ignored', () async {
    final before = cubit.state;
    await start(
      (_) async => http.Response.bytes(utf8.encode(file(revision: 6)), 200),
    );
    expect(cubit.state, same(before));
    expect(store.cached?.body, isNotNull);
  });

  test('a cached newer file applies at start without a request', () async {
    store.cached = CachedItemIcons(
      checkedAt: clock.subtract(const Duration(hours: 23)),
      body: file(),
      etag: '"v6"',
    );
    await start(ok);
    expect(icon('Snacklist'), '🐝');
    expect(requests, isEmpty);
  });

  test('checks once a day', () async {
    await start(ok);
    clock = clock.add(const Duration(hours: 23, minutes: 59));
    await start(ok);
    expect(requests, hasLength(1));
    clock = clock.add(const Duration(minutes: 1));
    await start(ok);
    expect(requests, hasLength(2));
  });

  test('a check time ahead of the clock is due', () async {
    await start(ok);
    clock = clock.subtract(const Duration(days: 30));
    await start(ok);
    expect(requests, hasLength(2));
  });

  test('304 keeps the cached file and only moves the check time', () async {
    await start(ok);
    final first = store.cached;
    clock = clock.add(const Duration(days: 2));
    await start((_) async => http.Response('', 304));
    expect(store.cached?.body, first?.body);
    expect(store.cached?.etag, first?.etag);
    expect(store.cached?.checkedAt, clock);
    expect(icon('Snacklist'), '🐝');
  });

  test('offline keeps the cache and asks again at the next start', () async {
    await start(ok);
    final first = store.cached;
    clock = clock.add(const Duration(days: 2));
    await start((request) async => throw http.ClientException('offline'));
    expect(store.cached, same(first));
    expect(icon('Snacklist'), '🐝');
    await start((_) async => http.Response('', 304));
    expect(requests, hasLength(3));
  });

  for (final status in [404, 503]) {
    test('a $status counts as the check of the day, the cache stays', () async {
      await start(ok);
      final first = store.cached;
      clock = clock.add(const Duration(days: 2));
      await start((_) async => http.Response('nope', status));
      expect(store.cached?.body, first?.body);
      expect(store.cached?.etag, first?.etag);
      expect(store.cached?.checkedAt, clock);
      expect(icon('Snacklist'), '🐝');
      clock = clock.add(const Duration(hours: 23));
      await start((_) async => http.Response('nope', status));
      expect(requests, hasLength(2), reason: 'no request within the day');
      clock = clock.add(const Duration(hours: 2));
      await start((_) async => http.Response('', 304));
      expect(requests, hasLength(3), reason: 'asked again a day later');
    });
  }

  test(
    'a 404 before any table: the bundled one, asked again a day later',
    () async {
      await start((_) async => http.Response('', 404));
      expect(store.cached?.body, isNull);
      expect(store.cached?.checkedAt, clock);
      await start((_) async => http.Response('', 404));
      expect(requests, hasLength(1));
      expect(cubit.state, same(ItemIcons.bundled));
    },
  );

  test('a bad 200 keeps what the app has and waits a day', () async {
    await start(ok);
    final first = store.cached;
    clock = clock.add(const Duration(days: 2));
    for (final body in ['<html>', file(schema: 2), file(revision: -1)]) {
      store.cached = first;
      await start((_) async => http.Response.bytes(utf8.encode(body), 200));
      expect(store.cached?.body, first?.body, reason: body);
      expect(store.cached?.checkedAt, clock, reason: body);
      expect(icon('Snacklist'), '🐝');
    }
    await start(ok);
    expect(requests, hasLength(4));
  });

  test('a body over 256 KiB is not read', () async {
    final big = '${file(revision: 9)}${' ' * itemIconsMaxBytes}';
    await start((_) async => http.Response.bytes(utf8.encode(big), 200));
    expect(cubit.state.emojiFor('Snacklist'), isNull);
    expect(store.cached?.body, isNull);
    expect(store.cached?.checkedAt, clock);
  });

  test(
    'a body over 256 KiB without a Content-Length stops being read',
    () async {
      final chunk = utf8.encode(' ' * 1024);
      var sent = 0;
      await ItemIconsLoader(
        store: store,
        cubit: cubit,
        client: MockClient.streaming(
          (request, _) async => http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(file()),
              for (var i = 0; i < 1024; i++) chunk,
            ]).map((bytes) {
              sent++;
              return bytes;
            }),
            200,
          ),
        ),
        url: url,
        now: () => clock,
        bundledRevision: bundled,
      ).start();
      expect(icon('Snacklist'), isNull);
      expect(sent, lessThan(300));
      expect(store.cached?.checkedAt, clock);
    },
  );

  test('a Content-Length over 256 KiB is not read at all', () async {
    final never = StreamController<List<int>>();
    addTearDown(() => unawaited(never.close()));
    await ItemIconsLoader(
      store: store,
      cubit: cubit,
      client: MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          never.stream,
          200,
          contentLength: itemIconsMaxBytes + 1,
        ),
      ),
      url: url,
      now: () => clock,
      bundledRevision: bundled,
    ).start();
    expect(store.cached?.checkedAt, clock);
    expect(never.hasListener, isFalse);
  });

  test('a cached file that no longer parses is ignored', () async {
    store.cached = CachedItemIcons(
      checkedAt: clock,
      body: file(schema: 2),
      etag: '"v6"',
    );
    final before = cubit.state;
    await start(ok);
    expect(cubit.state, same(before));
  });

  test('no URL: the cache applies, nothing is fetched', () async {
    store.cached = CachedItemIcons(
      checkedAt: clock.subtract(const Duration(days: 9)),
      body: file(),
    );
    await ItemIconsLoader(
      store: store,
      cubit: cubit,
      client: MockClient((request) async => fail('fetched $request')),
      url: null,
      now: () => clock,
      bundledRevision: bundled,
    ).start();
    expect(icon('Snacklist'), '🐝');
    expect(store.writes, 0);
  });
}

/// A distinct lowercase word per [i].
String _word(int i) => String.fromCharCodes([
  for (var n = i + 26 * 27; n > 0; n ~/= 26) 0x61 + n % 26,
]);
