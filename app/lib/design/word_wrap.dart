import 'dart:math' as math;

import 'package:family_groceries/design/hyphenate.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:material_ui/material_ui.dart';

/// [text] laid out for [width] in [style] at [scaler]: a word too wide
/// for a line („Benachrichtigungen“ at twice the text size) starts a line
/// and is cut at the last syllable that fits with its „-“, then a line
/// break, as often as it needs. Words that fit stay whole and wrap between
/// words. The hyphen is a real character rather than a soft hyphen left to
/// the engine: the web engine breaks at a soft hyphen without drawing it.
String hyphenateToFit(
  String text,
  TextStyle style,
  TextScaler scaler,
  double width,
  TextDirection direction,
) {
  if (!width.isFinite) {
    return text;
  }
  double measure(String part) {
    final painter = TextPainter(
      text: TextSpan(text: part, style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    final measured = painter.width;
    painter.dispose();
    return measured;
  }

  // A pixel to spare for rounding.
  final room = width - 1;
  final tokens = RegExp(r'\s+|\S+').allMatches(text).map((m) => m[0]!);
  final out = StringBuffer();
  var pendingSpace = '';
  for (final token in tokens) {
    if (token.trim().isEmpty) {
      pendingSpace = token;
      continue;
    }
    if (measure(token) <= room) {
      out
        ..write(pendingSpace)
        ..write(token);
      pendingSpace = '';
      continue;
    }
    if (out.isNotEmpty) {
      out.write('\n');
    }
    pendingSpace = '';
    final syllables = hyphenate(token).split(softHyphen);
    var rest = syllables;
    while (rest.length > 1 && measure(rest.join()) > room) {
      var take = 1;
      while (take < rest.length - 1 &&
          measure('${rest.take(take + 1).join()}-') <= room) {
        take++;
      }
      out
        ..write(rest.take(take).join())
        ..write('-\n');
      rest = rest.sublist(take);
    }
    out.write(rest.join());
  }
  return (out..write(pendingSpace)).toString();
}

/// A label at the full text size that wraps onto as many lines as it
/// needs: between words, and a word too long for a line at a syllable with
/// a hyphen (Peter, 26 Nov 2026: More's rows wrap at twice the text size,
/// never shrunk, cut or broken just anywhere). Screen readers get [text]
/// as it is, without the hyphens and breaks.
class const HlWordWrapText(
  final String text, {
  final TextStyle? style,
  final String? semanticsLabel,
  final TextAlign? textAlign,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final shown = hyphenateToFit(
        text,
        DefaultTextStyle.of(context).style.merge(style),
        MediaQuery.textScalerOf(context),
        constraints.maxWidth,
        Directionality.of(context),
      );
      return Text(
        shown,
        style: style,
        textAlign: textAlign,
        semanticsLabel: semanticsLabel ?? (shown == text ? null : text),
        softWrap: true,
        overflow: TextOverflow.visible,
      );
    },
  );
}

/// Material's cap on an app bar title's text scale, which keeps the title
/// from outgrowing the page at large text.
const _titleMaxScale = 1.34;

/// An app bar whose [title] wraps onto as many lines as it needs, as
/// [HlWordWrapText] does, the bar growing with it, instead of Material's one
/// line with an ellipsis. The title is measured for the width the bar gives
/// it with a back button, centred on iOS, and laid out at that width and
/// scale.
AppBar hlWrappingAppBar(BuildContext context, String title) {
  final theme = Theme.of(context);
  final style = theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge!;
  final direction = Directionality.of(context);
  final padding = MediaQuery.paddingOf(context);
  // The bar's toolbar sits inside the side insets of a notched landscape.
  final screen =
      MediaQuery.sizeOf(context).width - padding.left - padding.right;
  final centered =
      theme.appBarTheme.centerTitle ??
      switch (theme.platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => true,
        _ => false,
      };
  const spacing = NavigationToolbar.kMiddleSpacing;
  final width = math.max<double>(
    0,
    centered
        ? screen - 2 * (kToolbarHeight + spacing)
        : screen - kToolbarHeight - 2 * spacing,
  );
  final scaler = MediaQuery.textScalerOf(context)
      .clamp(maxScaleFactor: _titleMaxScale);
  final shown = hyphenateToFit(title, style, scaler, width, direction);
  final painter = TextPainter(
    text: TextSpan(text: shown, style: style),
    textDirection: direction,
    textScaler: scaler,
  )..layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return AppBar(
    toolbarHeight: math.max(kToolbarHeight, height + 2 * HlSpace.s2),
    title: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Text(
        shown,
        semanticsLabel: shown == title ? null : title,
        softWrap: true,
        overflow: TextOverflow.visible,
        textScaler: scaler,
      ),
    ),
  );
}
