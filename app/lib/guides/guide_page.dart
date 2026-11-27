import 'dart:async';

import 'package:family_groceries/core/legal_links.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/guides/model.dart';
import 'package:family_groceries/guides/source.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The guides' routes (job 462): each locale's index at the site's path,
/// its guides below it. Siblings, not nested: a guide opened by a link is
/// the only page, and closes to the app's start.
List<RouteBase> guideRoutes() => [
  for (final locale in GuideLocale.values) ...[
    GoRoute(
      path: GuideRef(locale).path,
      builder: (_, state) =>
          GuidePage(ref: GuideRef(locale), anchor: _anchorOf(state)),
    ),
    GoRoute(
      path: '${GuideRef(locale).path}/:slug',
      builder: (_, state) => GuidePage(
        ref: GuideRef(locale, state.pathParameters['slug']),
        anchor: _anchorOf(state),
      ),
    ),
  ],
];

/// A link's `#section`, scrolled to once the guide is loaded.
String? _anchorOf(GoRouterState state) =>
    state.uri.fragment.isEmpty ? null : state.uri.fragment;

/// A guides page of snacklist.app shown in the app (job 462): [ref]'s index
/// or guide, from the JSON the site build writes ([GuideSource]). Native,
/// never a web view: the app offers no web browsing of its own, and on
/// Android a claimed URL opened in the browser would come back here.
///
/// Public: it shows signed out and before any gate. Opened from a link it
/// is the only page, and closing it goes to the app's start, where the
/// usual way (sign-in, household) begins.
class const GuidePage({
  required final GuideRef ref,
  final String? anchor,
  super.key,
}) extends StatefulWidget {
  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState() extends State<GuidePage> {
  /// Null while loading.
  GuideAnswer? _answer;
  final _headings = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(GuidePage old) {
    super.didUpdateWidget(old);
    if (old.ref.path != widget.ref.path) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() => _answer = null);
    final ref = widget.ref;
    final answer = await context.read<GuideSource>().load(ref);
    if (mounted && ref.path == widget.ref.path) {
      setState(() => _answer = answer);
      if (widget.anchor case final id?) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollTo(id);
          }
        });
      }
    }
  }

  void _close() => context.go('/');

  void _follow(GuideLink link) => switch (link) {
    AnchorLink(:final id) => _scrollTo(id),
    InAppLink(:final ref, :final anchor) => unawaited(
      context.push(anchor == null ? ref.path : '${ref.path}#$anchor'),
    ),
    WebLink(:final url) => unawaited(openLegalPage(url)),
  };

  void _scrollTo(String id) {
    if (_headings[id]?.currentContext case final heading?) {
      Scrollable.ensureVisible(
        heading,
        duration: hlMotion(context, HlDuration.medium),
        curve: HlEasing.standard,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canPop = GoRouter.of(context).canPop();
    final isGuide = widget.ref.slug != null;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _close();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: canPop
              ? null
              : CloseButton(
                  key: const ValueKey('guide-close'),
                  onPressed: _close,
                ),
        ),
        body: switch (_answer) {
          null => const Center(
            key: ValueKey('guide-loading'),
            child: CircularProgressIndicator(),
          ),
          GuideFailed() => _Problem(
            key: const ValueKey('guide-failed'),
            text: isGuide ? l10n.guideFailed : l10n.guidesFailed,
            action: l10n.retry,
            onPressed: () => unawaited(_load()),
          ),
          GuideMissing() when isGuide => _Problem(
            key: const ValueKey('guide-missing'),
            text: l10n.guideMissing,
            action: l10n.guidesAll,
            onPressed: () => context.go(GuideRef(widget.ref.locale).path),
          ),
          GuideMissing() => _Problem(
            key: const ValueKey('guide-failed'),
            text: l10n.guidesFailed,
            action: l10n.retry,
            onPressed: () => unawaited(_load()),
          ),
          GuideLoaded(content: final Guide guide) => _Article(
            title: guide.title,
            children: [
              for (final block in guide.blocks)
                _BlockView(block, headings: _headings, onLink: _follow),
            ],
          ),
          GuideLoaded(content: final GuideIndex index) => _Article(
            title: index.title,
            flush: true,
            children: [
              HlGroup(
                top: 0,
                children: [
                  for (final entry in index.guides)
                    FocusRingTile(
                      key: ValueKey('guide-entry-${entry.slug}'),
                      child: ListTile(
                        title: Text(entry.title),
                        subtitle: entry.description.isEmpty
                            ? null
                            : Text(entry.description),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => unawaited(
                          context.push(GuideRef(index.locale, entry.slug).path),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        },
      ),
    );
  }
}

/// Why nothing shows, and the one way on.
class const _Problem({
  required final String text,
  required final String action,
  required final VoidCallback onPressed,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(HlSpace.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: HlSpace.s4,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          FilledButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    ),
  );
}

/// The page's title over its blocks, in a reading column. Not a lazy list:
/// an anchor link needs its heading built to scroll to it.
///
/// [flush]: the children bring their own side insets ([HlGroup] does), and
/// only the title gets the column's.
class const _Article({
  required final String title,
  required final List<Widget> children,
  final bool flush = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    return SelectionArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          flush ? 0 : HlSpace.s4,
          HlSpace.s2,
          flush ? 0 : HlSpace.s4,
          HlSpace.s7,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: HlSpace.s3,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: flush ? HlSpace.s4 : 0,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: t.text,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: HlSpace.s1),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _BlockView(
  final GuideBlock block, {
  required final Map<String, GlobalKey> headings,
  required final void Function(GuideLink) onLink,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final body = theme.textTheme.bodyLarge?.copyWith(color: t.text);
    Widget blocks(List<GuideBlock> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: HlSpace.s2,
      children: [
        for (final child in children)
          _BlockView(child, headings: headings, onLink: onLink),
      ],
    );
    return switch (block) {
      HeadingBlock(:final level, :final id, :final text) => Padding(
        key: id == null ? null : headings.putIfAbsent(id, GlobalKey.new),
        padding: EdgeInsets.only(top: level == 2 ? HlSpace.s4 : HlSpace.s2),
        child: Semantics(
          header: true,
          child: _Spans(
            text,
            style: switch (level) {
              2 => theme.textTheme.titleLarge,
              3 => theme.textTheme.titleMedium,
              _ => theme.textTheme.titleSmall,
            }?.copyWith(color: t.text),
            onLink: onLink,
          ),
        ),
      ),
      ParagraphBlock(:final text) => _Spans(text, style: body, onLink: onLink),
      ListBlock(:final ordered, :final items) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: HlSpace.s2,
        children: [
          for (final (i, item) in items.indexed)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: HlSpace.s5,
                  child: ExcludeSemantics(
                    excluding: !ordered,
                    child: Text(ordered ? '${i + 1}.' : '•', style: body),
                  ),
                ),
                Expanded(child: blocks(item)),
              ],
            ),
        ],
      ),
      QuoteBlock(blocks: final children) => Container(
        padding: const EdgeInsets.only(left: HlSpace.s3),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: t.honey, width: 4)),
        ),
        child: blocks(children),
      ),
      CodeBlock(:final text) => DecoratedBox(
        decoration: BoxDecoration(
          color: t.surfaceSunken,
          borderRadius: BorderRadius.circular(softRadius(40)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(HlSpace.s3),
          child: Text(text, style: _code(theme.textTheme.bodyMedium)),
        ),
      ),
      TableBlock(:final header, :final rows) => _Table(
        header: header,
        rows: rows,
        onLink: onLink,
      ),
    };
  }
}

/// Android knows `monospace`, iOS Menlo.
TextStyle? _code(TextStyle? style) => style?.copyWith(
  fontFamily: 'monospace',
  fontFamilyFallback: const ['Menlo', 'Courier'],
);

/// A table as a grid where it fits, and on a phone each row as a card whose
/// cells sit under their header: a few words per column of a 358 px wide
/// grid read worse than the same words stacked.
class const _Table({
  required final List<List<Span>> header,
  required final List<List<List<Span>>> rows,
  required final void Function(GuideLink) onLink,
}) extends StatelessWidget {
  static const _gridFrom = 520.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final body = theme.textTheme.bodyMedium?.copyWith(color: t.text);
    final label = theme.textTheme.labelLarge?.copyWith(color: t.textMuted);
    final edge = BorderSide(color: t.divider);
    final radius = BorderRadius.circular(cardRadius);
    Widget cell(List<Span> spans, TextStyle? style) => Padding(
      padding: const EdgeInsets.all(HlSpace.s3),
      child: _Spans(spans, style: style, onLink: onLink),
    );
    final columns = [
      header.length,
      for (final row in rows) row.length,
    ].reduce((a, b) => a > b ? a : b);
    List<Widget> cells(List<List<Span>> row, TextStyle? style) => [
      for (var i = 0; i < columns; i++)
        cell(i < row.length ? row[i] : const [], style),
    ];
    return LayoutBuilder(
      builder: (context, constraints) =>
          columns > 0 && constraints.maxWidth >= _gridFrom
          ? Table(
              border: TableBorder.all(color: t.divider, borderRadius: radius),
              children: [
                if (header.isNotEmpty) TableRow(children: cells(header, label)),
                for (final row in rows) TableRow(children: cells(row, body)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: HlSpace.s2,
              children: [
                for (final row in rows)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.fromBorderSide(edge),
                      borderRadius: radius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(HlSpace.s3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: HlSpace.s1,
                        children: [
                          for (final (i, spans) in row.indexed) ...[
                            if (i < header.length && header[i].isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: i == 0 ? 0 : HlSpace.s2,
                                ),
                                child: _Spans(
                                  header[i],
                                  style: label,
                                  onLink: onLink,
                                ),
                              ),
                            _Spans(spans, style: body, onLink: onLink),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// [spans] as one run of text; a span with a link is tappable.
class const _Spans(
  final List<Span> spans, {
  required final TextStyle? style,
  required final void Function(GuideLink) onLink,
}) extends StatefulWidget {
  @override
  State<_Spans> createState() => _SpansState();
}

class _SpansState() extends State<_Spans> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          for (final span in widget.spans)
            TextSpan(
              text: span.text,
              style: _style(span, t),
              recognizer: _recognizer(span.link),
            ),
        ],
      ),
    );
  }

  TapGestureRecognizer? _recognizer(GuideLink? link) {
    if (link == null) {
      return null;
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onLink(link);
    _recognizers.add(recognizer);
    return recognizer;
  }

  TextStyle? _style(Span span, SnacklistColors t) {
    var style = const TextStyle();
    if (span.strong) {
      style = style.copyWith(fontWeight: FontWeight.w700);
    }
    if (span.em) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    if (span.code) {
      style = _code(style)!.copyWith(backgroundColor: t.surfaceSunken);
    }
    if (span.link != null) {
      style = style.copyWith(
        color: t.accent,
        decoration: TextDecoration.underline,
        decorationColor: t.accent,
      );
    }
    return style;
  }
}
