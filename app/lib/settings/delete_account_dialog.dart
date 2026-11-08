import 'dart:async';

import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/purchases/premium_dialogs.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/refund_help.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Asks, deletes the account on the server and signs out on this device.
/// The router then shows the start screen with the confirmation.
/// A yearly plan the user pays keeps being billed after the deletion: they
/// hear so first (H-85).
Future<void> deleteAccount(BuildContext context) async {
  final repository = context.read<AccountRepository>();
  final session = context.read<SessionCubit>();
  if (!await confirmBillingContinues(context, account: true) ||
      !context.mounted) {
    return;
  }
  // The archive texts come with the archive UI's Legal Review or with the
  // Premium sale, whichever is first (DECISIONS 68.3).
  final archiveTexts =
      Environment.householdArchive ||
      await context.read<PremiumServer>().offerSwitch() == OfferSwitch.on;
  if (!context.mounted) {
    return;
  }
  final deleted = await showDialog<AccountDeleted>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        DeleteAccountDialog(repository: repository, archiveTexts: archiveTexts),
  );
  if (deleted != null) {
    await session.accountDeleted(
      AccountDeletedNotice(
        removeAppleManually: deleted.apple == AppleUnlink.manual,
      ),
    );
  }
}

/// Whether [input] is the confirmation word: `LÖSCHEN`, `LOESCHEN` for
/// keyboards without umlauts, or `DELETE` as the English app asks.
bool isDeleteConfirmation(String input) => const {
  'löschen',
  'loeschen',
  'delete',
}.contains(input.trim().toLowerCase());

sealed class const _Step();

final class const _LoadingFate() extends _Step;

final class const _FateFailed(final AccountError error) extends _Step;

final class const _Confirming(
  final AccountFate fate, [

  /// Why the last attempt deleted nothing.
  final AccountError? error,
]) extends _Step;

final class const _Deleting(final AccountFate fate) extends _Step;

/// Pops with the [AccountDeleted] answer once the server deleted the
/// account.
class const DeleteAccountDialog({
  required final AccountRepository repository,
  super.key,

  /// Name the archived households that go with the account, and why the
  /// last member cannot archive instead (job 68). Without them the last
  /// member of a household with premium is still warned (job 104).
  final bool archiveTexts = false,
}) extends StatefulWidget {
  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState() extends State<DeleteAccountDialog> {
  final _confirmation = TextEditingController();
  _Step _step = const _LoadingFate();

  /// The user ticked that Hummlist Premium is not refunded.
  var _premiumAcknowledged = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFate());
  }

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _loadFate() async {
    _Step next;
    try {
      next = _Confirming(await widget.repository.fate());
    } on AccountError catch (e) {
      next = _FateFailed(e);
    }
    if (mounted) {
      setState(() => _step = next);
    }
  }

  Future<void> _delete(AccountFate fate) async {
    setState(() => _step = _Deleting(fate));
    try {
      final deleted = await widget.repository.delete();
      if (mounted) {
        Navigator.of(context).pop(deleted);
      }
    } on AccountError catch (e) {
      if (mounted) {
        setState(() => _step = _Confirming(fate, e));
      }
    }
  }

  /// Archived households are only named with the archive texts, so only
  /// then does their premium ask for the tick.
  bool _endsPremium(AccountFate fate) =>
      widget.archiveTexts ? fate.endsPremium : fate.deletedPremium.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final step = _step;
    final deleting = step is _Deleting;
    final error = switch (step) {
      _FateFailed(error: AccountOffline()) => l10n.accountFateOffline,
      _FateFailed(error: AccountFailed(:final code)) => l10n.accountFateFailed(
        code,
      ),
      _FateFailed(error: AppleReauthCanceled()) => l10n.accountFateFailed(
        'canceled',
      ),
      _Confirming(error: AccountOffline()) => l10n.accountDeleteOffline,
      _Confirming(error: AccountFailed(:final code)) =>
        l10n.accountDeleteFailed(code),
      _Confirming(error: AppleReauthCanceled()) => l10n.accountDeleteCanceled,
      _Confirming(error: null) || _LoadingFate() || _Deleting() => null,
    };
    final fate = switch (step) {
      _Confirming(:final fate) || _Deleting(:final fate) => fate,
      _LoadingFate() || _FateFailed() => null,
    };
    return PopScope(
      canPop: !deleting,
      child: AlertDialog(
        key: const ValueKey('account-delete-dialog'),
        title: Text(l10n.accountDeleteTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.accountDeleteWhat),
              const SizedBox(height: 12),
              if (fate == null && error == null)
                const Center(child: CircularProgressIndicator())
              else if (fate != null) ...[
                if (fate.households.isEmpty)
                  Text(l10n.accountDeleteNone)
                else
                  for (final (i, household) in fate.households.indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Text(_fateText(l10n, household)),
                  ],
                if (widget.archiveTexts && fate.archived.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    key: const ValueKey('account-delete-archived'),
                    _archivedText(l10n, fate.archived),
                  ),
                ],
                if (_endsPremium(fate)) ...[
                  const SizedBox(height: 12),
                  _PremiumWarning(
                    fate: fate,
                    archiveTexts: widget.archiveTexts,
                    acknowledged: _premiumAcknowledged,
                    onChanged: deleting
                        ? null
                        : (ack) => setState(() => _premiumAcknowledged = ack),
                  ),
                ],
                if (fate.households.isNotEmpty || fate.archived.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(l10n.accountDeleteExportHint),
                ],
                const SizedBox(height: 16),
                LabeledField(
                  label: l10n.accountDeleteConfirmLabel,
                  field: TextField(
                    key: const ValueKey('account-delete-confirm-field'),
                    controller: _confirmation,
                    enabled: !deleting,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (deleting) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('account-delete-cancel'),
            onPressed: deleting ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('account-delete-confirm'),
            style: dangerButtonStyle(context),
            onPressed: switch (step) {
              _Confirming(:final fate)
                  when isDeleteConfirmation(_confirmation.text) &&
                      (_premiumAcknowledged || !_endsPremium(fate)) =>
                () => unawaited(_delete(fate)),
              _ => null,
            },
            child: Text(l10n.accountDeleteConfirm),
          ),
        ],
      ),
    );
  }
}

String _fateText(AppLocalizations l10n, HouseholdFate fate) => switch (fate) {
  FateKept(:final householdName, otherMemberNames: []) =>
    l10n.accountDeleteKeptUnnamed(householdName),
  FateKept(:final householdName, :final otherMemberNames) =>
    l10n.accountDeleteKept(householdName, _joinNames(l10n, otherMemberNames)),
  FateDeleted(:final householdName) => l10n.accountDeleteDeleted(householdName),
};

String _archivedText(AppLocalizations l10n, List<ArchivedFate> archived) {
  final names = _joinNames(l10n, [
    for (final a in archived) l10n.quotedName(a.name),
  ]);
  return archived.any((a) => a.unlocked)
      ? l10n.accountDeleteArchivedPremium(archived.length, names)
      : l10n.accountDeleteArchived(archived.length, names);
}

/// What ends with the account and that it is not refunded, with the refund
/// help and the box the user ticks before Delete works.
class const _PremiumWarning({
  required final AccountFate fate,
  required final bool archiveTexts,
  required final bool acknowledged,
  required final ValueChanged<bool>? onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('account-delete-premium'),
      margin: EdgeInsets.zero,
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final FateDeleted(:householdName) in fate.deletedPremium)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  archiveTexts
                      ? l10n.accountDeletePremium(householdName)
                      : l10n.accountDeletePremiumLastMember(householdName),
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            RefundHelpLink(
              key: const ValueKey('account-delete-refund-help'),
              label: l10n.joinLifetimeRefundLink,
            ),
            CheckboxListTile(
              key: const ValueKey('account-delete-premium-ack'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: acknowledged,
              onChanged: onChanged == null
                  ? null
                  : (value) => onChanged!(value ?? false),
              title: Text(
                l10n.accountDeletePremiumAck,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `Lea`, `Lea und Max`, `Anna, Lea und Max`.
String _joinNames(AppLocalizations l10n, List<String> names) =>
    names.length == 1
    ? names.single
    : l10n.namesAnd(names.sublist(0, names.length - 1).join(', '), names.last);
