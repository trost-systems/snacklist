import 'dart:convert';

import 'package:family_groceries/core/deep_links.dart';

/// A guide's language, with the site's path segment for its guides
/// (`/de/anleitungen`, `/en/guides`). The app routes the same paths.
enum GuideLocale(final String segment) {
  de('anleitungen'),
  en('guides');

  static GuideLocale? parse(String code) =>
      values.where((l) => l.name == code).firstOrNull;
}

/// A place in the guides: a locale's index ([slug] null) or one guide.
/// Its [path] is the same on snacklist.app and in the app.
final class const GuideRef(final GuideLocale locale, [final String? slug]) {
  /// The place [path] names, the same on the site and in the app; null for
  /// any other path. The apps claim everything below a locale's guides:
  /// `<slug>.md` (the Markdown twin) and `<slug>.html` are that guide, any
  /// other path the index.
  static GuideRef? ofPath(String path) =>
      switch (Uri(path: path).pathSegments) {
        [final code, final segment, ...final rest] => switch ((
          _in(code, segment),
          rest,
        )) {
          (null, _) => null,
          (final index?, [final name] || [final name, ''])
              when isSlug(_bare(name)) =>
            GuideRef(index.locale, _bare(name)),
          (final index?, _) => index,
        },
        _ => null,
      };

  static String _bare(String name) =>
      name.replaceFirst(RegExp(r'\.(md|html)$'), '');

  static bool isSlug(String slug) => _slug.hasMatch(slug);

  static GuideRef? _in(String code, String segment) =>
      switch (GuideLocale.parse(code)) {
        final locale? when locale.segment == segment => GuideRef(locale),
        _ => null,
      };

  static final _slug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  String get path => switch (slug) {
    final slug? => '/${locale.name}/${locale.segment}/$slug',
    null => '/${locale.name}/${locale.segment}',
  };

  /// Where the site build writes this place's JSON (`site/guide-data.mjs`).
  String get dataPath => '/data/guides/${locale.name}/${slug ?? 'index'}.json';
}

/// What a guide's link does when tapped.
sealed class const GuideLink();

/// `#id`: scrolls to the heading with that id on the same page.
final class const AnchorLink(final String id) extends GuideLink;

/// Another guide, or a guide index: opens in the app, at the heading
/// [anchor] names if it has one.
final class const InAppLink(final GuideRef ref, [final String? anchor])
    extends GuideLink;

/// Anything else on the web: opens in the system browser.
final class const WebLink(final Uri url) extends GuideLink;

/// A run of text with its marks.
final class const Span(
  final String text, {
  final bool strong = false,
  final bool em = false,
  final bool code = false,
  final GuideLink? link,
});

sealed class const GuideBlock();

final class const HeadingBlock({
  required final int level,
  required final String? id,
  required final List<Span> text,
}) extends GuideBlock;

final class const ParagraphBlock(final List<Span> text) extends GuideBlock;

/// An ordered or bulleted list; each item is a list of blocks.
final class const ListBlock({
  required final bool ordered,
  required final List<List<GuideBlock>> items,
}) extends GuideBlock;

final class const QuoteBlock(final List<GuideBlock> blocks) extends GuideBlock;

final class const CodeBlock(final String text) extends GuideBlock;

/// A table: [header] cells, then [rows] of cells; a cell is spans.
final class const TableBlock({
  required final List<List<Span>> header,
  required final List<List<List<Span>>> rows,
}) extends GuideBlock;

/// What a guides page shows: an index or a guide.
sealed class const GuideContent({
  required final GuideLocale locale,
  required final String title,
});

/// One guide as production renders it on the site, minus its page chrome.
final class const Guide({
  required super.locale,
  required final String slug,
  required super.title,
  required final List<GuideBlock> blocks,
}) extends GuideContent;

/// A locale's guides, in the site's order.
final class const GuideIndex({
  required super.locale,
  required super.title,
  required final List<GuideEntry> guides,
}) extends GuideContent;

final class const GuideEntry({
  required final String slug,
  required final String title,
  required final String description,
});

/// [body] as the content of [ref] (schema 1), or null when it is not one.
/// Blocks and spans of a type this app does not know, or out of shape, are
/// left out: the site may add kinds an older app cannot show.
GuideContent? parseGuideContent(GuideRef ref, String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return null;
  }
  final locale = ref.locale;
  return switch ((ref.slug, json)) {
    (
      final slug?,
      {
        'schema': 1,
        'locale': final String code,
        'slug': final String s,
        'title': final String title,
        'blocks': final List<Object?> blocks,
      },
    )
        when code == locale.name && s == slug =>
      Guide(
        locale: locale,
        slug: slug,
        title: title,
        blocks: _uniqueIds(_blocks(blocks), {}),
      ),
    (
      null,
      {
        'schema': 1,
        'locale': final String code,
        'title': final String title,
        'guides': final List<Object?> guides,
      },
    )
        when code == locale.name =>
      GuideIndex(
        locale: locale,
        title: title,
        guides: [
          for (final entry in guides)
            if (entry
                case {'slug': final String slug, 'title': final String title} &&
                    final Map<Object?, Object?> fields
                when GuideRef.isSlug(slug))
              GuideEntry(
                slug: slug,
                title: title,
                description: _string(fields['description']),
              ),
        ],
      ),
    _ => null,
  };
}

String _string(Object? value) => value is String ? value : '';

List<GuideBlock> _blocks(List<Object?> raw) => [
  for (final block in raw) ?_block(block),
];

GuideBlock? _block(Object? raw) => switch (raw) {
  {
            'type': 'heading',
            'level': final int level,
            'text': final List<Object?> text,
          } &&
          final Map<Object?, Object?> fields
      when level >= 2 && level <= 4 =>
    HeadingBlock(level: level, id: _id(fields['id']), text: _spans(text)),
  {'type': 'paragraph', 'text': final List<Object?> text} => ParagraphBlock(
    _spans(text),
  ),
  {
    'type': 'list',
    'ordered': final bool ordered,
    'items': final List<Object?> items,
  } =>
    ListBlock(
      ordered: ordered,
      items: [
        for (final item in items)
          if (item is List<Object?>) _blocks(item),
      ],
    ),
  {'type': 'quote', 'blocks': final List<Object?> blocks} => QuoteBlock(
    _blocks(blocks),
  ),
  {'type': 'code', 'text': final String text} => CodeBlock(text),
  {
    'type': 'table',
    'header': final List<Object?> header,
    'rows': final List<Object?> rows,
  } =>
    TableBlock(
      header: _cells(header),
      rows: [
        for (final row in rows)
          if (row is List<Object?>) _cells(row),
      ],
    ),
  _ => null,
};

/// [blocks] with only the first heading of each id keeping it: an anchor
/// scrolls to one heading.
List<GuideBlock> _uniqueIds(List<GuideBlock> blocks, Set<String> seen) => [
  for (final block in blocks)
    switch (block) {
      HeadingBlock(:final level, :final id?, :final text) when !seen.add(id) =>
        HeadingBlock(level: level, id: null, text: text),
      ListBlock(:final ordered, :final items) => ListBlock(
        ordered: ordered,
        items: [for (final item in items) _uniqueIds(item, seen)],
      ),
      QuoteBlock(blocks: final children) => QuoteBlock(
        _uniqueIds(children, seen),
      ),
      _ => block,
    },
];

String? _id(Object? id) => id is String && id.isNotEmpty ? id : null;

List<List<Span>> _cells(List<Object?> raw) => [
  for (final cell in raw)
    if (cell is List<Object?>) _spans(cell) else const [],
];

List<Span> _spans(List<Object?> raw) => [
  for (final span in raw)
    if (span
        case {'text': final String text} && final Map<Object?, Object?> marks
        when text.isNotEmpty)
      Span(
        text,
        strong: marks['strong'] == true,
        em: marks['em'] == true,
        code: marks['code'] == true,
        link: switch (marks['href']) {
          final String href => linkOf(href),
          _ => null,
        },
      ),
];

/// What tapping [href] does; null for a link the app will not follow (a
/// relative path, another scheme).
GuideLink? linkOf(String href) {
  final uri = Uri.tryParse(href);
  if (uri == null) {
    return null;
  }
  if (!uri.hasScheme && !uri.hasAuthority && uri.path.isEmpty) {
    return uri.fragment.isEmpty ? null : AnchorLink(uri.fragment);
  }
  if (uri.scheme == 'https' && LinkHost.site.hosts.contains(uri.host)) {
    if (GuideRef.ofPath(uri.path) case final ref?) {
      return InAppLink(ref, uri.fragment.isEmpty ? null : uri.fragment);
    }
  }
  return switch (uri.scheme) {
    'https' || 'http' || 'mailto' => WebLink(uri),
    _ => null,
  };
}
