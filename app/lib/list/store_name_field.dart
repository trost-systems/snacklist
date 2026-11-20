import 'dart:async';

import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A store name typed in place: a hex field with a check and a close
/// button. Enter or the check confirms, Escape, back or the close button
/// cancels. While [onConfirm] runs the field holds still; it stays open
/// when that answers false (a name taken, offline), so the name can be
/// fixed.
class const StoreNameField({
  required final Future<bool> Function(String name) onConfirm,
  required final VoidCallback onCancel,

  /// The check button's label for screen readers.
  required final String confirmLabel,
  final String initial = '',
  final String fieldKey = 'store-new-field',
  final String confirmKey = 'store-new-confirm',
  final String cancelKey = 'store-new-cancel',

  /// The text as it is typed (the add sheet's chain suggestions, job 313).
  final ValueChanged<String>? onChanged,
  super.key,
}) extends StatefulWidget {
  @override
  State<StoreNameField> createState() => _StoreNameFieldState();
}

class _StoreNameFieldState() extends State<StoreNameField> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection.collapsed(offset: widget.initial.length);
  final _focus = FocusNode();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    // Not autofocus: that yields to a field that has focus already, like
    // the add field or the store search.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _empty => _controller.text.trim().isEmpty;

  Future<void> _confirm() async {
    if (_busy || _empty) {
      return;
    }
    setState(() => _busy = true);
    final done = await widget.onConfirm(_controller.text);
    if (mounted && !done) {
      setState(() => _busy = false);
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          widget.onCancel();
        }
      },
      child: Row(
        spacing: HlSpace.s1,
        children: [
          Expanded(
            child: Focus(
              // Hardware Enter and Escape are handled here: Flutter web's
              // text-input action path blurs the field on Enter, and Escape
              // would close the sheet around it. Soft keyboards still submit
              // below.
              onKeyEvent: (_, event) {
                if (event is KeyUpEvent) {
                  return KeyEventResult.ignored;
                }
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.escape) {
                  widget.onCancel();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.numpadEnter) {
                  if (event is KeyDownEvent) {
                    unawaited(_confirm());
                  }
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: HintNamed(
                controller: _controller,
                hint: l10n.storeNameHint,
                field: TextField(
                  autofillHints: null,
                  key: ValueKey(widget.fieldKey),
                  controller: _controller,
                  focusNode: _focus,
                  readOnly: _busy,
                  maxLength: maxStoreNameLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  style: TextStyle(fontSize: 16, color: scheme.onSurface),
                  onChanged: (text) {
                    setState(() {});
                    widget.onChanged?.call(text);
                  },
                  onEditingComplete: () {},
                  onSubmitted: (_) => unawaited(_confirm()),
                  decoration: InputDecoration(
                    hintText: l10n.storeNameHint,
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                    counterText: '',
                    constraints: const BoxConstraints.tightFor(
                      height: HlSize.target,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The theme's main tactile button: on its edge like the chips
          // beside it (job 148).
          IconButton.filled(
            key: ValueKey(widget.confirmKey),
            style: Theme.of(context).filledButtonTheme.style?.copyWith(
              visualDensity: VisualDensity.standard,
              minimumSize: const WidgetStatePropertyAll(Size(56, 48)),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            tooltip: widget.confirmLabel,
            onPressed: _busy || _empty ? null : () => unawaited(_confirm()),
            icon: const Icon(Icons.check),
          ),
          IconButton(
            key: ValueKey(widget.cancelKey),
            tooltip: l10n.cancel,
            onPressed: widget.onCancel,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
