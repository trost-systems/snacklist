import 'dart:async';

import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_view/hold.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/list_view/leaving_rows.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// "6×" for a count, any other quantity as typed; null for one.
String? quantityLabel(String? quantity) => switch (quantity?.trim()) {
  null || '' || '1' => null,
  final q when RegExp(r'^\d+$').hasMatch(q) => '$q×',
  final q => q,
};

/// One item: a tap ticks it; a hold or a right click opens the edit sheet,
/// which also deletes the item and moves it to another category or store.
/// Nothing on the row drags or swipes (the order lives in the store's
/// details, Anpassen, job 78): a sideways drag does nothing.
/// Screen readers get edit and delete as actions.
class const ItemRow({
  required final Item item,
  required final Category? category,
  required final LeavingRows leaving,

  /// Not seen yet: tinted, and it reports whether it is on screen.
  required final bool fresh,

  /// The last row of its block has no rule under it.
  required final bool last,
  required final ValueChanged<bool> onVisible,
  required final ValueChanged<Item> onTick,
  required final ValueChanged<Item> onEdit,

  /// Only a screen reader's action deletes from the row; everyone else
  /// deletes in the edit sheet.
  required final ValueChanged<Item> onDelete,
  super.key,
}) extends StatefulWidget {
  @override
  State<ItemRow> createState() => _ItemRowState();
}

class _ItemRowState()
    extends State<ItemRow>
    with SingleTickerProviderStateMixin {
  /// The way out after a tap, from 0 (open) to 1 (gone): see
  /// [rowLeaveDuration].
  /// Null until the row is ticked.
  AnimationController? _leave;
  Timer? _still;

  @override
  void dispose() {
    if (_leave != null) {
      // Not while the tree is being torn down: the dividers listen.
      final leaving = widget.leaving;
      final id = widget.item.id;
      scheduleMicrotask(() => leaving.left(id));
    }
    _leave?.dispose();
    _still?.cancel();
    super.dispose();
  }

  /// The line draws, the row closes, then the tick commits. With reduced
  /// motion the struck row shows at once and holds for as long before the
  /// tick, so the result is still seen.
  void _tick() {
    if (_leave != null) {
      return;
    }
    final item = widget.item;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        AppLocalizations.of(context).itemTicked(item.name),
        Directionality.of(context),
      ),
    );
    final leave = AnimationController(vsync: this, duration: rowLeaveDuration);
    setState(() => _leave = leave);
    void commit() {
      if (mounted) {
        widget.onTick(item);
      }
    }

    if (MediaQuery.disableAnimationsOf(context)) {
      leave.value = _struck;
      _still = Timer(HlDuration.medium, commit);
    } else {
      widget.leaving.leave(item.id);
      unawaited(leave.forward().whenComplete(commit));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tile = _semantics(
      context,
      _Tile(row: widget, leave: _leave, onTap: _tick),
    );
    final watched = widget.fresh
        ? VisibilityDetector(
            key: ValueKey('new-${item.id}'),
            onVisibilityChanged: (info) =>
                widget.onVisible(info.visibleFraction > 0.5),
            child: tile,
          )
        : tile;
    return Hold(
      tappable: true,
      onHold: () => widget.onEdit(item),
      child: watched,
    );
  }

  Widget _semantics(BuildContext context, Widget child) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final details = [?item.brand, ?item.properties].join(' · ');
    // The name leads, so the row is found by it; then the details and the
    // quantity, in the order rows have been read since job 15.
    final label = [
      item.name,
      if (details.isNotEmpty) details,
      ?item.quantity,
      if (widget.fresh) l10n.newItem,
    ].join('\n');
    return Semantics(
      container: true,
      button: true,
      checked: _leave != null,
      label: label,
      onTap: _tick,
      onLongPress: () => widget.onEdit(item),
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.editSheet): () => widget.onEdit(item),
        CustomSemanticsAction(label: l10n.delete): () => widget.onDelete(item),
      },
      excludeSemantics: true,
      child: child,
    );
  }
}

// The way out of a ticked row runs on one controller: the line draws
// across the name and the row tints ([HlDuration.short]), then the row
// fades and closes its gap as one eased motion ([HlDuration.medium]), so the
// rows below move up instead of jumping when the item goes. A category
// divider whose rows all leave closes on the same curves.
final rowLeaveDuration = HlDuration.short + HlDuration.medium;

/// Where the line is drawn and the close begins.
final _struck =
    HlDuration.short.inMicroseconds / rowLeaveDuration.inMicroseconds;
final _draw = Interval(0, _struck, curve: HlEasing.standard);
final rowLeaveFade = Interval(_struck, 1, curve: HlEasing.exit);
final rowLeaveClose = Interval(_struck, 1, curve: HlEasing.standard);

// The site's `.item`: Bricolage 17/1.25 names, a 28 px emoji column, a
// 10 px gap, 13 px details in medium.
const _nameSize = 17.0;
const _nameLine = 21.25;
const _iconSize = 18.0;
const _iconColumn = 28.0;
const _iconGap = 10.0;
const _detailSize = 13.0;
const _rowPadding = 6.0;

/// The rule between two rows.
const _hairline = 1.0;

class const _Tile({
  required final ItemRow row,
  required final AnimationController? leave,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final leave = this.leave;
    if (leave == null) {
      return _content(context, 0);
    }
    return AnimatedBuilder(
      animation: leave,
      builder: (context, _) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1 - rowLeaveClose.transform(leave.value),
          child: _content(context, leave.value),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, double t) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = row.item;
    final quantity = quantityLabel(item.quantity);
    final details = [?item.brand, ?item.properties].join(' · ');
    final hl = HummlistColors.of(theme.brightness);
    final drawn = _draw.transform(t);
    // Yellow means new, mint means done, like the homepage hero (Peter).
    final base = row.fresh ? hl.honeySoft : scheme.surface;
    // A ticked name turns muted as its line draws, like the site's done row.
    final ink = Color.lerp(scheme.onSurface, hl.textMuted, drawn)!;
    final name = TextSpan(
      children: [
        if (quantity != null)
          TextSpan(
            text: '$quantity ',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color.lerp(scheme.primary, hl.textMuted, drawn),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        TextSpan(text: item.name),
      ],
      style: DefaultTextStyle.of(context).style.merge(
        TextStyle(
          fontFamily: HlFont.display,
          fontSize: _nameSize,
          height: _nameLine / _nameSize,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    );
    final scaler = MediaQuery.textScalerOf(context);
    return Material(
      color: Color.lerp(base, hl.mintSoft, drawn),
      child: InkWell(
        onTap: onTap,
        onSecondaryTap: () => row.onEdit(item),
        splashFactory: NoSplash.splashFactory,
        highlightColor: scheme.surfaceContainer,
        child: Opacity(
          opacity: 1 - rowLeaveFade.transform(t),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Container(
                // 48, not the site's 44: the whole row is the tap target.
                constraints: const BoxConstraints(minHeight: HlSpace.s7),
                alignment: AlignmentDirectional.centerStart,
                // The hairline below keeps its pixel of the row's height.
                padding: EdgeInsets.fromLTRB(
                  HlSpace.s4,
                  _rowPadding,
                  HlSpace.s4,
                  _rowPadding + (row.last ? 0 : _hairline),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: _iconGap,
                  children: [
                    SizedBox(
                      width: _iconColumn,
                      child: ItemIcon(
                        item.name,
                        size: _iconSize,
                        height: _nameLine,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 1,
                        children: [
                          CustomPaint(
                            foregroundPainter: drawn == 0
                                ? null
                                : StrikePainter(
                                    text: name,
                                    textScaler: scaler,
                                    textDirection: Directionality.of(context),
                                    progress: drawn,
                                    color: hl.textMuted,
                                  ),
                            child: Text.rich(name, textScaler: scaler),
                          ),
                          if (details.isNotEmpty)
                            Text(
                              details,
                              style: TextStyle(
                                fontSize: _detailSize,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                                color: Color.lerp(
                                  scheme.onSurfaceVariant,
                                  hl.textMuted,
                                  drawn,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Between rows of a section, a hairline from the name's start
              // to the content's end, like the category dividers' rules.
              if (!row.last)
                PositionedDirectional(
                  start: HlSpace.s4 + _iconColumn + _iconGap,
                  end: HlSpace.s4,
                  bottom: 0,
                  height: _hairline,
                  child: ColoredBox(color: scheme.outlineVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The strike-through of a ticked name: one line per line of text, as wide
/// as the words on it, drawn left to right and line after line as
/// [progress] runs from 0 to 1. It lays [text] out as the [RichText] it
/// covers does, at the width it was given.
class const StrikePainter({
  required final TextSpan text,
  required final TextScaler textScaler,
  required final TextDirection textDirection,
  required final double progress,
  required final Color color,
}) extends CustomPainter {
  static const thickness = HlBorder.width;

  /// Past the first and last letter, so the line reads as crossing out.
  static const overhang = 2.0;

  /// The full lines at [size], before [progress] cuts them.
  List<Rect> lines(Size size) {
    final painter = TextPainter(
      text: text,
      textScaler: textScaler,
      textDirection: textDirection,
    )..layout(maxWidth: size.width);
    // Through the middle of the lowercase letters.
    final lift = textScaler.scale(text.style?.fontSize ?? 14) * 0.28;
    final lines = [
      for (final line in painter.computeLineMetrics())
        if (line.width > 0)
          Rect.fromCenter(
            center: Offset(line.left + line.width / 2, line.baseline - lift),
            width: line.width + 2 * overhang,
            height: thickness,
          ),
    ];
    painter.dispose();
    return lines;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final lines = this.lines(size);
    var left = progress * lines.fold(0.0, (sum, line) => sum + line.width);
    final paint = Paint()..color = color;
    for (final line in lines) {
      if (left <= 0) {
        break;
      }
      final width = left < line.width ? left : line.width;
      left -= width;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(line.left, line.top, width, line.height),
          const Radius.circular(thickness),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(StrikePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.text != text ||
      old.textScaler != textScaler ||
      old.textDirection != textDirection;
}
