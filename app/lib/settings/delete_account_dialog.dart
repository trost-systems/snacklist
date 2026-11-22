import 'dart:async';

import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/purchases/premium_dialogs.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/refund_help.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

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
  final AccountFate fate,
  final MyPremium premium, [

  /// Why the last attempt deleted nothing.
  final AccountError? error,
]) extends _Step;

final class const _Deleting(final AccountFate fate, final MyPremium premium)
    extends _Step;

/// Pops with the [AccountDeleted] answer once the server deleted the
/// account.
class const DeleteAccountDialog({
  required final AccountRepository repository,
  super.key,

  /// Name the archived households that go with the account (job 68).
  final bool archiveTexts = false,
}) extends StatefulWidget {
  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState() extends State<DeleteAccountDialog> {
  final _confirmation = TextEditingController();
  _Step _step = const _LoadingFate();

  /// The user ticked that Snacklist Premium is not refunded.
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
    final server = context.read<PremiumServer>();
    _Step next;
    try {
      final fate = await widget.repository.fate();
      next = _Confirming(fate, await server.myPremium());
    } on Object catch (e) {
      next = _FateFailed(accountErrorOf(e));
    }
    if (mounted) {
      setState(() => _step = next);
    }
  }

  Future<void> _delete(AccountFate fate, MyPremium premium) async {
    setState(() => _step = _Deleting(fate, premium));
    try {
      final deleted = await widget.repository.delete();
      if (mounted) {
        Navigator.of(context).pop(deleted);
      }
    } on AccountError catch (e) {
      if (mounted) {
        setState(() => _step = _Confirming(fate, premium, e));
      }
    }
  }

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
    final (fate, premium) = switch (step) {
      _Confirming(:final fate, :final premium) ||
      _Deleting(:final fate, :final premium) => (fate, premium),
      _LoadingFate() || _FateFailed() => (null, MyPremium.none),
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
                if (premium != MyPremium.none) ...[
                  const SizedBox(height: 12),
                  _PremiumWarning(
                    billed: premium == MyPremium.billed,
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
                    autofillHints: null,
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
              _Confirming(:final fate, :final premium)
                  when isDeleteConfirmation(_confirmation.text) &&
                      (_premiumAcknowledged || premium == MyPremium.none) =>
                () => unawaited(_delete(fate, premium)),
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
  return l10n.accountDeleteArchived(archived.length, names);
}

/// The account's own Snacklist Premium ends with it and is not refunded;
/// a yearly plan that renews is still billed (Legal N-362). With the
/// store's subscription management for it, the refund help and the box the
/// user ticks before Delete works.
class const _PremiumWarning({
  /// A yearly plan of the account renews.
  required final bool billed,
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
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                l10n.accountDeletePremium,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (billed)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('account-delete-manage'),
                  onPressed: () => unawaited(openManageSubscriptions(context)),
                  child: Text(l10n.premiumManageSubscription),
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
