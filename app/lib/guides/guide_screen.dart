import 'dart:async';

import 'package:family_groceries/core/legal_links.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/guides/guide_link.dart';
import 'package:family_groceries/guides/guide_markdown.dart';
import 'package:family_groceries/guides/guide_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Reads a guide page ([fetchGuide] by default).
typedef GuideLoader = Future<GuideFetch> Function(Uri page);

/// A guide or guide list of snacklist.app ([page], a [guidePage]) in the
/// app's own type (job 462): the app has no browser view (App Store
/// "Unrestricted Web Access: No", `core/legal_links.dart`), so it reads the
/// page's Markdown twin and renders it. A link to another guide pushes it,
/// one to an app path goes there, any other opens [openOutside] (the
/// system browser). Back pops, or opens the list when this is the first
/// screen (the app was opened by the link).
///
/// In the web app the guide is the site's page itself: the browser goes
/// there (the site sends no CORS headers for the twin).
class const GuideScreen({
  required final Uri page,
  final GuideLoader? load,
  final Future<void> Function(Uri url) openOutside = openLegalPage,
  super.key,
}) extends StatefulWidget {
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState() extends State<GuideScreen> {
  /// Null while loading.
  GuideFetch? _fetched;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(launchUrl(widget.page, webOnlyWindowName: '_self'));
    } else {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(GuideScreen old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page && !kIsWeb) {
      _fetched = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final page = widget.page;
    final fetched = await (widget.load ?? _fetch)(page);
    if (mounted && page == widget.page) {
      setState(() => _fetched = fetched);
    }
  }

  static Future<GuideFetch> _fetch(Uri page) async {
    final client = http.Client();
    try {
      return await fetchGuide(client, page);
    } finally {
      client.close();
    }
  }

  void _open(GuideLink link) {
    switch (link) {
      case OpenGuide(:final location):
        unawaited(context.push(location));
      case OpenScreen(:final location):
        context.go(location);
      case OpenOutside(:final url):
        unawaited(widget.openOutside(url));
      case ScrollTo():
        break;
    }
  }

  void _retry() {
    setState(() => _fetched = null);
    unawaited(_load());
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = SnacklistColors.of(Theme.of(context).brightness);
    final index = guideIndexOf(widget.page);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          key: const ValueKey('guide-back'),
          onPressed: _back,
        ),
      ),
      body: switch (_fetched) {
        null => const Center(child: CircularProgressIndicator()),
        GuideShown(:final markdown) => SingleChildScrollView(
          key: const ValueKey('guide-shown'),
          padding: EdgeInsets.fromLTRB(
            HlSpace.s5,
            HlSpace.s2,
            HlSpace.s5,
            HlSpace.s7 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              // The shell's page width (`pageMaxWidth`).
              constraints: const BoxConstraints(maxWidth: 640),
              child: GuideMarkdown(
                markdown: markdown,
                page: widget.page,
                onLink: _open,
              ),
            ),
          ),
        ),
        GuideMissing() => _Notice(
          key: const ValueKey('guide-missing'),
          text: l10n.guideMissing,
          color: colors.text,
          action: widget.page.path == index
              ? null
              : FilledButton(
                  key: const ValueKey('guide-all'),
                  onPressed: () => context.pushReplacement(index),
                  child: Text(l10n.guideAllGuides),
                ),
        ),
        GuideFailed() => _Notice(
          key: const ValueKey('guide-failed'),
          text: l10n.guideFailed,
          color: colors.text,
          action: FilledButton(
            key: const ValueKey('guide-retry'),
            onPressed: _retry,
            child: Text(l10n.retry),
          ),
        ),
      },
    );
  }
}

/// A line in the middle of the page and the one thing to do about it.
class const _Notice({
  required final String text,
  required final Color color,
  required final Widget? action,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(HlSpace.s5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: HlSpace.s5,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: HlType.bodyL.copyWith(color: color),
            ),
            ?action,
          ],
        ),
      ),
    ),
  );
}
