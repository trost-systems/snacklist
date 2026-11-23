import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/document_language.dart';
import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/network.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_cubit.dart';
import 'package:family_groceries/feedback/feedback_inbox.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:family_groceries/feedback/screen_capture.dart';
import 'package:family_groceries/feedback/screen_tracker.dart';
import 'package:family_groceries/feedback/shake.dart';
import 'package:family_groceries/home_widget/home_widget_sync.dart';
import 'package:family_groceries/home_widget/widget_launch.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/join_decision_notices.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/household/removed_notice.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/catalog/catalog_loader.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/store_app.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:family_groceries/push/push_target.dart';
import 'package:family_groceries/report/report_repository.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:family_groceries/review/store_review.dart';
import 'package:family_groceries/session/mail_language.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:family_groceries/session/your_name.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:family_groceries/settings/integration_lock.dart';
import 'package:family_groceries/settings/shopping_day.dart';
import 'package:family_groceries/shell/push_taps.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:family_groceries/tips/hint_host.dart';
import 'package:family_groceries/tips/usage_log.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// Whether going from [before] to [after] is a join or a household switch:
/// a setback for the rating prompt (job 326, SA3). A start or a sign-in
/// into a household is none.
bool joinedOrSwitched(Session before, Session after) =>
    switch ((before, after)) {
      (NeedsHousehold(), InHousehold()) => true,
      (
        InHousehold(household: Household(id: final was)),
        InHousehold(:final household),
      ) =>
        household.id != was,
      _ => false,
    };

/// Whether going from [before] to [after] sent a feedback note of the kind
/// bug: a reason to hold the rating prompt back (job 326, SA3).
bool bugNoteSent(FeedbackState before, FeedbackState after) =>
    after.status == FeedbackStatus.sent &&
    before.status != FeedbackStatus.sent &&
    after.category == FeedbackCategory.bug;

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

  /// Whether the household has Snacklist Premium.
  required final Entitlements entitlements,

  /// Snacklist Premium's purchase; asks RevenueCat only on Buy or Restore.
  required final PurchaseCubit purchases,

  /// The purchase offer's server switch and the subscriber's own plan.
  required final PremiumServer premium,

  /// The store's prices for the Premium page; asks nothing until it opens.
  required final StorePriceReader storePrices,

  /// The invite link waiting for an answer, loaded before the first frame.
  required final PendingInvite pendingInvite,

  /// The signed-in user's name, which the name step asks for (job 297).
  required final YourNameCubit yourName,

  /// The guided start's draft (job 168b), loaded before the first frame;
  /// none by default.
  final OnboardingCubit? onboarding,

  /// Where the guided start makes the household; Supabase by default.
  final OnboardingBackend? onboardingBackend,

  /// The share sheet and clipboard; the plugins by default.
  final InviteSharer? sharer,

  /// Build and device facts for feedback; the plugins by default.
  final FeedbackDevice? feedbackDevice,

  /// Where reports of illegal content go (job 281); Supabase by default.
  final ReportRepository? report,

  /// What opens a store's chain app (job 313); the platform's by default.
  final StoreAppOpener storeApps = const PlatformStoreAppOpener(),

  /// The language picked under More's Einstellungen, read before the
  /// first frame.
  final AppLanguage? language,

  /// Keeps the account's mail language on the app's; null where no mail
  /// language is saved (tests).
  final MailLanguageSync? mailLanguage,

  /// Writes the Home Screen widgets' payload; null without widgets.
  final HomeWidgetSync? homeWidgets,

  /// Taps on the Home Screen widgets; null without widgets.
  final WidgetLaunches? widgetLaunches,

  /// The lists that tapped notifications name; null without push.
  final Stream<PushTarget>? pushTaps,

  /// The household-add alert's switch (job 377); null without push.
  final HouseholdAddAlert? householdAdd,

  /// The shopping-day reminder (job 378); none without push in the build.
  final ShoppingDayService? shoppingDay,

  /// The OS's network, which the list follows; null where it is not
  /// watched.
  final NetworkWatch? network,

  /// The item icon table, which `main` updates from the remote one; the
  /// bundled table by default.
  final ItemIconsCubit? itemIcons,

  /// The catalog the add sheet parses and guesses with, which `main`
  /// updates from the server's changes (job 274); none: the bundled one.
  final CatalogCubit? catalog,

  /// What the List tab's hints may ask and open beyond the list (job 168b);
  /// none by default.
  final HintHost hints = const HintHost(),

  /// The theme picked there; the device's setting by default.
  final ThemeMode theme = ThemeMode.system,
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
    _onboarding,
    widget.yourName,
  );
  late final _onboarding =
      widget.onboarding ??
      OnboardingCubit(widget.cache, analytics: widget.analytics);
  late final StreamSubscription<Session> _sessions;

  /// Joins, household switches and bug notes, for the rating prompt.
  late final List<StreamSubscription<Object?>> _setbacks;
  late final InviteSharer _sharer = widget.sharer ?? PlatformInviteSharer();
  late final _language = LanguageCubit(widget.cache, widget.language);
  late final _theme = ThemeCubit(widget.cache, widget.theme);
  late final _itemIcons = widget.itemIcons ?? ItemIconsCubit();
  late final _integrationLock = IntegrationLockCubit(widget.premium);

  /// Built once: a theme change only switches between them.
  final _light = appTheme(Brightness.light);
  final _dark = appTheme(Brightness.dark);
  final _screens = ScreenTracker();
  final _capture = ScreenCapture();
  late final _shake = ShakeSetting(widget.cache);
  late final _feedback = FeedbackCubit(
    widget.feedback,
    analytics: widget.analytics,
  );
  late final _inbox = FeedbackInbox(widget.feedback);
  late final FeedbackDevice _device =
      widget.feedbackDevice ?? PluginFeedbackDevice();
  final _addSheetRequest = AddSheetRequest();
  StreamSubscription<Uri?>? _widgetLaunches;
  late final _pushTaps = PushTaps(
    widget.session,
    _listLinks,
    () => _router.go(listPath),
  );
  var _mailLanguageTriggers = const <StreamSubscription<Object?>>[];

  /// Sends what analytics has queued when the app goes to the background
  /// or the tab is hidden: it may not come back. Back in front, it reads the
  /// household's unlock again: a plan may have ended meanwhile.
  late final AppLifecycleListener _lifecycle;
  late final AppLifecycleListener _reviewSessions;

  @override
  void initState() {
    super.initState();
    _reviewSessions = widget.reviewPrompt.followLifecycle();
    _onboarding.sessionChanged(widget.session.state);
    _sessions = widget.session.stream.listen(_onboarding.sessionChanged);
    var session = widget.session.state;
    var note = _feedback.state;
    _setbacks = [
      widget.session.stream.listen((next) {
        if (joinedOrSwitched(session, next)) {
          unawaited(widget.reviewPrompt.setback());
        }
        session = next;
      }),
      _feedback.stream.listen((next) {
        if (bugNoteSent(note, next)) {
          unawaited(widget.reviewPrompt.bugNoted());
        }
        note = next;
      }),
    ];
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(widget.analytics.flush()),
      onResume: () {
        _syncMailLanguage();
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
    if (widget.pushTaps case final taps?) {
      _pushTaps.follow(taps);
    }
    if (widget.mailLanguage != null) {
      // On start (web: on load), on a sign-in and on a language pick; the
      // device's language is read again on every resume.
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncMailLanguage());
      // A no-op signed out or when nothing changed, so every session state
      // may ask.
      _mailLanguageTriggers = [
        widget.session.stream.listen((_) => _syncMailLanguage()),
        _language.stream.listen((_) => _syncMailLanguage()),
      ];
    }
  }

  /// Saves the language the app shows as the account's mail language when
  /// it changed; never waits or fails.
  void _syncMailLanguage() {
    unawaited(
      widget.mailLanguage?.sync(
        resolveLocale(
          WidgetsBinding.instance.platformDispatcher.locales,
          _language.state,
        ),
      ),
    );
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
      _capture.visit(configuration.uri);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _reviewSessions.dispose();
    unawaited(_widgetLaunches?.cancel());
    unawaited(_pushTaps.cancel());
    for (final trigger in _mailLanguageTriggers) {
      unawaited(trigger.cancel());
    }
    unawaited(_sessions.cancel());
    for (final setback in _setbacks) {
      unawaited(setback.cancel());
    }
    if (widget.onboarding == null) {
      unawaited(_onboarding.close());
    }
    _router.routerDelegate.removeListener(_onRoute);
    _router.dispose();
    _popups.dispose();
    _listLinks.dispose();
    unawaited(_language.close());
    unawaited(_feedback.close());
    unawaited(_inbox.close());
    unawaited(_shake.close());
    _capture.dispose();
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
      RepositoryProvider<HintStore>.value(value: widget.cache),
      RepositoryProvider.value(value: widget.hints),
      RepositoryProvider<OnboardingBackend>(
        create: (_) =>
            widget.onboardingBackend ??
            SupabaseOnboardingBackend(Supabase.instance.client),
      ),
      RepositoryProvider.value(value: widget.account),
      RepositoryProvider<ReportRepository>(
        create: (_) =>
            widget.report ?? SupabaseReportRepository(Supabase.instance.client),
      ),
      RepositoryProvider.value(value: _screens),
      RepositoryProvider.value(value: _capture),
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
      RepositoryProvider.value(value: widget.storeApps),
      RepositoryProvider<ShoppingDayService?>.value(value: widget.shoppingDay),
      if (widget.homeWidgets case final homeWidgets?)
        RepositoryProvider.value(value: homeWidgets),
      if (widget.network case final network?)
        RepositoryProvider.value(value: network),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: widget.session),
        BlocProvider.value(value: _onboarding),
        BlocProvider.value(value: widget.yourName),
        BlocProvider.value(value: widget.entitlements),
        BlocProvider.value(value: widget.purchases),
        BlocProvider.value(value: widget.analytics),
        BlocProvider.value(value: widget.analytics.flags),
        BlocProvider.value(value: _language),
        BlocProvider.value(value: _feedback),
        BlocProvider.value(value: _inbox),
        BlocProvider.value(value: _shake),
        BlocProvider.value(value: _theme),
        BlocProvider.value(value: _integrationLock),
        BlocProvider.value(value: _itemIcons),
        if (widget.householdAdd case final alert?)
          BlocProvider.value(value: alert),
        if (widget.catalog case final catalog?)
          BlocProvider.value(value: catalog),
      ],
      child: Builder(
        builder: (context) => MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: _light,
          darkTheme: _dark,
          themeMode: context.watch<ThemeCubit>().state,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: switch (context.watch<LanguageCubit>().state) {
            final picked? => Locale(picked.code),
            null => null,
          },
          localeListResolutionCallback: (preferred, _) =>
              resolveLocale(preferred, null),
          routerConfig: _router,
          builder: (context, child) {
            setDocumentLanguage(Localizations.localeOf(context).languageCode);
            // What a feedback screenshot shows: the app, popups included.
            return _capture.wrap(
              NoticesHost(
                popups: _popups,
                child: RemovedNotices(
                  router: _router,
                  child: JoinDecisionNotices(
                    router: _router,
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
            );
          },
        ),
      ),
    ),
  );
}
