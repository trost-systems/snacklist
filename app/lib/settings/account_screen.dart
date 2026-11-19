import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/your_name.dart';
import 'package:family_groceries/session/your_name_screen.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:family_groceries/settings/delete_account_dialog.dart';
import 'package:family_groceries/settings/export_saver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Who is signed in (with the flag `display-name` their name first, to
/// change it, job 297 DE1), exporting the account's data and deleting the
/// account (`/more/account`). A page of the More tab, which gives it its
/// frame.
class const AccountScreen({
  super.key,

  /// Overrides the platform's download or share sheet, for tests.
  final ExportSaver saveExport = platformSaveExport,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final email = context.read<AccountRepository>().email;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          key: const ValueKey('account-screen'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const _NameRow(),
            if (email != null)
              ListTile(
                key: const ValueKey('account-email'),
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(email),
                trailing: IconButton(
                  key: const ValueKey('account-email-copy'),
                  tooltip: l10n.copyEmail,
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    unawaited(Clipboard.setData(ClipboardData(text: email)));
                    Notices.of(context)
                        .showSnackBar(SnackBar(content: Text(l10n.copied)));
                  },
                ),
              ),
            Builder(
              builder: (tile) => ListTile(
                key: const ValueKey('account-export'),
                leading: const Icon(Icons.download),
                title: Text(l10n.accountExport),
                subtitle: Text(l10n.accountExportBody),
                onTap: () => unawaited(_export(tile, saveExport)),
              ),
            ),
            ListTile(
              key: const ValueKey('account-delete'),
              leading: const Icon(Icons.delete_forever),
              iconColor: Theme.of(context).colorScheme.error,
              textColor: Theme.of(context).colorScheme.error,
              title: Text(l10n.accountDelete),
              onTap: () => unawaited(deleteAccount(context)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _export(BuildContext tile, ExportSaver save) async {
  final l10n = AppLocalizations.of(tile);
  final messenger = Notices.of(tile);
  final box = tile.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  final message = await () async {
    try {
      final json = await tile.read<AccountRepository>().export();
      final path = await save(
        exportFileName(DateTime.now()),
        json,
        origin: origin,
      );
      return path == null ? l10n.exportDone : l10n.exportDoneAt(path);
    } on AccountError catch (e) {
      return switch (e) {
        AccountOffline() => l10n.exportOffline,
        AccountFailed(:final code) => l10n.exportFailed(code),
        AppleReauthCanceled() => l10n.exportFailed('canceled'),
      };
    }
  }();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// The user's name, with the flag on and once read; a tap opens the sheet
/// to change it, one name for all households.
class const _NameRow() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final on = context.select<Flags?, bool>(
      (f) => f?.isOn(displayNameFlag) ?? false,
    );
    final name = context.watch<YourNameCubit?>()?.state;
    final l10n = AppLocalizations.of(context);
    if (on && name is NameUnread && name.failed) {
      return ListTile(
        key: const ValueKey('account-name-failed'),
        leading: const Icon(Icons.badge_outlined),
        title: Text(l10n.yourNameLabel),
        subtitle: Text(l10n.yourNameLoadFailed),
        trailing: const Icon(Icons.refresh),
        onTap: () => unawaited(context.read<YourNameCubit>().retry()),
      );
    }
    if (!on || name is! NameRead) {
      return const SizedBox.shrink();
    }
    return ListTile(
      key: const ValueKey('account-name'),
      leading: const Icon(Icons.badge_outlined),
      title: Text(l10n.yourNameLabel),
      subtitle: Text(name.fromEmail ? l10n.yourNameAdd : name.name),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => unawaited(_editName(context, name)),
    );
  }
}

Future<void> _editName(BuildContext context, NameRead name) async {
  final notices = Notices.of(context);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    // Above the tab bar, like a dialog.
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BlocProvider.value(
      value: context.read<YourNameCubit>(),
      child: _NameSheet(initial: name.fromEmail ? '' : name.name),
    ),
  );
  if ((saved ?? false) && context.mounted) {
    notices.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).yourNameSaved)),
    );
  }
}

/// The name, prefilled ([initial], empty for one from the e-mail address);
/// Save while it is valid and changed. Pops true once saved.
class const _NameSheet({required final String initial}) extends StatefulWidget {
  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState() extends State<_NameSheet> {
  late final _name = TextEditingController(text: widget.initial);
  var _busy = false;
  var _invalid = false;
  NameError? _problem;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _savable =>
      validDisplayName(_name.text) &&
      normalizeDisplayName(_name.text) != normalizeDisplayName(widget.initial);

  Future<void> _save() async {
    if (_busy || !_savable) {
      return;
    }
    setState(() {
      _busy = true;
      _invalid = false;
      _problem = null;
    });
    try {
      await context.read<YourNameCubit>().save(_name.text);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on NameError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _invalid = e is NameInvalid;
          _problem = e is NameInvalid ? null : e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final problem = _problem;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const ValueKey('your-name-sheet'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.yourNameLabel,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.yourNameEditBody, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            YourNameField(
              controller: _name,
              enabled: !_busy,
              autofocus: true,
              error: _invalid ? l10n.yourNameInvalid : null,
              onChanged: (_) => setState(() => _invalid = false),
              onSubmitted: () => unawaited(_save()),
            ),
            if (problem != null)
              ProblemText(
                nameErrorText(l10n, problem),
                key: const ValueKey('your-name-sheet-problem'),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('your-name-sheet-save'),
              onPressed: _busy || !_savable ? null : () => unawaited(_save()),
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.save),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('your-name-sheet-cancel'),
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }
}
