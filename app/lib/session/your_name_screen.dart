import 'dart:async';

import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/onboarding_frame.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/your_name.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// What the user reads when saving the name failed for [error], other than
/// an invalid name, which the field shows.
String nameErrorText(AppLocalizations l10n, NameError error) => switch (error) {
  NameOffline() => l10n.yourNameOffline,
  NameInvalid() => l10n.yourNameInvalid,
  NameFailed(:final code) => l10n.genericError(code),
};

/// Refuses an edit that makes the name longer than [maxDisplayName] code
/// points, as `set_display_name` counts: a family emoji is one letter on
/// the counter but five code points.
class const DisplayNameLimit() extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.text.runes.length > maxDisplayName ? oldValue : newValue;
}

/// The name field of the name step and Konto's sheet: labelled, with the
/// hint while empty and n/80 under it.
class const YourNameField({
  required final TextEditingController controller,
  required final bool enabled,
  required final ValueChanged<String> onChanged,
  required final VoidCallback onSubmitted,
  final String? error,
  final bool autofocus = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = this.error;
    return LabeledField(
      label: l10n.yourNameLabel,
      field: Semantics(
        hint: error ?? '',
        child: TextField(
          autofillHints: null,
          key: const ValueKey('your-name-field'),
          controller: controller,
          autofocus: autofocus,
          enabled: enabled,
          maxLength: maxDisplayName,
          // maxLength counts grapheme clusters; the server counts code points.
          inputFormatters: const [DisplayNameLimit()],
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: l10n.yourNameHint,
            error: error == null ? null : FieldError(error),
          ),
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitted(),
        ),
      ),
    );
  }
}

/// „Wie sollen wir dich nennen?“ (job 297, DN3), the gate after the
/// sign-in while [asksName]. A Google or Apple name is prefilled and one
/// tap confirms it; without one the field is empty and required. Members
/// of a household may postpone it. Once saved the router moves on.
class const YourNameScreen({super.key}) extends StatefulWidget {
  @override
  State<YourNameScreen> createState() => _YourNameScreenState();
}

class _YourNameScreenState() extends State<YourNameScreen> {
  final _name = TextEditingController();

  /// What the field was filled with from the server; the user's own text
  /// once it differs.
  var _prefill = '';
  var _busy = false;
  var _invalid = false;
  NameError? _problem;

  @override
  void initState() {
    super.initState();
    _fill(context.read<YourNameCubit>().state);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Takes the name read into the field, unless the user typed: Apple's
  /// name may arrive after the first read.
  void _fill(YourName name) {
    if (name case NameRead(:final name, :final fromEmail)) {
      final prefill = fromEmail ? '' : name;
      if (_name.text == _prefill) {
        _name.text = prefill;
      }
      _prefill = prefill;
    }
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    if (!validDisplayName(_name.text)) {
      setState(() => _invalid = true);
      return;
    }
    setState(() {
      _busy = true;
      _invalid = false;
      _problem = null;
    });
    try {
      await context.read<YourNameCubit>().save(_name.text);
    } on NameError catch (e) {
      if (mounted) {
        setState(() {
          _invalid = e is NameInvalid;
          _problem = e is NameInvalid ? null : e;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = context.watch<YourNameCubit>().state;
    final member = context.select<SessionCubit, bool>(
      (s) => s.state is InHousehold,
    );
    return BlocListener<YourNameCubit, YourName>(
      listener: (_, name) => setState(() => _fill(name)),
      child: OnboardingPage(
        title: l10n.yourNameLabel,
        listKey: const ValueKey('your-name-screen'),
        // A gate: without a household nothing else is reachable, so a wrong
        // account must not have to save a name to get out.
        actions: [
          IconButton(
            key: const ValueKey('your-name-sign-out'),
            tooltip: l10n.signOut,
            icon: const Icon(Icons.logout),
            onPressed: () => unawaited(context.read<SessionCubit>().signOut()),
          ),
        ],
        children: [
          OnboardingHeading(l10n.yourNameTitle),
          const SizedBox(height: 12),
          Text(l10n.yourNameBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          ...switch (name) {
            NameUnread(failed: true) => [
              ProblemText(
                l10n.yourNameLoadFailed,
                key: const ValueKey('your-name-load-failed'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                key: const ValueKey('your-name-retry'),
                onPressed: () =>
                    unawaited(context.read<YourNameCubit>().retry()),
                child: Text(l10n.retry),
              ),
            ],
            NameUnread() => [const Center(child: CircularProgressIndicator())],
            NameRead() => _form(l10n, member: member),
          },
        ],
      ),
    );
  }

  List<Widget> _form(AppLocalizations l10n, {required bool member}) {
    final problem = _problem;
    final confirms =
        _prefill.isNotEmpty &&
        normalizeDisplayName(_name.text) == normalizeDisplayName(_prefill);
    return [
      YourNameField(
        controller: _name,
        enabled: !_busy,
        error: _invalid ? l10n.yourNameInvalid : null,
        onChanged: (_) => setState(() => _invalid = false),
        onSubmitted: () => unawaited(_save()),
      ),
      if (problem != null)
        ProblemText(
          nameErrorText(l10n, problem),
          key: const ValueKey('your-name-problem'),
        ),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('your-name-save'),
        onPressed: _busy || !validDisplayName(_name.text)
            ? null
            : () => unawaited(_save()),
        child: _busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(confirms ? l10n.yourNameConfirm : l10n.onboardingNext),
      ),
      if (member) ...[
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('your-name-not-now'),
          onPressed: _busy
              ? null
              : () => unawaited(context.read<YourNameCubit>().postpone()),
          child: Text(l10n.yourNameNotNow),
        ),
      ],
    ];
  }
}
