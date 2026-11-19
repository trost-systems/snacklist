import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/household_switcher.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/household/switcher_sheet.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_names.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The switcher sheet's household step for Siri, Alexa and AI (job 248,
/// [VoiceHouseholdsPage]): a tap on a household goes on to its lists
/// ([VoiceListsPage]) when it has two or more and the flag
/// `default-list-voice-target` is on; else it saves the household and goes
/// back to the households.
class const VoiceHouseholdsView({
  required final InHousehold session,
  required final ValueChanged<SwitcherPage> go,
  super.key,
}) extends StatefulWidget {
  @override
  State<VoiceHouseholdsView> createState() => _VoiceHouseholdsViewState();
}

class _VoiceHouseholdsViewState() extends State<VoiceHouseholdsView> {
  /// The household whose lists load or which saves; the rows wait.
  String? _busy;

  Future<void> _pick(String householdId) async {
    final session = context.read<SessionCubit>();
    final notices = Notices.of(context);
    final l10n = AppLocalizations.of(context);
    final listStep = context.read<Flags?>()?.isOn(defaultListFlag) ?? false;
    final go = widget.go;
    setState(() => _busy = householdId);
    try {
      if (listStep) {
        final lists = await session.lists(householdId);
        if (lists.length >= 2) {
          go(VoiceListsPage(householdId, lists));
          return;
        }
      }
      if (widget.session.defaultHousehold.id != householdId) {
        await session.setDefault(householdId);
      }
      go(const HouseholdsPage());
    } on HouseholdError catch (e) {
      notices.showSnackBar(
        SnackBar(content: Text(householdProblemText(l10n, e.problem))),
      );
    } finally {
      // Also after going on: back within the page change shows this state
      // again.
      if (mounted) {
        setState(() => _busy = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = widget.session.defaultHousehold.id;
    final listStep = context.select<Flags?, bool>(
      (flags) => flags?.isOn(defaultListFlag) ?? false,
    );
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: HlSpace.s3),
      children: [
        HouseholdSheetTitle(l10n.voiceDefaultTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(l10n.voiceDefaultBody),
        ),
        const SizedBox(height: HlSpace.s2),
        IgnorePointer(
          ignoring: _busy != null,
          child: Column(
            children: [
              for (final household in widget.session.households)
                _voiceRow(
                  context,
                  key: ValueKey('voice-household-${household.id}'),
                  icon: Icons.home_outlined,
                  name: household.name,
                  current: household.id == current,
                  more: listStep,
                  busy: _busy == household.id,
                  onTap: () => unawaited(_pick(household.id)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The switcher sheet's list step for Siri, Alexa and AI (job 248,
/// [VoiceListsPage]): a tap on one of [household]'s [lists] saves it and,
/// when it is another, the household, then goes back to the households.
class const VoiceListsView({
  required final Household household,
  required final List<HouseholdList> lists,
  required final ValueChanged<SwitcherPage> go,
  super.key,
}) extends StatefulWidget {
  @override
  State<VoiceListsView> createState() => _VoiceListsViewState();
}

class _VoiceListsViewState() extends State<VoiceListsView> {
  /// The list that saves; the rows wait.
  String? _busy;

  /// The household's pick now; null until the server named it.
  String? _pick;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final pick = await context.read<SessionCubit>().defaultList(
        widget.household.id,
      );
      if (mounted) {
        setState(() => _pick = pick);
      }
    } on HouseholdError {
      // Offline or refused: no list is checked, a tap still saves.
    }
  }

  Future<void> _choose(String listId) async {
    final session = context.read<SessionCubit>();
    final notices = Notices.of(context);
    final l10n = AppLocalizations.of(context);
    final householdId = widget.household.id;
    final go = widget.go;
    setState(() => _busy = listId);
    try {
      await session.setDefaultList(listId);
      if (session.state case InHousehold(:final defaultHousehold)
          when defaultHousehold.id != householdId) {
        await session.setDefault(householdId);
      }
      go(const HouseholdsPage());
    } on HouseholdError catch (e) {
      notices.showSnackBar(
        SnackBar(content: Text(householdProblemText(l10n, e.problem))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: HlSpace.s3),
      children: [
        HouseholdSheetTitle(l10n.defaultListTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(l10n.voiceDefaultListBody(widget.household.name)),
        ),
        const SizedBox(height: HlSpace.s2),
        IgnorePointer(
          ignoring: _busy != null,
          child: Column(
            children: [
              for (final list in widget.lists)
                _voiceRow(
                  context,
                  key: ValueKey('voice-list-${list.id}'),
                  icon: Icons.checklist,
                  name: listName(list, l10n),
                  current: list.id == _pick,
                  more: false,
                  busy: _busy == list.id,
                  onTap: () => unawaited(_choose(list.id)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A household or list to pick: its [name] wraps, a check on the
/// [current] pick, a chevron when [more] follows, a spinner while [busy].
Widget _voiceRow(
  BuildContext context, {
  required Key key,
  required IconData icon,
  required String name,
  required bool current,
  required bool more,
  required bool busy,
  required VoidCallback onTap,
}) {
  final t = SnacklistColors.of(Theme.of(context).brightness);
  return ListTile(
    key: key,
    minTileHeight: 56,
    leading: sheetHex(context, icon, current ? t.accentSoft : t.surfaceSunken),
    title: Text(name),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (current)
          Icon(
            Icons.check,
            key: const ValueKey('voice-current'),
            color: t.text,
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(2),
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (more)
          Icon(Icons.chevron_right, color: t.textMuted),
      ],
    ),
    selected: current,
    onTap: onTap,
  );
}
