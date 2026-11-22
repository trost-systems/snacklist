import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/tips/usage_log.dart';
import 'package:material_ui/material_ui.dart';

/// A hint's id: stored once shown or dismissed, sent as `hint_id`. Never
/// change or reuse a [wire] (job 80's tips kept theirs).
enum HintId(final String wire) {
  editLongPress('edit-long-press'),
  quickAddAmounts('quick-add-amounts'),
  dictation('dictation'),
  siri('siri'),
  storeOrder('store-order'),
  addStore('add-store'),
  invitePartner('invite-partner'),
  secondHousehold('second-household'),
  ownHousehold('own-household'),
  aiAssistant('ai-assistant'),
  homeWidget('home-widget');

  static HintId? parse(Object? wire) =>
      values.where((id) => id.wire == wire).firstOrNull;
}

/// Where the app runs, as a hint targets it.
enum HintPlatform() {
  ios,
  android,
  web,
  macos,
  windows,
  linux;

  static HintPlatform current({
    required bool web,
    required TargetPlatform platform,
  }) => web
      ? HintPlatform.web
      : switch (platform) {
          TargetPlatform.iOS => HintPlatform.ios,
          TargetPlatform.macOS => HintPlatform.macos,
          TargetPlatform.windows => HintPlatform.windows,
          TargetPlatform.linux => HintPlatform.linux,
          TargetPlatform.android ||
          TargetPlatform.fuchsia => HintPlatform.android,
        };

  bool get phone => this == ios || this == android;
}

/// Where a hint shows on the List tab.
enum HintPlace() {
  /// A card at the top of the list.
  card,

  /// A callout under Anpassen, pointing up at it.
  belowEdit,
}

/// A hint's one button.
enum HintAction() {
  /// More → Einladungen.
  invite,

  /// More → Zugänge.
  access,

  /// The household creation flow; only where [HintContext.canAddHousehold].
  addHousehold;

  String label(AppLocalizations l10n) => switch (this) {
    invite => l10n.hintInviteAction,
    access => l10n.hintAssistantAction,
    addHousehold => l10n.hintAddHouseholdAction,
  };
}

/// What the list knows when a hint is picked.
@immutable
class const HintContext({
  required final HintPlatform platform,

  /// When this session started: the List tab's first build.
  required final DateTime startedAt,

  /// The device kept no log for the user before this session.
  required final bool firstSession,

  /// A sheet, dialog or the keyboard is over the list.
  required final bool covered,

  /// The List tab is not on screen: another tab or a page on top of it
  /// (onboarding's steps, Anpassen).
  required final bool listHidden,

  /// Open items on the list.
  required final int items,
  required final int stores,
  required final int members,

  /// The user created the household (or the role is not known yet).
  required final bool owner,
  final HouseholdKind? kind,

  /// The app can create a second household: [HintAction.addHousehold]
  /// works. False until job 169b (`HintHost.addHousehold`).
  final bool canAddHousehold = false,

  /// Flag `hide-categories`: nothing on screen names a category.
  final bool categoriesHidden = false,
});

/// One hint: its text, when it is useful, and what retires it.
@immutable
class const Hint({
  required final HintId id,
  required final String Function(AppLocalizations l10n) title,
  required final String Function(AppLocalizations l10n) body,
  required final IconData icon,

  /// Eligible when this holds: the behaviour that makes it useful.
  required final bool Function(UsageLog log, HintContext context, DateTime now)
  when,

  /// The use that retires it for good; null where the app cannot see the
  /// use (then X, its action or three showings retire it).
  final Signal? retiredBy,
  final HintPlace place = HintPlace.card,

  /// Null shows it everywhere.
  final Set<HintPlatform>? platforms,
  final HintAction? action,

  /// It teaches categories, which flag `hide-categories` hides.
  final bool aboutCategories = false,
}) {
  /// Whether it can show at all on [platform], its action included.
  bool offered(
    HintPlatform platform, {
    required bool canAddHousehold,
    bool categoriesHidden = false,
  }) =>
      (platforms?.contains(platform) ?? true) &&
      (action != HintAction.addHousehold || canAddHousehold) &&
      !(aboutCategories && categoriesHidden);

  /// The user did what it is about.
  bool usedIn(UsageLog log) => switch (retiredBy) {
    final signal? => log.saw(signal),
    null => false,
  };

  /// It never shows again: used, X, its action, or [maxShows] showings.
  bool doneIn(UsageLog log) {
    final record = log.of(id);
    return usedIn(log) ||
        record.dismissed ||
        record.acted ||
        record.shown >= maxShows;
  }

  /// Showings without a tap after which a hint retires itself.
  static const maxShows = 3;
}

/// At most one hint shows for the first time per this.
const newHintEvery = Duration(hours: 24);

/// No hint in the first seconds after the start.
const quietAfterStart = Duration(seconds: 10);

/// Every hint, most useful first. To add one: a new [HintId] (never an old
/// one's wire), its `hint…` title and body at the end of
/// `app/l10n/app_de.arb` and `app_en.arb`, and an entry here.
final hints = <Hint>[
  Hint(
    id: HintId.invitePartner,
    title: (l10n) => l10n.hintInviteTitle,
    body: (l10n) => l10n.hintInviteBody,
    icon: Icons.person_add_outlined,
    action: HintAction.invite,
    retiredBy: Signal.memberJoined,
    when: (log, c, now) =>
        c.owner &&
        c.kind != HouseholdKind.solo &&
        c.members <= 1 &&
        c.items >= 3 &&
        now.difference(log.since) >= const Duration(days: 1),
  ),
  Hint(
    id: HintId.editLongPress,
    title: (l10n) => l10n.tipEditTitle,
    body: (l10n) => l10n.tipEditBody,
    icon: Icons.edit_outlined,
    retiredBy: Signal.itemEdited,
    when: (_, c, _) => c.items >= 5,
  ),
  Hint(
    id: HintId.quickAddAmounts,
    title: (l10n) => l10n.tipAmountsTitle,
    body: (l10n) => l10n.tipAmountsBody,
    icon: Icons.format_list_numbered,
    retiredBy: Signal.amountAdd,
    when: (log, _, _) => log.count(Signal.plainTypedAdd) >= 5,
  ),
  Hint(
    id: HintId.storeOrder,
    title: (l10n) => l10n.hintStoreOrderTitle,
    body: (l10n) => l10n.hintStoreOrderBody,
    icon: Icons.swap_vert,
    place: HintPlace.belowEdit,
    retiredBy: Signal.categoryReorder,
    aboutCategories: true,
    when: (log, c, _) => c.stores > 0 && log.saw(Signal.shopDone),
  ),
  Hint(
    id: HintId.addStore,
    title: (l10n) => l10n.hintAddStoreTitle,
    body: (l10n) => l10n.hintAddStoreBody,
    icon: Icons.storefront_outlined,
    place: HintPlace.belowEdit,
    retiredBy: Signal.storeAdded,
    when: (log, c, _) => c.stores == 0 && log.activeDays >= 3,
  ),
  Hint(
    id: HintId.dictation,
    title: (l10n) => l10n.hintDictationTitle,
    body: (l10n) => l10n.hintDictationBody,
    icon: Icons.mic_none,
    platforms: const {HintPlatform.ios, HintPlatform.android},
    retiredBy: Signal.micUsed,
    when: (log, _, _) => log.count(Signal.typedAdd) >= 10,
  ),
  Hint(
    id: HintId.aiAssistant,
    title: (l10n) => l10n.hintAssistantTitle,
    body: (l10n) => l10n.hintAssistantBody,
    icon: Icons.smart_toy_outlined,
    action: HintAction.access,
    retiredBy: Signal.assistantConnected,
    when: (log, c, _) =>
        c.kind == HouseholdKind.club ||
        (!c.platform.phone && log.activeDays >= 7),
  ),
  // Siri's adds reach the server only: the app cannot see one. Only in a
  // build with native Siri (the `native-siri` hold released): before that
  // Siri needs a Shortcut the user sets up, and the phrase would not work.
  Hint(
    id: HintId.siri,
    title: (l10n) => l10n.hintSiriTitle,
    body: (l10n) => l10n.hintSiriBody,
    icon: Icons.keyboard_voice_outlined,
    platforms: Environment.nativeSiriLive ? const {HintPlatform.ios} : const {},
    when: (log, _, _) => log.activeDays >= 3,
  ),
  Hint(
    id: HintId.homeWidget,
    title: (l10n) => l10n.hintWidgetTitle,
    body: (l10n) => l10n.hintWidgetBody,
    icon: Icons.widgets_outlined,
    platforms: const {HintPlatform.ios, HintPlatform.android},
    retiredBy: Signal.widgetPlaced,
    when: (log, _, _) => log.activeDays >= 5,
  ),
  Hint(
    id: HintId.ownHousehold,
    title: (l10n) => l10n.hintOwnHouseholdTitle,
    body: (l10n) => l10n.hintOwnHouseholdBody,
    icon: Icons.home_outlined,
    action: HintAction.addHousehold,
    retiredBy: Signal.householdOwned,
    when: (log, c, _) => !c.owner && log.activeDays >= 3,
  ),
  // The app cannot see a second household before job 169b.
  Hint(
    id: HintId.secondHousehold,
    title: (l10n) => l10n.hintSecondHouseholdTitle,
    body: (l10n) => l10n.hintSecondHouseholdBody,
    icon: Icons.add_home_outlined,
    action: HintAction.addHousehold,
    when: (log, _, _) => log.activeDays >= 14,
  ),
];

/// The hint to show in a session starting now, or null. One that showed
/// before and is not done comes back first; a new one only [newHintEvery].
/// None while something covers the list, in its first [quietAfterStart],
/// during a pause after X in a row, or in the first session while the list
/// is empty.
Hint? nextHint(
  List<Hint> registry,
  UsageLog log,
  DateTime now,
  HintContext context,
) {
  if (context.covered ||
      context.listHidden ||
      now.difference(context.startedAt) < quietAfterStart ||
      (context.firstSession && context.items == 0)) {
    return null;
  }
  if (log.pausedUntil case final until? when now.isBefore(until)) {
    return null;
  }
  final live = registry.where(
    (hint) =>
        hint.offered(
          context.platform,
          canAddHousehold: context.canAddHousehold,
          categoriesHidden: context.categoriesHidden,
        ) &&
        !hint.doneIn(log) &&
        hint.when(log, context, now),
  );
  if (live.where((hint) => log.of(hint.id).shown > 0).firstOrNull
      case final again?) {
    return again;
  }
  final due = switch (log.lastNew) {
    final last? => now.difference(last) >= newHintEvery,
    null => true,
  };
  return due ? live.firstOrNull : null;
}
