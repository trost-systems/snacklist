import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/open_app_platform.dart';
import 'package:family_groceries/app/store_listings.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

// The web app's „Öffnen“ card in a phone's browser (job 271, JH2 decision
// 4): on every page load, until its X, it offers the installed app.

/// A phone whose browser shows the web app; tablets and desktops are none.
enum PhoneOs() {
  ios,
  android,
}

/// The phone [userAgent] names: an iPhone or iPod, or Android with
/// `Mobile` (Android tablets leave it out). An iPad is no phone, and since
/// iPadOS 13 its Safari names a Mac anyway.
PhoneOs? phoneOsOf(String userAgent) {
  if (userAgent.contains('iPhone') || userAgent.contains('iPod')) {
    return PhoneOs.ios;
  }
  if (userAgent.contains('Android') && userAgent.contains('Mobile')) {
    return PhoneOs.android;
  }
  return null;
}

/// What „Öffnen“ does: `app` opens the installed app on its list; Safari
/// stays on the page when no app takes it, and then goes to `store`, the
/// public listing, if there is one.
typedef AppOpening = ({String app, String? store});

/// The opening on [os] from [page], the web app's address.
///
/// iOS: Safari opens no universal link to the page's own domain, so the
/// app's custom scheme (Info.plist) carries `/list`. The router reads only
/// a link's path, and supabase_flutter takes a link for a sign-in only
/// with `code`, `access_token` or an `error` in it.
///
/// Android: an intent for the App Link `https://app.snacklist.app/list`
/// in the app. Without the app Chrome goes to the fallback, and without a
/// fallback to the package's Play page, listed or not: an unlisted app
/// falls back to [page] itself.
AppOpening appOpening(
  PhoneOs os, {
  required Uri page,
  required StoreListings listings,
}) {
  final fallback = listings.googlePlay ? playStoreUrl : page.toString();
  return switch (os) {
    PhoneOs.ios => (
      app: 'com.snacklist.app://open/list',
      store: listings.appStore ? appStoreUrl : null,
    ),
    PhoneOs.android => (
      app:
          'intent://app.snacklist.app/list#Intent;scheme=https;'
          'package=$playPackage;'
          'S.browser_fallback_url=${Uri.encodeComponent(fallback)};end',
      store: null,
    ),
  };
}

/// The phone the web app runs on and the way to its app. Tests pass their
/// own.
abstract interface class AppOpener() {
  /// Null in the apps, a tablet's or a desktop's browser.
  PhoneOs? get phone;

  void open(AppOpening opening);
}

class const PlatformAppOpener() implements AppOpener {
  @override
  PhoneOs? get phone => switch (browserUserAgent()) {
    final agent? => phoneOsOf(agent),
    null => null,
  };

  @override
  void open(AppOpening opening) =>
      navigateToApp(opening.app, store: opening.store);
}

/// Closed for this page load: the next load shows the card again.
final _closedThisLoad = ValueNotifier(false);

/// The list's top slot for [OpenAppCard]: with JH2 on, in a phone's
/// browser, until closed.
class const OpenAppSlot({
  final AppOpener opener = const PlatformAppOpener(),

  /// Whether the card was closed; the page load's by default.
  final ValueNotifier<bool>? closed,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final on = context.select<Flags?, bool>(
      (f) => f?.isOn(joinHouseholdJh2Flag) ?? false,
    );
    final phone = on ? opener.phone : null;
    if (phone == null) {
      return const SizedBox.shrink();
    }
    final closed = this.closed ?? _closedThisLoad;
    return ValueListenableBuilder(
      valueListenable: closed,
      builder: (context, isClosed, _) => isClosed
          ? const SizedBox.shrink()
          : OpenAppCard(
              onOpen: () => opener.open(
                appOpening(phone, page: Uri.base, listings: storeListings),
              ),
              onClose: () => closed.value = true,
            ),
    );
  }
}

/// „Snacklist funktioniert in der App besser.“, „Öffnen“ and a close X.
class const OpenAppCard({
  required final VoidCallback onOpen,
  required final VoidCallback onClose,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HlSpace.s3,
        vertical: HlSpace.s2,
      ),
      child: Semantics(
        container: true,
        child: HlSticker(
          key: const ValueKey('open-app-card'),
          depth: StickerDepth.s,
          color: t.accentSoft,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              HlSpace.s3,
              HlSpace.s3,
              HlSpace.s1,
              HlSpace.s2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: HlSpace.s1,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: HlSpace.s2,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.phone_iphone_outlined,
                        color: t.onAccentSoft,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        l10n.openAppText,
                        style: HlType.title.copyWith(color: t.onAccentSoft),
                      ),
                    ),
                    // A label, not a tooltip: on the web a showing tooltip
                    // moves the route's semantics.
                    Semantics(
                      container: true,
                      button: true,
                      label: l10n.close,
                      excludeSemantics: true,
                      onTap: onClose,
                      child: IconButton(
                        key: const ValueKey('open-app-close'),
                        onPressed: onClose,
                        icon: Icon(Icons.close, color: t.onAccentSoft),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: HlSpace.s2),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton(
                      key: const ValueKey('open-app-open'),
                      onPressed: onOpen,
                      child: Text(l10n.openAppAction),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
