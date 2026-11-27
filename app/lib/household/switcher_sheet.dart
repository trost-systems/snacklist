import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/household_switcher.dart';
import 'package:family_groceries/household/member_tiles.dart';
import 'package:family_groceries/household/switcher_household.dart';
import 'package:family_groceries/household/voice_default_pages.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_holds.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The switcher sheet of the decluttered list (job 229, flag
/// `list-declutter`): today's household sheet as its first page, a page per
/// household with its lists, one with its members and one to invite people
/// (job 242). It opens on the shown household's page, never taller than the
/// room below the status bar, or on [initial] (job 258: where the invite
/// hints lead). Needs the `ListScope` above [context].
Future<void> showSwitcherSheet(BuildContext context, {SwitcherPage? initial}) {
  // Fresh counts while the sheet opens; offline it shows the last ones.
  unawaited(context.read<SessionCubit>().refresh().catchError((Object _) {}));
  final holds = context.read<ListHolds>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (_) => RepositoryProvider<ListHolds>.value(
      value: holds,
      child: SwitcherSheet(initial: initial),
    ),
  );
}

/// Which page the switcher sheet shows.
sealed class const SwitcherPage() {
  /// Where back goes; null on the first page, where back closes the sheet.
  SwitcherPage? get back => switch (this) {
    HouseholdsPage() => null,
    HouseholdListsPage() => const HouseholdsPage(),
    MembersPage(:final householdId) => HouseholdListsPage(householdId),
    InvitePage(:final householdId) => MembersPage(householdId),
    VoiceHouseholdsPage() => const HouseholdsPage(),
    VoiceListsPage() => const VoiceHouseholdsPage(),
  };
}

/// The user's households, as the household sheet shows them.
final class const HouseholdsPage() extends SwitcherPage;

/// A page of one household, which [SwitcherHousehold] shows.
sealed class const HouseholdPage(final String householdId) extends SwitcherPage;

/// A household's name, its members row and its lists.
final class const HouseholdListsPage(super.householdId) extends HouseholdPage;

/// A household's members and its open person invites.
final class const MembersPage(super.householdId) extends HouseholdPage;

/// "Leute einladen" for a household: person invites and the group link.
final class const InvitePage(super.householdId) extends HouseholdPage;

/// The household Siri, Alexa and AI assistants use (job 248).
final class const VoiceHouseholdsPage() extends SwitcherPage;

/// The list they add to in [householdId], one of its [lists], when no list
/// is named; picking one saves it and the household (job 248).
final class const VoiceListsPage(
  final String householdId,
  final List<HouseholdList> lists,
) extends SwitcherPage;

class const SwitcherSheet({final SwitcherPage? initial, super.key})
    extends StatefulWidget {
  @override
  State<SwitcherSheet> createState() => _SwitcherSheetState();
}

class _SwitcherSheetState() extends State<SwitcherSheet> {
  late final ListHolds _holds = context.read<ListHolds>();

  /// The household shown when the sheet opened, and its list, whose open
  /// items count better than the server's last answer.
  String? _shownId;
  ListCubit? _shownList;

  late SwitcherPage _page =
      widget.initial ??
      switch (context.read<SessionCubit>().state) {
        InHousehold(:final household) => HouseholdListsPage(household.id),
        _ => const HouseholdsPage(),
      };

  @override
  void initState() {
    super.initState();
    if (context.read<SessionCubit>().state case InHousehold(:final household)) {
      _shownId = household.id;
      _shownList = _holds.hold(household.id);
    }
  }

  @override
  void dispose() {
    if (_shownId case final id?) {
      _holds.release(id);
    }
    super.dispose();
  }

  /// Counts page changes.
  var _visit = 0;

  void _go(SwitcherPage page) => setState(() {
    _page = page;
    _visit++;
  });

  /// [_go] for a page that goes on after an answer: only while it is still
  /// the page shown. One left meanwhile, also one still fading out, goes
  /// nowhere.
  ValueChanged<SwitcherPage> _goFrom(int visit) => (page) {
    if (mounted && visit == _visit) {
      _go(page);
    }
  };

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    if (session is! InHousehold) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    Household? householdOf(String id) =>
        session.households.where((h) => h.id == id).firstOrNull;
    // A household left or removed meanwhile: the households show.
    final page = switch (_page) {
      HouseholdPage(:final householdId) || VoiceListsPage(:final householdId)
          when householdOf(householdId) == null =>
        const HouseholdsPage(),
      final page => page,
    };
    final backTo = switch (page) {
      HouseholdsPage() => null,
      HouseholdListsPage() => l10n.switcherHouseholds,
      MembersPage(:final householdId) => householdOf(householdId)?.name,
      InvitePage() => l10n.householdMembersTitle,
      VoiceHouseholdsPage() => l10n.switcherHouseholds,
      VoiceListsPage() => l10n.voiceDefaultBack,
    };
    final duration = hlMotion(context, HlDuration.short);
    // The system back goes a page back; a tap beside the sheet, Escape, a
    // drag down or ✕ closes it from any page.
    final view = BackButtonListener(
      onBackButtonPressed: () async {
        if (page.back case final back?) {
          _go(back);
          return true;
        }
        return false;
      },
      child: SafeArea(
        key: const ValueKey('switcher-sheet'),
        // Back and Schließen stay put while a long page scrolls under them.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: switch ((page.back, backTo)) {
                    (final back?, final label?) => SwitcherBackRow(
                      label,
                      onBack: () => _go(back),
                    ),
                    _ => const SizedBox.shrink(),
                  },
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: HlSpace.s2),
                  child: IconButton(
                    key: const ValueKey('switcher-close'),
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.standard,
                    ),
                    tooltip: l10n.close,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
            Flexible(
              child: AnimatedSize(
                duration: duration,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: duration,
                  layoutBuilder: _topAligned,
                  child: switch (page) {
                    HouseholdsPage() => _HouseholdsView(
                      key: const ValueKey('switcher-households'),
                      session: session,
                      open: (id) => _go(HouseholdListsPage(id)),
                      voiceDefault: () => _go(const VoiceHouseholdsPage()),
                    ),
                    // A visit of its own: back and forth within the page
                    // change gets a fresh step, not the one fading out.
                    VoiceHouseholdsPage() => KeyedSubtree(
                      key: ValueKey(('voice', _visit)),
                      child: VoiceHouseholdsView(
                        key: const ValueKey('switcher-voice-households'),
                        session: session,
                        go: _goFrom(_visit),
                      ),
                    ),
                    VoiceListsPage(:final householdId, :final lists) =>
                      KeyedSubtree(
                        key: ValueKey(('voice', _visit)),
                        child: VoiceListsView(
                          key: ValueKey('switcher-voice-lists-$householdId'),
                          household: session.households.firstWhere(
                            (h) => h.id == householdId,
                          ),
                          lists: lists,
                          go: _goFrom(_visit),
                        ),
                      ),
                    HouseholdPage(:final householdId) => SwitcherHousehold(
                      key: ValueKey('switcher-household-$householdId'),
                      userId: session.userId,
                      household: session.households.firstWhere(
                        (h) => h.id == householdId,
                      ),
                      shown: session.household.id == householdId,
                      page: page,
                      go: _go,
                    ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return switch (_shownList) {
      final list? => BlocProvider.value(value: list, child: view),
      null => view,
    };
  }
}

/// AnimatedSwitcher's layout with the pages at the top: the sheet grows
/// and shrinks at its top edge, not around its middle.
Widget _topAligned(Widget? current, List<Widget> previous) =>
    Stack(alignment: Alignment.topCenter, children: [...previous, ?current]);

/// The first page: today's household sheet, where a row opens the
/// household's page instead of switching to it, and long-press then drag
/// orders the households.
class const _HouseholdsView({
  required final InHousehold session,
  required final ValueChanged<String> open,

  /// Opens the pages for Siri, Alexa and AI.
  required final VoidCallback voiceDefault,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final households = session.households;
    final shown = session.household.id;
    return CustomScrollView(
      shrinkWrap: true,
      slivers: [
        SliverToBoxAdapter(child: HouseholdSheetTitle(l10n.householdsTitle)),
        SliverReorderableList(
          itemCount: households.length,
          proxyDecorator: liftedRow,
          onReorderItem: (from, to) {
            final ids = [for (final h in households) h.id];
            ids.insert(to, ids.removeAt(from));
            unawaited(_reorder(context, ids));
          },
          itemBuilder: (context, i) {
            final household = households[i];
            final isShown = household.id == shown;
            return ReorderableRow(
              key: ValueKey(household.id),
              index: i,
              count: households.length,
              move: (to) {
                final ids = [for (final h in households) h.id];
                ids.insert(to, ids.removeAt(i));
                unawaited(_reorder(context, ids));
              },
              child: householdTile(
                context,
                household: household,
                shown: isShown,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isShown)
                      Icon(
                        Icons.check,
                        key: const ValueKey('household-current'),
                        color: t.text,
                        semanticLabel: l10n.householdCurrent,
                      ),
                    Icon(Icons.chevron_right, color: t.textMuted),
                  ],
                ),
                onTap: () => open(household.id),
              ),
            );
          },
        ),
        SliverList.list(
          children: householdSheetTail(
            context,
            session,
            voiceDefault: voiceDefault,
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: HlSpace.s3)),
      ],
    );
  }

  static Future<void> _reorder(BuildContext context, List<String> ids) {
    final session = context.read<SessionCubit>();
    return tellRefusal(context, () => session.reorderHouseholds(ids));
  }
}

/// A row that long-press then drag moves within its
/// [SliverReorderableList], and that screen readers move with "Nach oben"
/// and "Nach unten" ([move] gets the new index).
class const ReorderableRow({
  required final int index,
  required final int count,
  required final ValueChanged<int> move,
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      customSemanticsActions: {
        if (index > 0)
          CustomSemanticsAction(label: l10n.listMoveUp): () => move(index - 1),
        if (index < count - 1)
          CustomSemanticsAction(label: l10n.listMoveDown): () =>
              move(index + 1),
      },
      child: ReorderableDelayedDragStartListener(index: index, child: child),
    );
  }
}

/// A row while it is dragged: lifted off the sheet on the sheet's own
/// surface.
Widget liftedRow(Widget child, int index, Animation<double> animation) =>
    AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final theme = Theme.of(context);
        final lift = Curves.easeOut.transform(animation.value);
        return Material(
          elevation: HlSticker.elevation(lerpDouble(0, 6, lift) ?? 0),
          color:
              theme.bottomSheetTheme.backgroundColor ??
              theme.colorScheme.surface,
          borderRadius: const BorderRadius.all(Radius.circular(HlRadius.s)),
          child: child,
        );
      },
      child: child,
    );

/// "‹ Haushalte", "‹ Zuhause" and "‹ Mitglieder": back to [label]'s page.
class const SwitcherBackRow(
  final String label, {
  required final VoidCallback onBack,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: HlSpace.s2),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const ValueKey('switcher-back'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.standard,
          minimumSize: const Size(HlSize.target, HlSize.target),
        ),
        icon: const Icon(Icons.arrow_back),
        label: Semantics(
          label: AppLocalizations.of(context).switcherBack(label),
          excludeSemantics: true,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        onPressed: onBack,
      ),
    ),
  );
}
