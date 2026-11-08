import 'dart:async';

import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The households the user archived as their last member (job 43), with a
/// way back into each. A sheet over More, so it needs no route of its own.
Future<void> showArchivedHouseholds(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (_) => const ArchivedHouseholds(),
    );

class const ArchivedHouseholds({super.key}) extends StatefulWidget {
  @override
  State<ArchivedHouseholds> createState() => _ArchivedHouseholdsState();
}

class _ArchivedHouseholdsState() extends State<ArchivedHouseholds> {
  List<ArchivedHousehold>? _households;
  HouseholdProblem? _problem;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final households = await context.read<InviteRepository>().archived();
      if (mounted) {
        setState(() {
          _households = households;
          _problem = null;
        });
      }
    } on HouseholdError catch (e) {
      if (mounted) {
        setState(() => _problem = e.problem);
      }
    }
  }

  /// Brings [household] back beside the user's other households; nothing
  /// is left (job 169b).
  Future<void> _restore(ArchivedHousehold household) async {
    final l10n = AppLocalizations.of(context);
    final session = context.read<SessionCubit>();
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('archived-restore-dialog'),
        title: Text(l10n.archivedRestoreTitle(household.name)),
        content: Text(l10n.archivedRestoreBody(household.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('archived-restore-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.archivedRestore),
          ),
        ],
      ),
    );
    if (!(go ?? false) || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await session.unarchive(household.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on HouseholdError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = e.problem;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final households = _households;
    final problem = _problem;
    return SafeArea(
      child: ListView(
        key: const ValueKey('archived-households'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Semantics(
            header: true,
            child: Text(l10n.archivedTitle, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 16),
          if (problem != null)
            ProblemText(householdProblemText(l10n, problem))
          else if (households == null || _busy)
            const Center(child: CircularProgressIndicator())
          else if (households.isEmpty)
            Text(l10n.archivedEmpty, key: const ValueKey('archived-empty'))
          else
            for (final household in households)
              ListTile(
                key: ValueKey('archived-${household.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(household.name),
                subtitle: _subtitle(l10n, household),
                trailing: TextButton(
                  key: const ValueKey('archived-restore'),
                  onPressed: () => unawaited(_restore(household)),
                  child: Text(l10n.archivedRestore),
                ),
              ),
        ],
      ),
    );
  }

  /// With Hummlist Lifetime, and when it is deleted unless brought back.
  static Widget? _subtitle(AppLocalizations l10n, ArchivedHousehold household) {
    final deletesAt = household.deletesAt;
    final lines = [
      if (household.unlocked) l10n.archivedUnlocked,
      if (deletesAt != null) l10n.archivedDeletesOn(deletesAt.toLocal()),
    ];
    return lines.isEmpty
        ? null
        : Text(
            lines.join('\n'),
            key: ValueKey('archived-deletes-${household.id}'),
          );
  }
}
