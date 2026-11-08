import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/network.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_cubit.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:family_groceries/feedback/screen_tracker.dart';
import 'package:family_groceries/home_widget/home_widget_sync.dart';
import 'package:family_groceries/home_widget/widget_launch.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/household/removed_notice.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:family_groceries/review/store_review.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:family_groceries/settings/integration_lock.dart';
import 'package:family_groceries/tips/tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class const App({
  required final SessionCubit session,
  required final SocialSignIn social,
  required final DeviceCache cache,
  required final AccountRepository account,
  required final Analytics analytics,
  required final FeedbackRepository feedback,

  /// Counts this install's use and asks the store for a rating when due.
  required final ReviewPrompt reviewPrompt,

  /// The store's rating prompt and listing.
  required final StoreReview storeReview,
  required final InviteRepository invites,

  /// Whether the household has Hummlist Premium.
  required final Entitlements entitlements,

  /// Hummlist Premium's purchase; asks RevenueCat only on Buy or Restore.
  required final PurchaseCubit purchases,

  /// The purchase offer's server switch and the subscriber's own plan.
  required final PremiumServer premium,

  /// The store's prices for the Premium page; asks nothing until it opens.
  required final StorePriceReader storePrices,

  /// The invite link waiting for an answer, loaded before the first frame.
  required final PendingInvite pendingInvite,

  /// The share sheet and clipboard; the plugins by default.
  final InviteSharer? sharer,

  /// Build and device facts for feedback; the plugins by default.
  final FeedbackDevice? feedbackDevice,

  /// The language picked under More's Einstellungen, read before the
  /// first frame.
  final AppLanguage? language,

  /// Writes the Home Screen widgets' payload; null without widgets.
  final HomeWidgetSync? homeWidgets,

  /// Taps on the Home Screen widgets; null without widgets.
  final WidgetLaunches? widgetLaunches,

  /// The OS's network, which the list follows; null where it is not
  /// watched.
  final NetworkWatch? network,

  /// The item icon table, which `main` updates from the remote one; the
  /// bundled table by default.
  final ItemIconsCubit? itemIcons,

  /// The theme picked there; the device's setting by default.
  final ThemeMode theme = ThemeMode.system,

  /// Whether the integration settings may show the integration lock (the
  /// `INTEGRATION_LOCK` define, job 50).
  final bool integrationLock = Environment.integrationLock,
  super.key,
}) extends StatefulWidget {
  @override
  State<App> createState() => _AppState();
}

class _AppState() extends State<App> {
  final _listLinks = ListLinks();
  final _popups = Popups();
  late final GoRouter _router = buildRouter(
    widget.session,
    widget.analytics,
    widget.pendingInvite,
    _listLinks,
    _popups,
  );
  late final InviteSharer _sharer = widget.sharer ?? PlatformInviteSharer();
  late final _language = LanguageCubit(widget.cache, widget.language);
  late final _theme = ThemeCubit(widget.cache, widget.theme);
  late final _itemIcons = widget.itemIcons ?? ItemIconsCubit();
  late final _integrationLock = IntegrationLockCubit(
    widget.premium,
    enabled: widget.integrationLock,
  );

  /// Built once: a theme change only switches between them.
  final _light = appTheme(Brightness.light);
  final _dark = appTheme(Brightness.dark);
  final _screens = ScreenTracker();
  late final _feedback = FeedbackCubit(
    widget.feedback,
    analytics: widget.analytics,
  );
  late final FeedbackDevice _device =
      widget.feedbackDevice ?? PluginFeedbackDevice();
  final _addSheetRequest = AddSheetRequest();
  StreamSubscription<Uri?>? _widgetLaunches;

  /// Sends what analytics has queued when the app goes to the background
  /// or the tab is hidden: it may not come back. Back in front, it reads the
  /// household's unlock again: a plan may have ended meanwhile.
  late final AppLifecycleListener _lifecycle;
  late final AppLifecycleListener _reviewSessions;

  @override
  void initState() {
    super.initState();
    _reviewSessions = widget.reviewPrompt.followLifecycle();
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(widget.analytics.flush()),
      onResume: () {
        unawaited(widget.entitlements.refresh());
        // Someone may have removed the user from a household meanwhile.
        if (widget.session.state case InHousehold() || NeedsHousehold()) {
          unawaited(widget.session.refresh().catchError((Object _) {}));
        }
      },
    );
    _router.routerDelegate.addListener(_onRoute);
    // The first location may be set before anyone listens (a reload on
    // `/more`): take it once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRoute());
    if (widget.widgetLaunches case final launches?) {
      _widgetLaunches = followWidgetLaunches(launches, _onWidgetLaunch);
    }
  }

  /// A widget tap opens the list; Add opens its add sheet too. Signed out,
  /// `authRedirect` sends both to sign-in.
  void _onWidgetLaunch(WidgetLaunch launch) {
    _router.go(listPath);
    if (launch == WidgetLaunch.add) {
      _addSheetRequest.request();
    }
  }

  void _onRoute() {
    final configuration = _router.routerDelegate.currentConfiguration;
    if (configuration.isNotEmpty) {
      _screens.visit(configuration.uri);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _reviewSessions.dispose();
    unawaited(_widgetLaunches?.cancel());
    _router.routerDelegate.removeListener(_onRoute);
    _router.dispose();
    _popups.dispose();
    _listLinks.dispose();
    unawaited(_language.close());
    unawaited(_feedback.close());
    unawaited(_theme.close());
    unawaited(_integrationLock.close());
    if (widget.itemIcons == null) {
      unawaited(_itemIcons.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider.value(value: widget.social),
      RepositoryProvider.value(value: widget.cache),
      RepositoryProvider<TipStore>.value(value: widget.cache),
      RepositoryProvider.value(value: widget.account),
      RepositoryProvider.value(value: _screens),
      RepositoryProvider.value(value: _device),
      RepositoryProvider.value(value: widget.invites),
      RepositoryProvider.value(value: widget.pendingInvite),
      RepositoryProvider.value(value: _listLinks),
      RepositoryProvider.value(value: _sharer),
      RepositoryProvider.value(value: widget.premium),
      RepositoryProvider.value(value: widget.storePrices),
      RepositoryProvider.value(value: _addSheetRequest),
      RepositoryProvider.value(value: widget.reviewPrompt),
      RepositoryProvider.value(value: widget.storeReview),
      if (widget.homeWidgets case final homeWidgets?)
        RepositoryProvider.value(value: homeWidgets),
      if (widget.network case final network?)
        RepositoryProvider.value(value: network),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: widget.session),
        BlocProvider.value(value: widget.entitlements),
        BlocProvider.value(value: widget.purchases),
        BlocProvider.value(value: widget.analytics),
        BlocProvider.value(value: widget.analytics.flags),
        BlocProvider.value(value: _language),
        BlocProvider.value(value: _feedback),
        BlocProvider.value(value: _theme),
        BlocProvider.value(value: _integrationLock),
        BlocProvider.value(value: _itemIcons),
      ],
      child: Builder(
        builder: (context) => MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: _light,
          darkTheme: _dark,
          themeMode: context.watch<ThemeCubit>().state,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: switch (context.watch<LanguageCubit>().state) {
            final picked? => Locale(picked.code),
            null => null,
          },
          localeListResolutionCallback: (preferred, _) =>
              resolveLocale(preferred, null),
          routerConfig: _router,
          builder: (context, child) => NoticesHost(
            popups: _popups,
            child: RemovedNotices(
              child: BlocBuilder<SessionCubit, Session>(
                builder: (context, session) => session is SessionLoading
                    ? const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      )
                    : child!,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
