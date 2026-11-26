import 'dart:async';

import 'package:family_groceries/core/pop_if_current.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for a name and hands it to [save], trimmed. The dialog stays open
/// while [save] runs and when it answers false (a name taken, offline), so
/// the name can be fixed. [validate] answers why a name cannot be saved
/// (taken), shown under the field, or null. An empty name closes it without
/// saving. [below] shows under the field as the name is typed (job 313's
/// chain suggestions); its `submit` saves a name the way the confirm button
/// does, with its own `save`.
Future<void> showNameDialog(
  BuildContext context, {
  required String title,
  required String confirm,
  required String label,
  required Future<bool> Function(String name) save,
  String? Function(String name)? validate,
  String initial = '',
  int maxLength = 60,
  NameDialogBelow? below,
}) => showDialog<void>(
  context: context,
  builder: (_) => _NameDialog(
    title: title,
    confirm: confirm,
    label: label,
    save: save,
    validate: validate,
    initial: initial,
    maxLength: maxLength,
    below: below,
  ),
);

/// Content under the name dialog's field for the [text] typed so far.
typedef NameDialogBelow = Widget Function(
  String text,
  void Function(String name, Future<bool> Function(String name) save) submit,
);

class const _NameDialog({
  required final String title,
  required final String confirm,
  required final String label,
  required final Future<bool> Function(String name) save,
  required final String? Function(String name)? validate,
  required final String initial,
  required final int maxLength,
  required final NameDialogBelow? below,
}) extends StatefulWidget {
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState() extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  final _field = GlobalKey(debugLabel: 'name-dialog-field');
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit(
    String typed,
    Future<bool> Function(String name) save,
  ) async {
    if (_busy) {
      return;
    }
    final name = typed.trim();
    if (name.isEmpty) {
      popIfCurrent(context);
      return;
    }
    if (widget.validate?.call(name) case final error?) {
      setState(() => _error = error);
      return;
    }
    setState(() => _busy = true);
    final saved = await save(name);
    if (!mounted) {
      return;
    }
    if (saved) {
      popIfCurrent(context);
    } else {
      setState(() => _busy = false);
    }
  }

  Widget _withBelow(Widget field) => switch (widget.below) {
    null => field,
    final below => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: HlSpace.s2,
      children: [
        field,
        ListenableBuilder(
          listenable: _name,
          builder: (_, _) =>
              below(_name.text, (name, save) => unawaited(_submit(name, save))),
        ),
      ],
    ),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The keyboard shrinks the dialog after the field asked to be shown, so
    // the field's lower edge and counter could end up under the buttons:
    // keep the whole field in view whenever the scroll view resizes.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        if (_field.currentContext case final field?) {
          Scrollable.ensureVisible(
            field,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
        return false;
      },
      child: AlertDialog(
        scrollable: true,
        title: Text(widget.title),
        content: _withBelow(
          LabeledField(
            key: _field,
            label: widget.label,
            field: Semantics(
              hint: _error ?? '',
              child: TextField(
                autofillHints: null,
                key: const ValueKey('name-dialog-field'),
                controller: _name,
                autofocus: true,
                readOnly: _busy,
                maxLength: widget.maxLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  error: switch (_error) {
                    final e? => FieldError(e),
                    null => null,
                  },
                ),
                onChanged: (_) {
                  if (_error != null) {
                    setState(() => _error = null);
                  }
                },
                onSubmitted: (_) => unawaited(_submit(_name.text, widget.save)),
              ),
            ),
          ),
        ),
        // Large text still leaves room for the field on a small phone with
        // the keyboard open: two 2x buttons stacked took all of it.
        actions: [
          for (final action in [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey('name-dialog-confirm'),
              onPressed: _busy
                  ? null
                  : () => unawaited(_submit(_name.text, widget.save)),
              child: Text(widget.confirm),
            ),
          ])
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.5,
              child: action,
            ),
        ],
      ),
    );
  }
}
