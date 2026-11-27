import 'dart:async';

import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/core/pop_if_current.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/default_list.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invite_sheet.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The user's households, one row each with a check on the shown one and
/// "Leute einladen" ([showInviteSheet]), and greyed rows for the join
/// requests waiting; then "Neuer Haushalt", "Mit Code
/// beitreten", and the default for Siri, Alexa & KI, which opens
/// [showDefaultPicker], with the list they add to there
/// ([DefaultListPicker]).
Future<void> showHouseholdSheet(BuildContext context) {
  // Fresh counts while the sheet opens; offline it shows the last ones.
  unawaited(context.read<SessionCubit>().refresh().catchError((Object _) {}));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (_) => const HouseholdSheet(),
  );
}

class const HouseholdSheet({super.key}) extends StatelessWidget {
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

/// [household]'s row in the household sheets: its name and members, honey
/// and selected when it is the [shown] one. No count of open items (job
/// 474): it read like pending invites.
Widget householdTile(
  BuildContext context, {
  required Household household,
  required bool shown,
  required Widget trailing,
  required VoidCallback onTap,
}) {
  final l10n = AppLocalizations.of(context);
  final t = SnacklistColors.of(Theme.of(context).brightness);
  return FocusRingTile(
    key: ValueKey('household-row-${household.id}'),
    child: ListTile(
      minTileHeight: 64,
      leading: sheetHex(
        context,
        Icons.home_outlined,
        shown ? t.honeySoft : t.surfaceSunken,
      ),
      title: Text(household.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.householdMembers(household.memberCount)),
      trailing: trailing,
      selected: shown,
      onTap: onTap,
    ),
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
      FocusRingTile(
        key: ValueKey('household-request-${request.householdId}'),
        child: ListTile(
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
      ),
    Divider(height: HlSpace.s4, indent: 72, color: t.divider),
    FocusRingTile(
      key: const ValueKey('household-new'),
      child: ListTile(
        leading: sheetHex(context, Icons.add, t.surfaceSunken),
        title: Text(l10n.newHousehold),
        onTap: () => go(newHouseholdPath),
      ),
    ),
    FocusRingTile(
      key: const ValueKey('household-join'),
      child: ListTile(
        leading: sheetHex(context, Icons.group_add_outlined, t.surfaceSunken),
        title: Text(l10n.joinWithCode),
        onTap: () => go(joinCodePath),
      ),
    ),
    Divider(height: HlSpace.s4, indent: 72, color: t.divider),
    if (voiceDefault case final open?)
      FocusRingTile(
        key: const ValueKey('household-default-row'),
        child: ListTile(
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
        ),
      )
    else ...[
      FocusRingTile(
        key: const ValueKey('household-default-row'),
        child: ListTile(
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
      ),
      DefaultListPicker(
        householdId: session.defaultHousehold.id,
        builder: (context, list, pick) => FocusRingTile(
          key: const ValueKey('household-default-list-row'),
          child: ListTile(
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
      ),
    ],
  ];
}

/// A name in the row for Siri, Alexa & KI: [icon] tells the household
/// from the list where names wrap, and screen readers hear [label]. The
/// icon is a middle-aligned span of the text, centred on its line, so the
/// name wraps under it at full width and the line merges into the row's
/// semantics.
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
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(
            icon,
            size:
                (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16) *
                1.2 *
                MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.3),
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
  /// The household tapped while the server saves it, shown checked at once;
  /// a refusal puts the check back.
  String? _picked;

  Future<void> _pick(String householdId) async {
    final l10n = AppLocalizations.of(context);
    final notices = Notices.of(context);
    final session = context.read<SessionCubit>();
    setState(() => _picked = householdId);
    try {
      await session.setDefault(householdId);
      if (mounted) {
        popIfCurrent(context);
      }
    } on HouseholdError catch (e) {
      notices.showSnackBar(
        SnackBar(content: Text(householdProblemText(l10n, e.problem))),
      );
      if (mounted) {
        setState(() => _picked = null);
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
              ignoring: _picked != null,
              child: RadioGroup<String>(
                groupValue: _picked ?? session.defaultHousehold.id,
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
