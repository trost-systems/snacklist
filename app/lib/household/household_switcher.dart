import 'dart:async';
import 'dart:math';
import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/measured_width.dart';
import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/default_list.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invite_sheet.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The switcher (PLAN S1, job 169b): the shown household's name with an
/// expand icon, top left of the list, a raised button like Anpassen. It
/// opens [showHouseholdSheet]. Shown with one household too, so a second
/// one can be found. As wide as its name, at most [maxWidth] ([widest]),
/// with the bar's gap after it; [onWidth] hears the width it took, gap
/// included, after each layout that changed it.
class const HouseholdChip({
  required final double maxWidth,
  final ValueChanged<double>? onWidth,
  super.key,
}) extends StatelessWidget {
  /// The largest share of the bar's row the chip takes.
  static const _share = 0.55;

  /// Anpassen at its widest, until it is measured.
  static const _anpassen = 160.0;

  /// The sync pill's least width.
  static const _pill = HlSize.target;

  /// The least the chip needs: its padding between the hex tips, the
  /// expand icon and a letter or two. Narrower, it steps aside (320 px at
  /// large text while the sync pill shows).
  static const _least = 2 * (HlHex.tip * HlSize.target + HlSpace.s3) + 44;

  /// The widest the chip may be in a top bar [row] wide: [_share] of it,
  /// and room for [anpassen] (its width; 0 while unknown) and, while there
  /// is [trouble], the sync pill (which then shows its icon alone). 0 when
  /// that leaves it too little.
  static double widest(
    double row, {
    required double anpassen,
    required bool trouble,
  }) {
    final room = min(
      row * _share,
      row -
          (anpassen > 0 ? anpassen : _anpassen) -
          (trouble ? _pill : 0) -
          // The gaps after the chip, the pill's slot and the new adds.
          3 * HlSpace.s2,
    );
    return room < _least ? 0 : room;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // No session above: a list on its own (tests, Widgetbook) has no chip.
    final session = context.watch<SessionCubit?>()?.state;
    return MeasuredWidth(
      onWidth: onWidth,
      child: session is! InHousehold || maxWidth <= 0
          ? const SizedBox.shrink()
          : Padding(
              // The bar's gap after it: no gap while it steps aside.
              padding: const EdgeInsetsDirectional.only(end: HlSpace.s2),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Semantics(
                  container: true,
                  hint: l10n.householdSwitch,
                  // As Anpassen: on the web the rows under the chip keep
                  // their tappable semantics elements, which would take the
                  // click.
                  hitTestBehavior: SemanticsHitTestBehavior.opaque,
                  child: OutlinedButton.icon(
                    key: const ValueKey('household-chip'),
                    // Desktop's compact density would shrink it under 48 px.
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.standard,
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.expand_more, size: 18),
                    label: Text(
                      session.household.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => unawaited(
                      showHouseholdSheet(context, openNow: _openNow(context)),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  /// The shown household's open items now, on every list, pending changes
  /// included; null until it loaded.
  static int? _openNow(BuildContext context) {
    final state = context.read<ListCubit>().state;
    return state.loaded
        ? state.allItems.values
              .where((i) => i.status == ItemStatus.active)
              .length
        : null;
  }
}

/// The user's households, one row each with a check on the shown one and
/// "Leute einladen" ([showInviteSheet]), and greyed rows for the join
/// requests waiting; then "Neuer Haushalt", "Mit Code
/// beitreten", and the default for Siri, Alexa & KI, which opens
/// [showDefaultPicker], with the list they add to there
/// ([DefaultListPicker]). [openNow] counts the shown list's open items better
/// than the server's last answer.
Future<void> showHouseholdSheet(BuildContext context, {int? openNow}) {
  // Fresh counts while the sheet opens; offline it shows the last ones.
  unawaited(context.read<SessionCubit>().refresh().catchError((Object _) {}));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (_) => HouseholdSheet(openNow: openNow),
  );
}

class const HouseholdSheet({final int? openNow, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final session = context.watch<SessionCubit>().state;
    if (session is! InHousehold) {
      return const SizedBox.shrink();
    }
    final shown = session.household;
    return SafeArea(
      child: ListView(
        key: const ValueKey('household-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: HlSpace.s3),
        children: [
          HouseholdSheetTitle(l10n.householdsTitle),
          for (final household in session.households)
            householdTile(
              context,
              household: household,
              shown: household.id == shown.id,
              open: household.id == shown.id
                  ? openNow ?? household.openCount
                  : household.openCount,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (household.id == shown.id)
                    Icon(
                      Icons.check,
                      key: const ValueKey('household-current'),
                      color: t.text,
                      semanticLabel: l10n.householdCurrent,
                    ),
                  IconButton(
                    key: ValueKey('household-invite-${household.id}'),
                    tooltip: l10n.inviteSheetOpen(household.name),
                    icon: const Icon(Icons.person_add_outlined),
                    onPressed: () => unawaited(
                      showInviteSheet(
                        context,
                        household,
                        from: InviteContext.switcher,
                      ),
                    ),
                  ),
                ],
              ),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(context.read<SessionCubit>().switchTo(household.id));
              },
            ),
          ...householdSheetTail(context, session),
        ],
      ),
    );
  }
}

/// A household sheet's title.
class const HouseholdSheetTitle(final String text, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, HlSpace.s2),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

/// The pointy hex in front of a row of the household sheets.
Widget sheetHex(BuildContext context, IconData icon, Color face) => PointyHex(
  face: face,
  size: 34,
  child: Icon(
    icon,
    size: 18,
    color: SnacklistColors.of(Theme.of(context).brightness).text,
  ),
);

/// [household]'s row in the household sheets: its name, members and [open]
/// items, honey and selected when it is the [shown] one.
Widget householdTile(
  BuildContext context, {
  required Household household,
  required bool shown,
  required int open,
  required Widget trailing,
  required VoidCallback onTap,
}) {
  final l10n = AppLocalizations.of(context);
  final t = SnacklistColors.of(Theme.of(context).brightness);
  return ListTile(
    key: ValueKey('household-row-${household.id}'),
    minTileHeight: 64,
    leading: sheetHex(
      context,
      Icons.home_outlined,
      shown ? t.honeySoft : t.surfaceSunken,
    ),
    title: Text(household.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [
        l10n.householdMembers(household.memberCount),
        l10n.householdOpenItems(open),
      ].join(' · '),
    ),
    trailing: trailing,
    selected: shown,
    onTap: onTap,
  );
}

/// What the households sheet shows below the households: the join requests
/// waiting (greyed), "Neuer Haushalt", "Mit Code beitreten", and the
/// default household and list for Siri, Alexa & KI. The switcher sheet's
/// first page (job 229) has them too, there as one row naming both that
/// opens [voiceDefault] (job 248).
List<Widget> householdSheetTail(
  BuildContext context,
  InHousehold session, {
  VoidCallback? voiceDefault,
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final t = SnacklistColors.of(theme.brightness);
  void go(String path) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(path);
  }

  return [
    // Asked to join, not in it yet (job 169b W3 M): greyed, no switching
    // into it; a tap offers to withdraw.
    for (final request in session.requests)
      ListTile(
        key: ValueKey('household-request-${request.householdId}'),
        minTileHeight: 64,
        textColor: t.textMuted,
        leading: PointyHex(
          face: t.surfaceSunken,
          contour: t.divider,
          size: 34,
          child: Icon(
            Icons.hourglass_top_outlined,
            size: 18,
            color: t.textMuted,
          ),
        ),
        title: Text(
          request.householdName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(l10n.joinRequestPending),
        onTap: () => unawaited(_offerWithdraw(context, request)),
      ),
    Divider(height: HlSpace.s4, indent: 72, color: t.divider),
    ListTile(
      key: const ValueKey('household-new'),
      leading: sheetHex(context, Icons.add, t.surfaceSunken),
      title: Text(l10n.newHousehold),
      onTap: () => go(newHouseholdPath),
    ),
    ListTile(
      key: const ValueKey('household-join'),
      leading: sheetHex(context, Icons.group_add_outlined, t.surfaceSunken),
      title: Text(l10n.joinWithCode),
      onTap: () => go(joinCodePath),
    ),
    Divider(height: HlSpace.s4, indent: 72, color: t.divider),
    if (voiceDefault case final open?)
      ListTile(
        key: const ValueKey('household-default-row'),
        // The hex and the chevron sit beside the label only: the names
        // below get the row's width, which large text needs, else a long
        // word breaks mid-word.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: HlSpace.s4,
              children: [
                sheetHex(
                  context,
                  Icons.record_voice_over_outlined,
                  t.accentSoft,
                ),
                Expanded(
                  child: Text(
                    l10n.voiceDefaultLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: t.textMuted,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            Padding(
              // Under the label at normal sizes; from 150 % on, from the
              // row's start.
              padding: EdgeInsetsDirectional.only(
                start: MediaQuery.textScalerOf(context).scale(1) < 1.5
                    ? 34 * PointyHex.aspect + HlSpace.s4
                    : 0,
              ),
              // No ellipsis, unlike the household rows: a cut name could
              // name the wrong household or list.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _voiceName(
                    context,
                    Icons.home_outlined,
                    session.defaultHousehold.name,
                    l10n.voiceDefaultHouseholdName(
                      session.defaultHousehold.name,
                    ),
                  ),
                  DefaultListPicker(
                    householdId: session.defaultHousehold.id,
                    single: true,
                    builder: (context, list, _) => _voiceName(
                      context,
                      Icons.checklist,
                      list,
                      l10n.defaultListRow(list),
                      key: const ValueKey('household-default-list-name'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        onTap: open,
      )
    else ...[
      ListTile(
        key: const ValueKey('household-default-row'),
        leading: sheetHex(
          context,
          Icons.record_voice_over_outlined,
          t.accentSoft,
        ),
        title: Text(
          l10n.voiceDefaultRow(session.defaultHousehold.name),
          style: theme.textTheme.bodyMedium,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(showDefaultPicker(context)),
      ),
      DefaultListPicker(
        householdId: session.defaultHousehold.id,
        builder: (context, list, pick) => ListTile(
          key: const ValueKey('household-default-list-row'),
          leading: sheetHex(context, Icons.checklist, t.accentSoft),
          title: Text(
            l10n.defaultListRow(list),
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.expand_more),
          onTap: pick,
        ),
      ),
    ],
  ];
}

/// A name in the row for Siri, Alexa & KI: [icon] tells the household
/// from the list where names wrap, and screen readers hear [label]. The
/// icon is a glyph of the text, so the name wraps under it at full width
/// and the line merges into the row's semantics.
Widget _voiceName(
  BuildContext context,
  IconData icon,
  String name,
  String label, {
  Key? key,
}) {
  final t = SnacklistColors.of(Theme.of(context).brightness);
  return Text.rich(
    key: key,
    TextSpan(
      children: [
        TextSpan(
          text: String.fromCharCode(icon.codePoint),
          semanticsLabel: '',
          // An icon draws inside its box: a bit larger to match the
          // letters, on the line's own height.
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize:
                (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16) * 1.2,
            height: 1,
            color: t.textMuted,
          ),
        ),
        TextSpan(text: ' $name', semanticsLabel: label),
      ],
    ),
  );
}

/// Asks whether to withdraw [request], and does.
Future<void> _offerWithdraw(BuildContext context, JoinRequest request) async {
  final session = context.read<SessionCubit>();
  final notices = Notices.of(context);
  final l10n = AppLocalizations.of(context);
  final withdraw = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const ValueKey('join-request-withdraw-dialog'),
      title: Text(l10n.joinRequestWithdrawFor(request.householdName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('join-request-withdraw-confirm'),
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(l10n.joinRequestWithdraw),
        ),
      ],
    ),
  );
  if (withdraw != true) {
    return;
  }
  try {
    await session.withdrawJoinRequest(request.householdId);
  } on HouseholdError catch (e) {
    notices.showSnackBar(
      SnackBar(content: Text(householdProblemText(l10n, e.problem))),
    );
  }
}

/// Picks the household Siri, Alexa and AI assistants use.
Future<void> showDefaultPicker(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _DefaultPicker());

class const _DefaultPicker() extends StatefulWidget {
  @override
  State<_DefaultPicker> createState() => _DefaultPickerState();
}

class _DefaultPickerState() extends State<_DefaultPicker> {
  var _busy = false;

  Future<void> _pick(String householdId) async {
    final l10n = AppLocalizations.of(context);
    final notices = Notices.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await context.read<SessionCubit>().setDefault(householdId);
      navigator.pop();
    } on HouseholdError catch (e) {
      notices.showSnackBar(
        SnackBar(content: Text(householdProblemText(l10n, e.problem))),
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = context.watch<SessionCubit>().state;
    if (session is! InHousehold) {
      return const SizedBox.shrink();
    }
    return AlertDialog(
      key: const ValueKey('household-default-picker'),
      title: Text(l10n.voiceDefaultTitle),
      contentPadding: const EdgeInsets.fromLTRB(0, HlSpace.s4, 0, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(l10n.voiceDefaultBody),
            ),
            const SizedBox(height: HlSpace.s2),
            IgnorePointer(
              ignoring: _busy,
              child: RadioGroup<String>(
                groupValue: session.defaultHousehold.id,
                onChanged: (id) {
                  if (id != null && id != session.defaultHousehold.id) {
                    unawaited(_pick(id));
                  }
                },
                child: Column(
                  children: [
                    for (final household in session.households)
                      HexRadioTile<String>(
                        key: ValueKey('household-default-${household.id}'),
                        value: household.id,
                        title: Text(household.name),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
