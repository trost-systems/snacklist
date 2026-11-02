import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Where the app runs, as a tip targets it.
enum TipSurface() {
  ios,
  android,
  web,
  macos,
  windows,
  linux;

  static TipSurface current({
    required bool web,
    required TargetPlatform platform,
  }) => web
      ? TipSurface.web
      : switch (platform) {
          TargetPlatform.iOS => TipSurface.ios,
          TargetPlatform.macOS => TipSurface.macos,
          TargetPlatform.windows => TipSurface.windows,
          TargetPlatform.linux => TipSurface.linux,
          TargetPlatform.android ||
          TargetPlatform.fuchsia => TipSurface.android,
        };
}

/// One card of the List tab's tips (job 80).
@immutable
class const Tip({
  /// Stored once dismissed: never change or reuse one.
  required final String id,
  required final String Function(AppLocalizations l10n) title,
  required final String Function(AppLocalizations l10n) body,
  required final IconData icon,

  /// Null shows it everywhere.
  final Set<TipSurface>? surfaces,

  /// Inclusive `x.y.z` bounds on the app version; the build number is
  /// ignored.
  final String? minVersion,
  final String? maxVersion,
});

/// The tips in the order they show, one at a time. To add one: a new [Tip.id]
/// (never an old one's), its title and body under `tip…` keys at the end of
/// `app/l10n/app_de.arb` and `app_en.arb`, and [Tip.surfaces],
/// [Tip.minVersion] or [Tip.maxVersion] when it holds only somewhere.
/// Removing one is deleting its entry.
final tips = <Tip>[
  Tip(
    id: 'edit-long-press',
    title: (l10n) => l10n.tipEditTitle,
    body: (l10n) => l10n.tipEditBody,
    icon: Icons.edit_outlined,
  ),
  Tip(
    id: 'quick-add-amounts',
    title: (l10n) => l10n.tipAmountsTitle,
    body: (l10n) => l10n.tipAmountsBody,
    icon: Icons.format_list_numbered,
  ),
];

/// The first of [tips] not [dismissed] that holds on [surface] at
/// [appVersion]. A tip with a version bound needs a version to compare.
Tip? nextTip(
  List<Tip> tips, {
  required TipSurface surface,
  required String? appVersion,
  required Set<String> dismissed,
}) {
  final version = _parseVersion(appVersion);
  bool fits(Tip tip) {
    if (tip.minVersion == null && tip.maxVersion == null) {
      return true;
    }
    if (version == null) {
      return false;
    }
    final min = _parseVersion(tip.minVersion);
    final max = _parseVersion(tip.maxVersion);
    return (min == null || _compare(version, min) >= 0) &&
        (max == null || _compare(version, max) <= 0);
  }

  return tips
      .where(
        (tip) =>
            !dismissed.contains(tip.id) &&
            (tip.surfaces?.contains(surface) ?? true) &&
            fits(tip),
      )
      .firstOrNull;
}

final _version = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+.*)?$');

List<int>? _parseVersion(String? version) =>
    switch (_version.firstMatch(version?.trim() ?? '')) {
      final m? => [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)],
      null => null,
    };

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) {
      return a[i].compareTo(b[i]);
    }
  }
  return 0;
}

/// Which tips a user dismissed on this device: `DeviceCache` in the app.
abstract interface class TipStore() {
  Future<Set<String>> dismissedTips(String userId);

  Future<void> saveDismissedTips(String userId, Set<String> ids);
}
