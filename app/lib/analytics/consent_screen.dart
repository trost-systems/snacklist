import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/guides.dart';
import 'package:family_groceries/core/legal_links.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Asked once per install, right after the first sign-in and before
/// onboarding or the list: may Snacklist send usage data and error reports?
/// Both answers are one tap and equally prominent; the router moves on as
/// soon as one is stored. Peter approved the wording on 2026-10-30.
class const AnalyticsConsentScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      // A title, like every other page: screen readers (and the web engine's
      // focus on a new page) start on it, not on the sign-out button.
      appBar: AppBar(
        title: Text(l10n.analyticsSection),
        actions: [
          IconButton(
            tooltip: l10n.signOut,
            icon: const Icon(Icons.logout),
            onPressed: () => unawaited(context.read<SessionCubit>().signOut()),
          ),
        ],
      ),
      // One list like the welcome screen's. A layout with the answers pinned
      // below a scrolling text made the web engine move the list's add field
      // in the page after this one and lose its focus (DECISIONS 19.20).
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            key: const ValueKey('analytics-consent'),
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: const [ConsentQuestion()],
          ),
        ),
      ),
    );
  }
}

/// The question itself, the same words on the consent screen and as the
/// guided start's first step (job 168b): icon, title, text with the privacy
/// link, and both answers, equally prominent.
class const ConsentQuestion({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.query_stats_outlined,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        // Own nodes: one list item on its own, the web merged the title and
        // the text into one block that screen readers read at once.
        Semantics(
          container: true,
          header: true,
          child: Text(
            l10n.analyticsConsentTitle,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          container: true,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${l10n.analyticsConsentBody} '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: LegalLink(
                    key: const ValueKey('analytics-consent-privacy'),
                    url: privacyPolicyUrl(
                      Localizations.localeOf(context).languageCode,
                    ),
                    builder: (context, open) => GestureDetector(
                      onTap: open,
                      child: Text(
                        l10n.analyticsConsentPrivacyLink,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Builder(
          builder: (context) {
            final decline = FilledButton.tonal(
              key: const ValueKey('analytics-consent-decline'),
              onPressed: () =>
                  unawaited(context.read<Analytics>().decide(granted: false)),
              child: Text(l10n.analyticsDecline),
            );
            final accept = FilledButton.tonal(
              key: const ValueKey('analytics-consent-accept'),
              onPressed: () =>
                  unawaited(context.read<Analytics>().decide(granted: true)),
              child: Text(l10n.analyticsAccept),
            );
            if (MediaQuery.sizeOf(context).width < 400) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  decline,
                  const SizedBox(height: HlSpace.s3),
                  accept,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: decline),
                const SizedBox(width: HlSpace.s3),
                Expanded(child: accept),
              ],
            );
          },
        ),
      ],
    );
  }
}
