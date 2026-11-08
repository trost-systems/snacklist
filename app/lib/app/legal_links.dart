import 'dart:async';

import 'package:family_groceries/app/guides.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a page on hummlist.com in the system browser (a new tab on the
/// web), never in an in-app browser view: the app offers no web browsing
/// of its own (App Store age rating, "Unrestricted Web Access: No").
Future<void> openLegalPage(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// A link to [url] that opens like [openLegalPage]. On the web it is a
/// real `<a target="_blank">`, so the address shows on hover and can be
/// copied.
class const LegalLink({
  required final Uri url,
  required final Widget Function(BuildContext, VoidCallback? open) builder,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Link(
    uri: url,
    target: LinkTarget.blank,
    builder: (context, follow) =>
        builder(context, follow == null ? null : () => unawaited(follow())),
  );
}

/// "Impressum · Datenschutz" below the sign-in form, reachable before
/// anyone signs in (DDG §5, DSGVO Art. 13).
class const LegalFooter({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final style = Theme.of(context).textTheme.bodyMedium;
    Widget link(String key, String label, Uri url) => LegalLink(
      key: ValueKey(key),
      url: url,
      builder: (context, open) => TextButton(
        onPressed: open,
        child: Text(
          label,
          style: style?.copyWith(decoration: TextDecoration.underline),
        ),
      ),
    );
    // Wraps on a narrow phone with large text instead of running off it.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        link('legal-imprint', l10n.imprint, imprintUrl(language)),
        ExcludeSemantics(child: Text('·', style: style)),
        link('legal-privacy', l10n.privacy, privacyPolicyUrl(language)),
      ],
    );
  }
}
