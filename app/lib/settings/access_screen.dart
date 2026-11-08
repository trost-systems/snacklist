import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/app/legal_links.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_features_card.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/settings/access_cubit.dart';
import 'package:family_groceries/settings/access_repository.dart';
import 'package:family_groceries/settings/integration_lock.dart';
import 'package:family_groceries/siri/siri_channel.dart';
import 'package:family_groceries/siri/siri_phrases.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ways in from outside the app: the MCP endpoint, Siri, personal access
/// tokens, API keys and OAuth-connected apps (`/more/access`). A page of the More
/// tab, which gives it its frame.
class const AccessScreen({
  super.key,

  /// Overrides the Supabase repository for a household (null: the
  /// default), for tests.
  final AccessRepository Function(String? household)? repositories,

  /// Overrides the platform's Siri channel (iOS only), for tests.
  final SiriChannel? siri,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final siri =
        this.siri ??
        siriChannelFor(web: kIsWeb, platform: defaultTargetPlatform);
    // New tokens and API keys are bound to the household shown (job 169b):
    // a switch makes a new cubit for the new one.
    final household = context.select<SessionCubit?, String?>(
      (session) => switch (session?.state) {
        InHousehold(:final household) => household.id,
        _ => null,
      },
    );
    return BlocProvider(
      key: ValueKey(household),
      create: (_) {
        final cubit = AccessCubit(
          repositories?.call(household) ??
              SupabaseAccessRepository(
                Supabase.instance.client,
                household: household,
              ),
          siri: siri,
        );
        unawaited(cubit.load());
        // Job 50: the server's lock switches, read again on every visit.
        unawaited(context.read<IntegrationLockCubit?>()?.refresh());
        return cubit;
      },
      child: _Access(onIphone: siri != null),
    );
  }
}

/// A user-made token named like the old Shortcut recipe's (`Siri` in
/// docs/SIRI_SHORTCUT.md), which native Siri replaces.
bool _isShortcutToken(AccessToken token) =>
    token.kind == AccessKind.pat &&
    RegExp(
      'siri|kurzbefehl|shortcut',
      caseSensitive: false,
    ).hasMatch(token.name);

final _apiDocs = Uri.parse(
  'https://github.com/trost-systems/family-groceries/blob/main/docs/API.md',
);

class const _Access({required final bool onIphone}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AccessCubit>().state;
    final tokens = switch (state.tokens) {
      SectionLoaded(:final value) => value,
      _ => const <AccessToken>[],
    };
    final siriTokens = [
      for (final t in tokens)
        if (t.kind == AccessKind.siri) t,
    ];
    final shortcutTokens = tokens.where(_isShortcutToken).toList();
    final apiKeys = [
      for (final t in tokens)
        if (t.kind == AccessKind.api) t,
    ];
    // No Flags above (a screen on its own, in tests): off.
    final apiOffered = context.select<Flags?, bool>(
      (flags) => flags?.isOn(publicApiFlag) ?? false,
    );
    final access = _accessOf(context);
    final paused = access is IntegrationsLocked;
    // With several households, the one new keys act in (job 169b).
    final shownOfSeveral = context.select<SessionCubit?, String?>(
      (session) => switch (session?.state) {
        InHousehold(:final household, :final households)
            when households.length > 1 =>
          household.name,
        _ => null,
      },
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          key: const ValueKey('access-screen'),
          // Clear of the floating tab pill.
          padding: EdgeInsets.only(
            top: 8,
            bottom: 8 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            if (access case IntegrationsLocked(:final offer))
              _PremiumCard(offer: offer),
            HlSectionLabel(
              l10n.mcpServer,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            ),
            ListTile(
              title: const SelectionArea(child: Text(Environment.mcpUrl)),
              subtitle: Text(l10n.mcpServerBody),
              trailing: IconButton(
                tooltip: l10n.copy,
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(context, Environment.mcpUrl),
              ),
            ),
            if (onIphone || siriTokens.isNotEmpty)
              HlSectionLabel(
                l10n.siriHeader,
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              ),
            if (onIphone) _SiriCard(shortcutTokens: shortcutTokens),
            for (final token in siriTokens)
              _TokenTile(
                token: token,
                label: token.id == state.siriHere
                    ? l10n.siriThisIphone
                    : l10n.siriOtherIphone,
                paused: paused,
              ),
            HlSectionLabel(
              l10n.accessTokens,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            ),
            Padding(
              key: const ValueKey('access-tokens-hint'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              // Points at the API only where the API section offers it.
              child: Text(
                apiOffered
                    ? l10n.accessTokensHintWithApi
                    : l10n.accessTokensHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (shownOfSeveral case final household?)
              Padding(
                key: const ValueKey('access-keys-household'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  apiOffered
                      ? l10n.accessKeysHouseholdWithApi(household)
                      : l10n.accessKeysHousehold(household),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ..._section(
              context,
              switch (state.tokens) {
                SectionLoaded(:final value) => SectionLoaded([
                  for (final t in value)
                    if (t.kind == AccessKind.pat) t,
                ]),
                final other => other,
              },
              empty: l10n.noTokens,
              tile: (token) =>
                  _TokenTile(token: token, label: token.name, paused: paused),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.createToken),
                  onPressed: () => unawaited(_createToken(context)),
                ),
              ),
            ),
            if (apiOffered || apiKeys.isNotEmpty)
              ..._apiSection(
                context,
                apiKeys: apiKeys,
                offered: apiOffered,
                paused: paused,
              ),
            HlSectionLabel(
              l10n.connectedApps,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            ),
            ..._section(
              context,
              state.apps,
              empty: l10n.noConnectedApps,
              tile: (app) => _AppTile(
                app: app,
                paused: paused && app.name != _alexaClientName,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Job 50: whether to show the lock. Without the app-wide cubit (a
  /// screen on its own) or with the `INTEGRATION_LOCK` define off, never.
  static IntegrationAccess _accessOf(BuildContext context) {
    final server = context.watch<IntegrationLockCubit?>()?.state;
    if (server == null) {
      return const IntegrationsOpen();
    }
    return integrationAccess(
      server: server,
      // Watched: a purchase by any member arrives over Realtime and hides
      // the card within one sync.
      entitlements: context.watch<Entitlements>(),
      noSale: context.read<PurchaseCubit>().state.noSale,
    );
  }

  static List<Widget> _section<T>(
    BuildContext context,
    Section<List<T>> section, {
    required String empty,
    required Widget Function(T value) tile,
  }) => switch (section) {
    SectionLoading() => const [
      Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
    ],
    SectionFailed(:final message) => [
      ListTile(title: Text(AppLocalizations.of(context).genericError(message))),
    ],
    SectionLoaded(value: []) => [ListTile(title: Text(empty))],
    SectionLoaded(:final value) => [for (final v in value) tile(v)],
  };
}

void _copy(BuildContext context, String text) {
  unawaited(Clipboard.setData(ClipboardData(text: text)));
  Notices.of(
    context,
  ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).copied)));
}

String _errorText(AppLocalizations l10n, Object error, AccessKind kind) =>
    switch ((error, kind)) {
      (AccessError(code: 'too_many_tokens'), AccessKind.api) =>
        l10n.tooManyApiKeys,
      (AccessError(code: 'too_many_tokens'), _) => l10n.tooManyTokens,
      (AccessError(code: 'session_required'), AccessKind.api) =>
        l10n.apiKeySessionRequired,
      (AccessError(code: 'api_disabled'), AccessKind.api) => l10n.apiDisabled,
      (AccessError(:final code), _) => l10n.genericError(code),
      _ => l10n.genericError('$error'),
    };

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Runs [action] on a credential of [kind], showing a failure as a snack
/// bar.
Future<void> _attempt(
  BuildContext context,
  Future<void> Function() action, {
  AccessKind kind = AccessKind.pat,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = Notices.of(context);
  try {
    await action();
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(_errorText(l10n, e, kind))));
  }
}

Future<void> _createToken(BuildContext context) async {
  final cubit = context.read<AccessCubit>();
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const _NameDialog(),
  );
  if (name == null || !context.mounted) {
    return;
  }
  await _attempt(context, () async {
    final token = await cubit.create(name);
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NewTokenDialog(token: token, kind: AccessKind.pat),
      );
    }
  });
}

Future<void> _createApiKey(BuildContext context) async {
  final cubit = context.read<AccessCubit>();
  final picked = await showDialog<(String, ApiScopes)>(
    context: context,
    builder: (_) => const _ApiKeyDialog(),
  );
  if (picked == null || !context.mounted) {
    return;
  }
  final (name, scopes) = picked;
  await _attempt(context, kind: AccessKind.api, () async {
    final token = await cubit.createApi(name, scopes);
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NewTokenDialog(token: token, kind: AccessKind.api),
      );
    }
  });
}

String _scopesLabel(AppLocalizations l10n, ApiScopes scopes) =>
    switch (scopes) {
      ApiScopes.read => l10n.apiScopeRead,
      ApiScopes.readWrite => l10n.apiScopeReadWrite,
    };

/// The list's category label, for a settings group: 11 px heavy caps,
/// 0.12 em tracking, muted, and a hairline rule after it.

class const _SiriCard({required final List<AccessToken> shortcutTokens})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const ValueKey('siri-card'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.siriSayHint),
            for (final token in shortcutTokens)
              Padding(
                key: const ValueKey('siri-legacy-hint'),
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.siriOldShortcutHint(token.name)),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('siri-phrases'),
                onPressed: () => unawaited(
                  showDialog<void>(
                    context: context,
                    builder: (_) => const _SiriPhrasesDialog(),
                  ),
                ),
                child: Text(l10n.siriShowPhrases),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Both languages: Siri listens in the iPhone's, not the app's.
class const _SiriPhrasesDialog() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final english = (l10n.siriPhrasesEnglish, siriPhrases.en);
    final german = (l10n.siriPhrasesGerman, siriPhrases.de);
    final languages = l10n.localeName == 'en'
        ? [english, german]
        : [german, english];
    return AlertDialog(
      title: Text(l10n.siriPhrasesTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (language, phrases) in languages) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  language,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final phrase in phrases) Text(l10n.siriPhrase(phrase)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class const _TokenTile({
  required final AccessToken token,

  /// The token's name, or what a Siri credential is called.
  required final String label,

  /// The household is locked (job 50): the token stays, unused for now.
  final bool paused = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lastUsed = token.lastUsedAt;
    return ListTile(
      key: token.kind == AccessKind.api ? const ValueKey('api-key-tile') : null,
      leading: Icon(switch (token.kind) {
        AccessKind.pat => Icons.key,
        AccessKind.siri => Icons.mic_none,
        AccessKind.api => Icons.api,
      }),
      title: Text(label),
      subtitle: _Subtitle(
        [
          l10n.tokenHint(token.hint),
          if (token.scopes case final scopes?) _scopesLabel(l10n, scopes),
          l10n.createdOn(token.createdAt),
          if (lastUsed == null) l10n.neverUsed else l10n.lastUsedOn(lastUsed),
        ].join(' · '),
        paused: paused,
      ),
      trailing: IconButton(
        tooltip: l10n.revokeToken(label),
        icon: const Icon(Icons.delete_outline),
        onPressed: () => unawaited(_revoke(context)),
      ),
    );
  }

  Future<void> _revoke(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<AccessCubit>();
    final (title, body) = switch (token.kind) {
      AccessKind.pat => (l10n.revokeTokenTitle, l10n.revokeTokenBody),
      AccessKind.siri => (l10n.revokeSiriTitle, l10n.revokeSiriBody),
      AccessKind.api => (l10n.revokeApiKeyTitle, l10n.revokeApiKeyBody),
    };
    final confirmed = await _confirm(
      context,
      title: title,
      body: body,
      action: l10n.revoke,
    );
    if (confirmed && context.mounted) {
      await _attempt(context, () => cubit.revoke(token.id));
    }
  }
}

/// The OAuth client Alexa links with (docs/ALEXA.md). Alexa stays free
/// (Legal Review N-27), so its connection never shows as paused. The grant
/// carries no redirect URIs, so its name is all the app can go by.
const _alexaClientName = 'Amazon Alexa';

/// Job 73: the public REST API. Its keys are listed whenever there are
/// any, so they can always be revoked; the URL, the docs and new keys only
/// while the `public-api` flag is on. Rows of the page's list, not one
/// widget, so screen readers get the heading and each row on their own.
List<Widget> _apiSection(
  BuildContext context, {
  required List<AccessToken> apiKeys,
  required bool offered,
  required bool paused,
}) {
  final l10n = AppLocalizations.of(context);
  return [
    HlSectionLabel(
      key: const ValueKey('api-section'),
      l10n.apiHeader,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    ),
    if (offered) ...[
      ListTile(
        key: const ValueKey('api-url'),
        title: const SelectionArea(child: Text(Environment.apiUrl)),
        subtitle: Text(l10n.apiBody),
        trailing: IconButton(
          tooltip: l10n.copy,
          icon: const Icon(Icons.copy),
          onPressed: () => _copy(context, Environment.apiUrl),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: LegalLink(
            key: const ValueKey('api-docs'),
            url: _apiDocs,
            builder: (context, open) => TextButton.icon(
              icon: const Icon(Icons.open_in_new),
              onPressed: open,
              label: Text(l10n.apiDocs),
            ),
          ),
        ),
      ),
    ],
    if (paused)
      Padding(
        key: const ValueKey('api-premium'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(l10n.apiPremium),
      ),
    for (final apiKey in apiKeys)
      _TokenTile(token: apiKey, label: apiKey.name, paused: paused),
    if (offered && apiKeys.isEmpty) ListTile(title: Text(l10n.noApiKeys)),
    if (offered)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const ValueKey('api-create'),
            icon: const Icon(Icons.add),
            label: Text(l10n.createApiKey),
            onPressed: () => unawaited(_createApiKey(context)),
          ),
        ),
      ),
  ];
}

/// A connected app: where it was approved and when it was connected and
/// last active (job 80). A tap opens [_AppDetails].
class const _AppTile({
  required final ConnectedApp app,
  final bool paused = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lastUsed = app.lastUsedAt;
    return ListTile(
      key: ValueKey('app-${app.clientId}'),
      leading: const Icon(Icons.smart_toy_outlined),
      title: Text(app.name),
      subtitle: _Subtitle(
        [
          ?app.device,
          l10n.connectedOn(app.grantedAt),
          if (lastUsed != null) l10n.lastActiveOn(lastUsed),
        ].join(' · '),
        paused: paused,
      ),
      onTap: () => unawaited(
        showModalBottomSheet<void>(
          context: context,
          // Above the tab bar, like a dialog.
          useRootNavigator: true,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => BlocProvider.value(
            value: context.read<AccessCubit>(),
            child: _AppDetails(app: app, paused: paused),
          ),
        ),
      ),
      trailing: IconButton(
        tooltip: l10n.disconnectApp(app.name),
        icon: const Icon(Icons.link_off),
        onPressed: () => unawaited(_disconnectApp(context, app)),
      ),
    );
  }
}

/// Asks, then disconnects [app]; true once it is gone.
Future<bool> _disconnectApp(BuildContext context, ConnectedApp app) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<AccessCubit>();
  final confirmed = await _confirm(
    context,
    title: l10n.disconnectTitle(app.name),
    body: l10n.disconnectBody,
    action: l10n.disconnect,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  var done = false;
  await _attempt(context, () async {
    await cubit.disconnect(app.clientId);
    done = true;
  });
  return done;
}

/// What a connected app may do, in plain words, and the way to disconnect
/// it. The scopes' own names ("Deine Anmeldung bestätigen") said little.
class const _AppDetails({
  required final ConnectedApp app,
  required final bool paused,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final lastUsed = app.lastUsedAt;
    final can = [
      l10n.consentListAccess(app.name),
      for (final scope in app.scopes)
        ?switch (scope) {
          'email' => l10n.appCanEmail,
          'profile' => l10n.appCanProfile,
          'phone' => l10n.appCanPhone,
          'offline_access' => l10n.appCanStay,
          _ => null,
        },
    ];
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('app-details'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(app.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            for (final line in [
              ?switch (app.device) {
                final device? => l10n.appDevice(device),
                null => null,
              },
              l10n.connectedOn(app.grantedAt),
              if (lastUsed == null)
                l10n.notActiveYet
              else
                l10n.lastActiveOn(lastUsed),
            ])
              Text(line, style: muted),
            if (paused)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.integrationPaused,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            HlSectionLabel(
              l10n.appCanTitle(app.name),
              padding: const EdgeInsets.only(top: 24, bottom: 8),
            ),
            for (final sentence in can)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check,
                      size: 20,
                      color: HummlistColors.of(theme.brightness).brand,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(sentence)),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              key: const ValueKey('app-details-disconnect'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.link_off),
              label: Text(l10n.disconnectApp(app.name)),
              onPressed: () async {
                final navigator = Navigator.of(context);
                if (await _disconnectApp(context, app)) {
                  navigator.pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A connection's details, below them "paused" while the household is
/// locked (job 50).
class const _Subtitle(final String details, {required final bool paused})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!paused) {
      return Text(details);
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(details),
        Text(
          AppLocalizations.of(context).integrationPaused,
          key: const ValueKey('access-paused'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Job 50: Siri and AI assistants are part of Hummlist Premium (Alexa stays
/// free), for a household known to have none while the server enforces the
/// lock. Nothing is removed; [offer] says how to unlock it.
class const _PremiumCard({required final LockOffer offer})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('integration-premium'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: PremiumFeaturesCard(
        title: l10n.integrationPremiumTitle,
        titleStyle: theme.textTheme.titleMedium,
        body: l10n.integrationPremiumBody,
        footer: switch (offer) {
          LockOffer.buy => FilledButton(
            key: const ValueKey('integration-buy'),
            onPressed: () => context.go(
              Uri(
                path: premiumPath,
                queryParameters: {'from': 'integrations'},
              ).toString(),
            ),
            child: Text(l10n.integrationPremiumBuy),
          ),
          LockOffer.soon => Text(
            l10n.integrationPremiumSoon,
            key: const ValueKey('integration-soon'),
            style: theme.textTheme.titleSmall,
          ),
          LockOffer.inTheApps => Text(
            l10n.premiumWeb,
            key: const ValueKey('integration-in-the-apps'),
          ),
        },
      ),
    );
  }
}

class const _NameDialog() extends StatefulWidget {
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState() extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_name.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.createToken),
      content: LabeledField(
        label: l10n.tokenName,
        field: TextField(
          controller: _name,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(hintText: l10n.tokenNameHint),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.create)),
      ],
    );
  }
}

/// A new API key's name and what it may do; pops both.
class const _ApiKeyDialog() extends StatefulWidget {
  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState() extends State<_ApiKeyDialog> {
  final _name = TextEditingController();

  /// Read only unless the user asks for more.
  var _scopes = ApiScopes.read;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop((_name.text.trim(), _scopes));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.createApiKey),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: l10n.tokenName,
            field: TextField(
              controller: _name,
              autofocus: true,
              maxLength: 60,
              decoration: InputDecoration(hintText: l10n.apiKeyNameHint),
              onSubmitted: (_) => _submit(),
            ),
          ),
          RadioGroup<ApiScopes>(
            groupValue: _scopes,
            onChanged: (scopes) => setState(() => _scopes = scopes ?? _scopes),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final scopes in ApiScopes.values)
                  HexRadioTile<ApiScopes>(
                    key: ValueKey(switch (scopes) {
                      ApiScopes.read => 'api-scope-read',
                      ApiScopes.readWrite => 'api-scope-write',
                    }),
                    value: scopes,
                    title: Text(_scopesLabel(l10n, scopes)),
                    subtitle: Text(switch (scopes) {
                      ApiScopes.read => l10n.apiScopeReadBody,
                      ApiScopes.readWrite => l10n.apiScopeReadWriteBody,
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.create)),
      ],
    );
  }
}

/// The only time the secret is shown.
class const _NewTokenDialog({
  required final NewToken token,

  /// An MCP token or an API key, as the dialog calls it.
  required final AccessKind kind,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, shownOnce) = kind == AccessKind.api
        ? (l10n.apiKeyCreated, l10n.apiKeyShownOnce)
        : (l10n.tokenCreated, l10n.tokenShownOnce);
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(shownOnce),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SelectionArea(
                  child: Text(
                    token.token,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.copy,
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(context, token.token),
              ),
            ],
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}
