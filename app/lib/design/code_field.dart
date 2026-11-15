import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A code field drawn as [length] boxes, a dash after the first half, the
/// box of the next character marked while it has focus. One real text
/// field lies over the boxes, so typing, the platform's paste,
/// IMEs, screen readers and web automation work as in any field; its own
/// text is invisible. The glyphs shrink to fit, never overflow.
class const CodeField({
  required final TextEditingController controller,
  required final ValueChanged<String> onChanged,

  /// Keep the text to [length] characters a code can have.
  required final List<TextInputFormatter> inputFormatters,
  final int length = 8,
  final bool autofocus = false,
  super.key,
}) extends StatefulWidget {
  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState() extends State<CodeField> {
  final _focus = FocusNode();

  static const _gap = 6.0;
  static const _dash = 16.0;
  static const _height = 56.0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refocus);
  }

  void _refocus() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_refocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) =>
                    _boxes(widget.controller.text, theme, t),
              ),
            ),
          ),
          Positioned.fill(
            child: TextField(
              key: const ValueKey('join-code-field'),
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              autofillHints: null,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: widget.inputFormatters,
              showCursor: false,
              style: const TextStyle(color: Colors.transparent, fontSize: 16),
              // The boxes are its look: none of the theme's borders.
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boxes(String code, ThemeData theme, SnacklistColors t) {
    final length = widget.length;
    final caret = _focus.hasFocus ? code.length.clamp(0, length - 1) : null;
    Widget box(int i) => Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          borderRadius: BorderRadius.circular(HlRadius.s - 2),
          border: Border.all(
            color: i == caret ? theme.colorScheme.primary : t.border,
            width: HlBorder.width,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(HlSpace.s1),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                i < code.length ? code[i] : '',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: t.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        for (var i = 0; i < length; i++) ...[
          if (i == length ~/ 2)
            SizedBox(
              width: _dash,
              child: Center(
                child: Container(width: 8, height: 2, color: t.textMuted),
              ),
            )
          else if (i > 0)
            const SizedBox(width: _gap),
          box(i),
        ],
      ],
    );
  }
}
