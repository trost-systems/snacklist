import 'dart:convert';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/list/item_icons_remote.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/review/review_counters.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/tips/tips.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';

/// What an offline start needs, in shared preferences: each user's
/// households, the one shown, and one list snapshot and seen mark per user
/// and household. A cache: a
/// value that cannot be read counts as missing, and a failed write is
/// dropped.
class DeviceCache(final SharedPreferencesAsync _prefs)
    implements
        SessionCache,
        AnalyticsStore,
        PendingInviteStore,
        TipStore,
        ItemIconsStore,
        ReviewStore {
  /// On Linux, supabase_flutter's legacy SharedPreferences and
  /// SharedPreferencesAsync each rewrite the whole file from their own copy,
  /// so sharing shared_preferences.json loses the session. The other
  /// platforms ignore Linux options and keep their default store.
  factory onDevice() => DeviceCache(
    SharedPreferencesAsync(
      options: const SharedPreferencesLinuxOptions(fileName: 'device_cache'),
    ),
  );

  static const _householdPrefix = 'household.';
  static const _listPrefix = 'list.';
  static const _seenPrefix = 'seen.';
  static const _prefsPrefix = 'listprefs.';

  /// The app language picked under More's Einstellungen; absent follows the
  /// device. Kept across sign-outs: it belongs to the device, not the
  /// account.
  static const _languageKey = 'language';

  /// The theme picked under More's Einstellungen, `light` or `dark`; absent
  /// follows the device. Kept across sign-outs like the language.
  static const _themeKey = 'theme';

  /// Analytics (job 19): the install id, the consent decision and the
  /// version of the consent text it was given under, the install id
  /// `first_open` went out for, and the internal-install mark. Kept across
  /// sign-outs: the decision is per install, not per account.
  static const _installIdKey = 'analytics.install_id';
  static const _consentKey = 'analytics.consent';
  static const _consentVersionKey = 'analytics.consent_text_version';
  static const _firstOpenKey = 'analytics.first_open';
  static const _internalKey = 'analytics.internal';

  /// The invite link the user opened and has not answered yet (job 22):
  /// `{code, at}`. Not under [forget]'s prefixes: a signed-out start (which
  /// forgets) must keep the link that is about to be signed in for.
  static const _pendingInviteKey = 'invite.pending';

  /// The List tab's dismissed tips per user (job 80), a JSON list of tip
  /// ids. Not under [forget]'s prefixes: ids only, and a user who signs in
  /// again has seen them.
  static const _tipsPrefix = 'tips.';

  /// The remote item icon table's last check (job 147): `{checked_at,
  /// body, etag}` in one value, so a cut-off write leaves the old check.
  /// Not under [forget]'s prefixes: it belongs to the device.
  static const _itemIconsKey = 'itemicons.cache';

  /// The store rating prompt's counters (job 155), one JSON value. Not
  /// under [forget]'s prefixes: they count this install's use.
  static const _reviewKey = 'review.state';

  static String _householdKey(String userId) => '$_householdPrefix$userId';

  static String _listKey(String userId, String householdId) =>
      '$_listPrefix$userId.$householdId';

  static String _seenKey(String userId, String householdId) =>
      '$_seenPrefix$userId.$householdId';

  static String _prefsKey(String userId, String householdId) =>
      '$_prefsPrefix$userId.$householdId';

  /// `de`, `en`, or null for the device's language.
  Future<String?> language() async {
    try {
      return await _prefs.getString(_languageKey);
    } on Object {
      return null;
    }
  }

  Future<void> saveLanguage(String? code) => _write(
    () => code == null
        ? _prefs.remove(_languageKey)
        : _prefs.setString(_languageKey, code),
  );

  /// `light`, `dark`, or null for the device's setting.
  Future<String?> theme() => _readString(_themeKey);

  Future<void> saveTheme(String? name) => _write(
    () => name == null
        ? _prefs.remove(_themeKey)
        : _prefs.setString(_themeKey, name),
  );

  @override
  Future<String?> installId() => _readString(_installIdKey);

  @override
  Future<void> saveInstallId(String id) =>
      _write(() => _prefs.setString(_installIdKey, id));

  @override
  Future<void> forgetInstallId() => _write(() async {
    await _prefs.remove(_installIdKey);
    await _prefs.remove(_firstOpenKey);
  });

  @override
  Future<bool?> consent() async {
    try {
      return await _prefs.getBool(_consentKey);
    } on Object {
      return null;
    }
  }

  @override
  Future<String?> consentTextVersion() => _readString(_consentVersionKey);

  @override
  Future<void> saveConsent({
    required bool granted,
    required String textVersion,
  }) => _write(() async {
    // The answer first: a yes cut off before its version is outdated, so
    // asked again; a no is a no with any version.
    await _prefs.setBool(_consentKey, granted);
    await _prefs.setString(_consentVersionKey, textVersion);
  });

  @override
  Future<void> forgetConsent() => _write(() async {
    await _prefs.remove(_consentKey);
    await _prefs.remove(_consentVersionKey);
  });

  @override
  Future<String?> firstOpenSentFor() => _readString(_firstOpenKey);

  @override
  Future<void> saveFirstOpenSentFor(String installId) =>
      _write(() => _prefs.setString(_firstOpenKey, installId));

  @override
  Future<bool> internalInstall() async {
    try {
      return await _prefs.getBool(_internalKey) ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> saveInternalInstall({required bool internal}) =>
      _write(() => _prefs.setBool(_internalKey, internal));

  @override
  Future<({String code, DateTime at})?> pendingInvite() async =>
      switch (await _readString(_pendingInviteKey)) {
        final json? => _parsePendingInvite(json),
        null => null,
      };

  static ({String code, DateTime at})? _parsePendingInvite(String json) {
    try {
      return switch (jsonDecode(json)) {
        {'code': final String code, 'at': final String at} => (
          code: code,
          at: DateTime.parse(at),
        ),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> savePendingInvite(({String code, DateTime at})? invite) =>
      _write(
        () => switch (invite) {
          (:final code, :final at) => _prefs.setString(
            _pendingInviteKey,
            jsonEncode({'code': code, 'at': at.toUtc().toIso8601String()}),
          ),
          null => _prefs.remove(_pendingInviteKey),
        },
      );

  @override
  Future<Set<String>> dismissedTips(String userId) async {
    try {
      return switch (jsonDecode(
        await _prefs.getString('$_tipsPrefix$userId') ?? '[]',
      )) {
        final List<Object?> ids => {...ids.whereType<String>()},
        _ => const {},
      };
    } on Object {
      return const {};
    }
  }

  @override
  Future<void> saveDismissedTips(String userId, Set<String> ids) => _write(
    () => _prefs.setString('$_tipsPrefix$userId', jsonEncode([...ids])),
  );

  @override
  Future<CachedItemIcons?> cachedItemIcons() async {
    try {
      return switch (jsonDecode(await _prefs.getString(_itemIconsKey) ?? '')) {
        {
          'checked_at': final String checkedAt,
          'body': final String? body,
          'etag': final String? etag,
        } =>
          CachedItemIcons(
            checkedAt: DateTime.parse(checkedAt),
            body: body,
            etag: etag,
          ),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveCachedItemIcons(CachedItemIcons cached) => _write(
    () => _prefs.setString(
      _itemIconsKey,
      jsonEncode({
        'checked_at': cached.checkedAt.toUtc().toIso8601String(),
        'body': cached.body,
        'etag': cached.etag,
      }),
    ),
  );

  @override
  Future<String?> reviewState() => _readString(_reviewKey);

  @override
  Future<void> saveReviewState(String json) =>
      _write(() => _prefs.setString(_reviewKey, json));

  Future<String?> _readString(String key) async {
    try {
      return await _prefs.getString(key);
    } on Object {
      return null;
    }
  }

  ListCache list(String userId, String householdId) =>
      _PrefsListCache(this, userId, householdId);

  /// The user's households and the one shown, as `{shown, households}`;
  /// a value from before job 169b is the one household, `{id, name}`.
  @override
  Future<({List<Household> households, String? shown})?> householdsOf(
    String userId,
  ) async {
    try {
      final json = await _prefs.getString(_householdKey(userId));
      return switch (json == null ? null : jsonDecode(json)) {
        {'households': final List<Object?> rows} && final value => (
          households: [
            for (final row in rows.whereType<Map<String, Object?>>())
              ?Household.fromJson(row),
          ],
          shown: switch (value['shown']) {
            final String id => id,
            _ => null,
          },
        ),
        final Map<String, Object?> one => switch (Household.fromJson(one)) {
          final household? => (households: [household], shown: household.id),
          null => null,
        },
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  @override
  Future<void> remember(
    String userId, {
    required List<Household> households,
    String? shown,
  }) => _write(() async {
    final key = _householdKey(userId);
    if (households.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(
        key,
        jsonEncode({
          'shown': shown,
          'households': [for (final h in households) h.toJson()],
        }),
      );
    }
    final keep = {
      for (final h in households) ...[
        _listKey(userId, h.id),
        _seenKey(userId, h.id),
        _prefsKey(userId, h.id),
      ],
    };
    await _removeWhere(
      (k) =>
          (k.startsWith('$_listPrefix$userId.') ||
              k.startsWith('$_seenPrefix$userId.') ||
              k.startsWith('$_prefsPrefix$userId.')) &&
          !keep.contains(k),
    );
  });

  @override
  Future<void> forget() => _write(
    () => _removeWhere(
      (k) =>
          k.startsWith(_householdPrefix) ||
          k.startsWith(_listPrefix) ||
          k.startsWith(_seenPrefix) ||
          k.startsWith(_prefsPrefix),
    ),
  );

  Future<void> _removeWhere(bool Function(String key) test) async {
    final keys = (await _prefs.getKeys()).where(test).toSet();
    if (keys.isNotEmpty) {
      await _prefs.clear(allowList: keys);
    }
  }

  Future<void> _write(Future<void> Function() write) async {
    try {
      await write();
    } on Object {
      // A cache write that fails only costs the next offline start.
    }
  }
}

class _PrefsListCache(
  final DeviceCache _device,
  final String _userId,
  final String _householdId,
) implements ListCache {
  @override
  Future<ListSnapshot?> load() =>
      _read(DeviceCache._listKey(_userId, _householdId), ListSnapshot.fromJson);

  @override
  Future<void> save(ListSnapshot snapshot) =>
      _store(DeviceCache._listKey(_userId, _householdId), snapshot.toJson());

  @override
  Future<SeenMark?> loadSeen() =>
      _read(DeviceCache._seenKey(_userId, _householdId), SeenMark.fromJson);

  @override
  Future<void> saveSeen(SeenMark mark) =>
      _store(DeviceCache._seenKey(_userId, _householdId), mark.toJson());

  @override
  Future<ListPrefs?> loadPrefs() =>
      _read(DeviceCache._prefsKey(_userId, _householdId), ListPrefs.fromJson);

  @override
  Future<void> savePrefs(ListPrefs prefs) =>
      _store(DeviceCache._prefsKey(_userId, _householdId), prefs.toJson());

  Future<T?> _read<T>(
    String key,
    T Function(Map<String, Object?>) parse,
  ) async {
    try {
      final json = await _device._prefs.getString(key);
      return json == null
          ? null
          : parse(jsonDecode(json) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }

  /// Skipped once the user signed out or left the household, so a list
  /// closing late cannot write its state back. A household switched away
  /// from keeps its list.
  Future<void> _store(String key, Map<String, Object?> json) =>
      _device._write(() async {
        final cached = await _device.householdsOf(_userId);
        if (cached?.households.any((h) => h.id == _householdId) ?? false) {
          await _device._prefs.setString(key, jsonEncode(json));
        }
      });
}
