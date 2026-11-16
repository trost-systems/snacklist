import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/catalog_loader.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime.utc(2026, 11, 16, 8);
final _bundled = CatalogIndex.bundled;

Map<String, Object?> _answer(String version, String term) => {
  'version': version,
  'full': false,
  'terms': {
    'put': [
      [term, term, 'produce'],
    ],
    'drop': <Object?>[],
  },
};

final class _Store() implements CatalogStore {
  CachedCatalogDelta? cached;
  var saves = 0;

  /// When set, the cache read waits for it.
  Completer<void>? gate;

  @override
  Future<CachedCatalogDelta?> cachedCatalogDelta() async {
    await gate?.future;
    return cached;
  }

  @override
  Future<void> saveCachedCatalogDelta(CachedCatalogDelta cached) async {
    saves++;
    this.cached = cached;
  }
}

final class _Server() implements CatalogRepository {
  Object? Function() answer = () => null;
  final asked = <String>[];
  final had = <String>[];

  @override
  Future<Object?> catalogDelta(String base, {required String have}) async {
    asked.add(base);
    had.add(have);
    return answer();
  }
}

void main() {
  late _Store store;
  late _Server server;
  late CatalogCubit cubit;
  late CatalogLoader loader;

  setUp(() {
    store = _Store();
    server = _Server();
    cubit = CatalogCubit();
    loader = CatalogLoader(
      store: store,
      repository: server,
      cubit: cubit,
      now: () => _at,
    );
  });
  tearDown(() => cubit.close());

  CachedCatalogDelta cached({
    Duration age = Duration.zero,
    String? base,
    String term = 'zwurbel',
  }) => CachedCatalogDelta(
    checkedAt: _at.subtract(age),
    base: base ?? _bundled.version,
    body: jsonEncode(_answer('00000000000000aa', term)),
  );

  test('the cached answer applies at start, before any check', () async {
    store.cached = cached(age: const Duration(days: 3));
    await loader.follow(on: true, signedIn: false);
    expect(cubit.state.version, '00000000000000aa');
    expect(cubit.state.terms.containsKey('zwurbel'), isTrue);
    expect(server.asked, isEmpty, reason: 'signed out, catalog_delta refuses');
  });

  test('a due check asks from the bundled version, keeps and applies the '
      'answer', () async {
    store.cached = cached(age: const Duration(days: 1, minutes: 1));
    server.answer = () => _answer('00000000000000bb', 'quorpel');
    await loader.follow(on: true, signedIn: true);
    expect(server.asked, [_bundled.version]);
    expect(cubit.state.version, '00000000000000bb');
    expect(cubit.state.terms.containsKey('quorpel'), isTrue);
    expect(
      cubit.state.terms.containsKey('zwurbel'),
      isFalse,
      reason: 'answers never build on each other',
    );
    expect(store.cached?.checkedAt, _at);
    expect(
      parseCatalogDelta(jsonDecode(store.cached!.body!))?.version,
      '00000000000000bb',
    );
  });

  test('within a day of the last check the server is not asked', () async {
    store.cached = cached(age: const Duration(hours: 23));
    await loader.follow(on: true, signedIn: true);
    expect(server.asked, isEmpty);
    expect(cubit.state.version, '00000000000000aa');
  });

  test('a clock set back makes the check due', () async {
    store.cached = cached(age: const Duration(hours: -2));
    server.answer = () => _answer('00000000000000bb', 'quorpel');
    await loader.follow(on: true, signedIn: true);
    expect(server.asked, hasLength(1));
  });

  test('offline, the cached answer stays and the next start asks', () async {
    store.cached = cached(age: const Duration(days: 2));
    server.answer = () => throw Exception('offline');
    await loader.follow(on: true, signedIn: true);
    expect(cubit.state.version, '00000000000000aa');
    expect(store.saves, 0);
  });

  test(
    'a malformed answer is kept out, and not asked for again that day',
    () async {
      store.cached = cached(age: const Duration(days: 2));
      server.answer = () => {'version': 'nope'};
      await loader.follow(on: true, signedIn: true);
      expect(cubit.state.version, '00000000000000aa');
      expect(store.cached?.checkedAt, _at);
      expect(store.cached?.body, cached().body, reason: 'the last good answer');
      await loader.follow(on: true, signedIn: true);
      expect(server.asked, hasLength(1));
    },
  );

  test('an answer for another bundled version is ignored', () async {
    store.cached = cached(base: '0123456789abcdef');
    server.answer = () => _answer('00000000000000bb', 'quorpel');
    await loader.follow(on: true, signedIn: true);
    expect(server.asked, [_bundled.version], reason: 'due: the app changed');
    expect(cubit.state.terms.containsKey('zwurbel'), isFalse);
    expect(cubit.state.version, '00000000000000bb');
  });

  test(
    'with the flag off the bundled catalog stays and nothing is asked',
    () async {
      store.cached = cached(age: const Duration(days: 2));
      await loader.follow(on: false, signedIn: true);
      expect(identical(cubit.state, _bundled), isTrue);
      expect(server.asked, isEmpty);

      await loader.follow(on: true, signedIn: false);
      expect(cubit.state.version, '00000000000000aa');
      await loader.follow(on: false, signedIn: false);
      expect(identical(cubit.state, _bundled), isTrue, reason: 'switched off');
    },
  );

  test('signing in while a signed-out start still reads the cache checks '
      'once', () async {
    store
      ..cached = cached(age: const Duration(days: 2))
      ..gate = Completer<void>();
    server.answer = () => _answer('00000000000000bb', 'quorpel');
    final signedOut = loader.follow(on: true, signedIn: false);
    final signedIn = loader.follow(on: true, signedIn: true);
    final again = loader.follow(on: true, signedIn: true);
    store.gate!.complete();
    await Future.wait([signedOut, signedIn, again]);
    expect(server.asked, [_bundled.version]);
    expect(cubit.state.version, '00000000000000bb');
  });

  test('a check names the version applied; "you have it" keeps the cached '
      'answer', () async {
    store.cached = cached(age: const Duration(days: 2));
    server.answer = () => {'version': '00000000000000aa', 'full': false};
    await loader.follow(on: true, signedIn: true);
    expect(server.had, ['00000000000000aa']);
    expect(cubit.state.version, '00000000000000aa');
    expect(cubit.state.terms.containsKey('zwurbel'), isTrue);
    expect(store.cached?.checkedAt, _at);
    expect(store.cached?.body, cached().body);
  });

  test('without a cached answer it names the bundled version', () async {
    server.answer = () => {'version': _bundled.version, 'full': false};
    await loader.follow(on: true, signedIn: true);
    expect(server.had, [_bundled.version]);
    expect(cubit.state.version, _bundled.version);
  });

  test('an answer without tables is never the bundled rows under another '
      'version', () async {
    store.cached = cached(age: const Duration(days: 2));
    server.answer = () => {'version': '00000000000000cc', 'full': false};
    await loader.follow(on: true, signedIn: true);
    expect(cubit.state.version, '00000000000000aa');
    expect(cubit.state.terms.containsKey('zwurbel'), isTrue);
    expect(store.cached?.body, cached().body);
    expect(store.cached?.checkedAt, _at);
  });
}
