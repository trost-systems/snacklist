import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The catalog the device parses, guesses and ranks with: the bundled one
/// until [CatalogLoader] applies the server's changes.
class CatalogCubit([CatalogIndex? index]) extends Cubit<CatalogIndex> {
  this : super(index ?? CatalogIndex.bundled);

  void use(CatalogIndex index) => emit(index);
}

/// Asks the server for the catalog's changes.
abstract interface class CatalogRepository() {
  /// public.catalog_delta's answer for [base], unparsed; [have] is the
  /// version the device has applied.
  Future<Object?> catalogDelta(String base, {required String have});
}

class SupabaseCatalogRepository(final SupabaseClient _client)
    implements CatalogRepository {
  @override
  Future<Object?> catalogDelta(String base, {required String have}) => _client
      .rpc<Object?>('catalog_delta', params: {'p_base': base, 'p_have': have});
}

/// What the device keeps of the last check: when the server last answered,
/// the version the device asked about, and the last answer that passed
/// [parseCatalogDelta] as JSON (none before the first good one).
final class const CachedCatalogDelta({
  required final DateTime checkedAt,
  required final String base,
  final String? body,
});

/// The cached answer on this device: `DeviceCache` in the app.
abstract interface class CatalogStore() {
  Future<CachedCatalogDelta?> cachedCatalogDelta();

  Future<void> saveCachedCatalogDelta(CachedCatalogDelta cached);
}

/// Larger answers are not kept: the full catalog is about 170 KB.
const catalogDeltaMaxBytes = 1024 * 1024;

/// Applies the server's catalog changes over the bundled catalog (job 274)
/// while the flag `on-device-catalog` is on: the cached answer first, then
/// at most once a day a fresh one, asked for from the bundled version, so
/// an answer never builds on another.
final class CatalogLoader({
  required final CatalogStore store,
  required final CatalogRepository repository,
  required final CatalogCubit cubit,
  final DateTime Function() now = DateTime.now,
  final CatalogIndex? bundled,
}) {
  static const checkEvery = Duration(hours: 24);
  static const timeout = Duration(seconds: 10);

  late final _bundled = bundled ?? CatalogIndex.bundled;
  var _on = false;
  var _signedIn = false;
  Future<void>? _running;

  /// Follows the flag and the session: on, the cached answer applies and
  /// a due check runs once [signedIn] (catalog_delta is for signed-in
  /// users); off, the bundled catalog is back.
  Future<void> follow({required bool on, required bool signedIn}) {
    if (!on) {
      _on = false;
      cubit.use(_bundled);
      return Future.value();
    }
    _on = true;
    _signedIn = signedIn;
    return _running ??= _runUntilSignedInRan().whenComplete(
      () => _running = null,
    );
  }

  /// A sign-in during a signed-out run runs once more: that run skipped
  /// the check.
  Future<void> _runUntilSignedInRan() async {
    bool ran;
    do {
      ran = _signedIn;
      await _run(signedIn: ran);
    } while (!ran && _signedIn);
  }

  Future<void> _run({required bool signedIn}) async {
    final cached = await store.cachedCatalogDelta();
    final mine = cached?.base == _bundled.version ? cached : null;
    final applied = switch (mine?.body) {
      final body? => parseCatalogDelta(_decode(body)),
      null => null,
    };
    _apply(applied);
    // A check time ahead of the clock (the clock was set back) is due too.
    final age = switch (mine) {
      final mine? => now().difference(mine.checkedAt),
      null => null,
    };
    if (!signedIn || (age != null && !age.isNegative && age < checkEvery)) {
      return;
    }
    final Object? answer;
    try {
      answer = await repository
          .catalogDelta(
            _bundled.version,
            have: applied?.version ?? _bundled.version,
          )
          .timeout(timeout);
    } on Object {
      // Offline or refused: asked again at the next start.
      return;
    }
    final body = jsonEncode(answer);
    final parsed = body.length > catalogDeltaMaxBytes
        ? null
        : parseCatalogDelta(answer);
    // An answer without tables says the version the device has applied is
    // current; it never means the bundled rows under another version.
    final delta = parsed != null && _tableless(answer)
        ? (parsed.version == _bundled.version ? parsed : null)
        : parsed;
    // A bad answer is not asked for again on every start either.
    await store.saveCachedCatalogDelta(
      CachedCatalogDelta(
        checkedAt: now(),
        base: _bundled.version,
        body: delta == null ? mine?.body : body,
      ),
    );
    _apply(delta);
  }

  static bool _tableless(Object? answer) =>
      answer is Map &&
      !answer.containsKey('terms') &&
      !answer.containsKey('forms') &&
      !answer.containsKey('brands');

  void _apply(CatalogDelta? delta) {
    if (_on && delta != null && delta.version != cubit.state.version) {
      cubit.use(_bundled.apply(delta));
    }
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
