import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/guides/guide_link.dart';
import 'package:flutter/gestures.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

/// A guide's Markdown (GitHub flavoured, as the site's twin writes it) as
/// the app's own text: headings, paragraphs, lists, quotes, code and
/// tables in the design tokens. A table is a stack of its rows, each cell
/// under its column's header, since the guides' tables have long cells a
/// phone cannot fit side by side. Anything else shows as its text.
///
/// A link to a section of this page scrolls to the heading the link names;
/// every other link goes to [onLink].
class const GuideMarkdown({
  required final String markdown,
  required final Uri page,
  required final void Function(GuideLink link) onLink,
  super.key,
}) extends StatefulWidget {
  @override
  State<GuideMarkdown> createState() => _GuideMarkdownState();
}

class _GuideMarkdownState() extends State<GuideMarkdown> {
  List<md.Node> _nodes = const [];
  final _recognizers = <TapGestureRecognizer>[];

  /// Each heading's text and the key of its widget, for a section link.
  final _headings = <(String, GlobalKey)>[];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(GuideMarkdown old) {
    super.didUpdateWidget(old);
    if (old.markdown != widget.markdown) {
      _parse();
    }
  }

  void _parse() {
    _nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parse(widget.markdown);
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    _headings.clear();
  }

  void _tap(String href, String text) {
    switch (resolveGuideLink(widget.page, href)) {
      case ScrollTo():
        final context = _headings
            .where((h) => h.$1 == text)
            .firstOrNull
            ?.$2
            .currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: hlMotion(context, HlDuration.short),
            curve: HlEasing.standard,
          ).ignore();
        }
      case final link?:
        widget.onLink(link);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // The spans of the last build are gone with this one.
    _clear();
    final theme = Theme.of(context);
    final colors = SnacklistColors.of(theme.brightness);
    final blocks = _Blocks(
      colors: colors,
      body: HlType.body.copyWith(color: colors.text),
      recognizer: (href, text) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _tap(href, text);
        _recognizers.add(recognizer);
        return recognizer;
      },
      heading: (text) {
        final key = GlobalKey();
        _headings.add((text, key));
        return key;
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks.of(_nodes),
    );
  }
}

/// Builds the widgets of a run of block nodes.
final class _Blocks({
  required final SnacklistColors colors,
  required final TextStyle body,
  required final TapGestureRecognizer Function(String href, String text)
  recognizer,
  required final GlobalKey Function(String text) heading,
}) {
  static const _gap = HlSpace.s4;

  _Blocks _withBody(TextStyle style) => _Blocks(
    colors: colors,
    body: style,
    recognizer: recognizer,
    heading: heading,
  );

  TextStyle get _mono => body.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Courier New', 'Courier'],
    fontSize: (body.fontSize ?? 17) - 2,
    height: 1.4,
  );

  /// [nodes] as blocks, [gap] above each but the first. Inline nodes
  /// between blocks (a tight list item's text) make one paragraph.
  List<Widget> of(List<md.Node> nodes, {double gap = _gap}) {
    final widgets = <Widget>[];
    final inline = <md.Node>[];
    void add(Widget block, {required double above}) => widgets.add(
      widgets.isEmpty
          ? block
          : Padding(
              padding: EdgeInsets.only(top: above),
              child: block,
            ),
    );
    void flush() {
      if (inline.isNotEmpty) {
        add(_paragraph(List.of(inline)), above: gap);
        inline.clear();
      }
    }

    for (final node in nodes) {
      if (node is md.Element && _blockTags.contains(node.tag)) {
        flush();
        add(_block(node), above: _above(node.tag) ?? gap);
      } else {
        inline.add(node);
      }
    }
    flush();
    return widgets;
  }

  static const _blockTags = {
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'p',
    'ul',
    'ol',
    'blockquote',
    'pre',
    'table',
    'hr',
  };

  /// Headings sit closer to what follows than to what came before.
  static double? _above(String tag) => switch (tag) {
    'h1' || 'h2' => HlSpace.s6,
    'h3' || 'h4' || 'h5' || 'h6' => HlSpace.s5,
    _ => null,
  };

  Widget _block(md.Element e) => switch (e.tag) {
    'h1' => _heading(
      e,
      HlType.headline.copyWith(color: colors.text, height: 1.1),
    ),
    'h2' => _heading(e, HlType.title.copyWith(color: colors.text)),
    'h3' || 'h4' || 'h5' || 'h6' => _heading(
      e,
      body.copyWith(fontWeight: FontWeight.w700, height: 1.3),
    ),
    'ul' || 'ol' => _list(e),
    'blockquote' => _quote(e),
    'pre' => _code(e),
    'table' => _table(e),
    'hr' => Divider(height: 1, thickness: 1, color: colors.divider),
    _ => _paragraph(e.children ?? const []),
  };

  /// The parser keeps the spaces after a list marker (`1.  Öffne`) as
  /// the item's text; the marker column already parts them.
  Widget _paragraph(List<md.Node> nodes, {TextStyle? style}) => Text.rich(
    TextSpan(
      children: _spans([
        if (nodes.firstOrNull case md.Text(:final text))
          md.Text(text.trimLeft())
        else
          ...nodes.take(1),
        ...nodes.skip(1),
      ], style ?? body),
    ),
  );

  Widget _heading(md.Element e, TextStyle style) => Semantics(
    key: heading(e.textContent),
    header: true,
    child: _paragraph(e.children ?? const [], style: style),
  );

  Widget _list(md.Element list) {
    final ordered = list.tag == 'ol';
    final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = [
      for (final item in list.children ?? const <md.Node>[])
        if (item is md.Element && item.tag == 'li') item,
    ];
    // A loose list's items are paragraphs, each a group of its own: the
    // blocks of one item sit closer than the items.
    final loose = items.any(
      (item) => (item.children ?? const []).any(
        (child) => child is md.Element && child.tag == 'p',
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: loose ? HlSpace.s4 : HlSpace.s2,
      children: [
        for (final (i, item) in items.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: HlSpace.s5 + (ordered ? HlSpace.s1 : 0),
                child: Text(
                  ordered ? '${start + i}.' : '•',
                  style: body.copyWith(
                    color: ordered ? colors.text : colors.brand,
                    fontWeight: ordered ? FontWeight.w700 : null,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: of(item.children ?? const [], gap: HlSpace.s2),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _quote(md.Element e) => DecoratedBox(
    decoration: BoxDecoration(
      color: colors.accentSoft,
      borderRadius: BorderRadius.circular(HlRadius.s),
    ),
    child: Padding(
      padding: const EdgeInsets.all(HlSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _withBody(body.copyWith(color: colors.onAccentSoft))
            .of(e.children ?? const []),
      ),
    ),
  );

  Widget _code(md.Element e) => DecoratedBox(
    decoration: BoxDecoration(
      color: colors.surfaceSunken,
      borderRadius: BorderRadius.circular(HlRadius.s),
    ),
    child: SelectionArea(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(HlSpace.s3),
        child: Text(e.textContent.trimRight(), style: _mono),
      ),
    ),
  );

  /// Each body row as a block of its cells, each under its header.
  Widget _table(md.Element table) {
    List<md.Element> rows(String section) => [
      for (final part in table.children ?? const <md.Node>[])
        if (part is md.Element && part.tag == section)
          for (final row in part.children ?? const <md.Node>[])
            if (row is md.Element && row.tag == 'tr') row,
    ];
    List<md.Element> cells(md.Element row) => [
      for (final cell in row.children ?? const <md.Node>[])
        if (cell is md.Element) cell,
    ];
    final headers = [for (final row in rows('thead')) ...cells(row)];
    final label = body.copyWith(
      fontSize: HlType.label.fontSize,
      fontWeight: FontWeight.w700,
      height: 1.3,
      color: colors.textMuted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: HlSpace.s2,
      children: [
        for (final row in rows('tbody'))
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              border: Border.all(color: colors.divider),
              borderRadius: BorderRadius.circular(HlRadius.s),
            ),
            child: Padding(
              padding: const EdgeInsets.all(HlSpace.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: HlSpace.s3,
                children: [
                  for (final (i, cell) in cells(row).indexed)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: HlSpace.s1,
                      children: [
                        if (headers.elementAtOrNull(i) case final header?
                            when header.textContent.trim().isNotEmpty)
                          _paragraph(header.children ?? const [], style: label),
                        _paragraph(cell.children ?? const []),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<InlineSpan> _spans(
    List<md.Node> nodes,
    TextStyle style, {
    TapGestureRecognizer? link,
  }) => [
    for (final node in nodes)
      switch (node) {
        md.Element(tag: 'br') => const TextSpan(text: '\n'),
        md.Element(tag: 'a') => _link(node, style),
        md.Element(tag: 'strong') => TextSpan(
          children: _spans(
            node.children ?? const [],
            style.copyWith(fontWeight: FontWeight.w700),
            link: link,
          ),
        ),
        md.Element(tag: 'em') => TextSpan(
          children: _spans(
            node.children ?? const [],
            style.copyWith(fontStyle: FontStyle.italic),
            link: link,
          ),
        ),
        md.Element(tag: 'del') => TextSpan(
          children: _spans(
            node.children ?? const [],
            style.copyWith(decoration: TextDecoration.lineThrough),
            link: link,
          ),
        ),
        md.Element(tag: 'code') => TextSpan(
          text: node.textContent,
          recognizer: link,
          style: _mono.copyWith(
            color: style.color,
            fontSize: (style.fontSize ?? 17) - 2,
            backgroundColor: colors.surfaceSunken,
          ),
        ),
        md.Element(tag: 'img') => TextSpan(
          text: node.attributes['alt'] ?? '',
          style: style,
          recognizer: link,
        ),
        md.Element(:final children) => TextSpan(
          children: _spans(children ?? const [], style, link: link),
        ),
        _ => TextSpan(text: node.textContent, style: style, recognizer: link),
      },
  ];

  InlineSpan _link(md.Element a, TextStyle style) {
    final href = a.attributes['href'];
    final linked = style.copyWith(
      color: colors.accent,
      decoration: TextDecoration.underline,
      decorationColor: colors.accent,
    );
    return TextSpan(
      children: _spans(
        a.children ?? const [],
        linked,
        link: href == null ? null : recognizer(href, a.textContent),
      ),
    );
  }
}
