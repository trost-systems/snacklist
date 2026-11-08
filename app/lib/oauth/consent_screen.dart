import 'dart:async';

import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/oauth/device_label.dart';
import 'package:family_groceries/oauth/user_agent.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// What the authorization server asks the user to approve.
sealed class const ConsentRequest();

/// The user approved this client before; the server already decided.
final class const AlreadyApproved(final Uri redirect) extends ConsentRequest;

@immutable
final class const NeedsConsent({
  required final String clientId,
  required final String clientName,
  required final List<String> scopes,
  final String? clientUri,
  final String? email,
}) extends ConsentRequest;

/// Supabase Auth's OAuth server, as the consent screen needs it. Approve and
/// deny return where to send the browser next.
abstract interface class ConsentApi() {
  Future<ConsentRequest> getDetails(String authorizationId);

  /// Also records [device] for [clientId] (job 80), which Zugänge shows.
  Future<Uri> approve(
    String authorizationId, {
    required String clientId,
    required String device,
  });

  Future<Uri> deny(String authorizationId);
}

class SupabaseConsentApi(final SupabaseClient _client) implements ConsentApi {
  GoTrueOAuthApi get _oauth => _client.auth.oauth;

  @override
  Future<ConsentRequest> getDetails(String authorizationId) async =>
      switch (await _oauth.getAuthorizationDetails(authorizationId)) {
        OAuthAuthorizationRedirectResponse(:final redirectUrl) =>
          AlreadyApproved(Uri.parse(redirectUrl)),
        OAuthAuthorizationDetailsResponse(
          :final client,
          :final user,
          :final scope,
        ) =>
          NeedsConsent(
            clientId: client.clientId,
            clientName: client.clientName ?? client.clientId,
            clientUri: client.clientUri,
            email: user.email,
            scopes: (scope ?? '')
                .split(' ')
                .where((s) => s.isNotEmpty)
                .toList(),
          ),
      };

  @override
  Future<Uri> approve(
    String authorizationId, {
    required String clientId,
    required String device,
  }) async {
    final redirect = _redirect(
      await _oauth.approveAuthorization(authorizationId),
    );
    try {
      await _client.rpc<void>(
        'record_oauth_device',
        params: {'p_client': clientId, 'p_device': device},
      );
    } on Object catch (e) {
      // The connection works without its label; Zugänge then shows none.
      debugPrint('oauth consent: no device label: $e');
    }
    return redirect;
  }

  @override
  Future<Uri> deny(String authorizationId) async =>
      _redirect(await _oauth.denyAuthorization(authorizationId));

  static Uri _redirect(OAuthConsentResponse response) => switch (response) {
    OAuthConsentResponse(:final String redirectUrl) => Uri.parse(redirectUrl),
    _ => throw const AuthException('no redirect_url'),
  };
}

String scopeLabel(AppLocalizations l10n, String scope) => switch (scope) {
  'openid' => l10n.scopeOpenid,
  'email' => l10n.scopeEmail,
  'profile' => l10n.scopeProfile,
  'phone' => l10n.scopePhone,
  'offline_access' => l10n.scopeOfflineAccess,
  _ => scope,
};

/// Supabase Auth sends the browser here (`/oauth/consent?authorization_id=`)
/// when an MCP client asks to connect.
class const ConsentScreen({
  required final String? authorizationId,
  super.key,

  /// Overrides the Supabase API, for tests.
  final ConsentApi? api,

  /// Overrides leaving the app for the client's redirect, for tests.
  final Future<void> Function(Uri url)? navigate,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    if (session is! InHousehold) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ConsentView(
      authorizationId: authorizationId,
      // MCP over OAuth acts in the default household (job 169b), not the
      // one this device shows.
      household: session.defaultHousehold,
      several: session.households.length > 1,
      api: api ?? SupabaseConsentApi(Supabase.instance.client),
      navigate: navigate ?? _openHere,
    );
  }

  static Future<void> _openHere(Uri url) =>
      launchUrl(url, webOnlyWindowName: '_self');
}

class const ConsentView({
  required final String? authorizationId,

  /// The user's default household, the one the client acts in.
  required final Household household,
  required final ConsentApi api,
  required final Future<void> Function(Uri url) navigate,

  /// The user has several households: the line says it is the default.
  final bool several = false,
  super.key,
}) extends StatefulWidget {
  @override
  State<ConsentView> createState() => _ConsentViewState();
}

sealed class const _Phase();

final class const _Loading() extends _Phase;

final class const _Failed() extends _Phase;

final class const _Asking(final NeedsConsent request) extends _Phase;

/// The user tapped allow or deny; the server records it.
final class const _Deciding(final NeedsConsent request) extends _Phase;

/// Decided; the browser is on its way to the client. The client's callback
/// can take seconds (Claude's took about 10, docs/MCP.md), and the browser
/// keeps this page up until it answers, so it says the user is done.
final class const _Left({
  required final NeedsConsent? request,
  required final bool approved,
}) extends _Phase;

class _ConsentViewState() extends State<ConsentView> {
  _Phase _phase = const _Loading();

  @override
  void initState() {
    super.initState();
    final id = widget.authorizationId;
    if (id == null || id.isEmpty) {
      _phase = const _Failed();
    } else {
      unawaited(
        _guard(() async {
          switch (await widget.api.getDetails(id)) {
            case AlreadyApproved(:final redirect):
              _show(const _Left(request: null, approved: true));
              await widget.navigate(redirect);
            case final NeedsConsent request:
              _show(_Asking(request));
          }
        }),
      );
    }
  }

  void _show(_Phase phase) {
    if (mounted) {
      setState(() => _phase = phase);
    }
  }

  Future<void> _decide(NeedsConsent request, {required bool approve}) =>
      _guard(() async {
        _show(_Deciding(request));
        final id = widget.authorizationId!;
        final redirect = await (approve
            ? widget.api.approve(
                id,
                clientId: request.clientId,
                device: deviceLabel(
                  platform: defaultTargetPlatform,
                  userAgent: browserUserAgent(),
                ),
              )
            : widget.api.deny(id));
        _show(_Left(request: request, approved: approve));
        await widget.navigate(redirect);
      });

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on AuthException catch (e) {
      debugPrint('oauth consent: ${e.message}');
      _show(const _Failed());
    } on Object catch (e) {
      debugPrint('oauth consent: $e');
      _show(const _Failed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final body = switch (_phase) {
      _Loading() => const [Center(child: CircularProgressIndicator())],
      _Failed() => [
        Text(l10n.consentInvalid, style: theme.textTheme.bodyMedium),
        const SizedBox(height: HlSpace.s5),
        OutlinedButton(
          key: const ValueKey('consent-back-to-list'),
          onPressed: () => context.go(listPath),
          child: Text(l10n.consentBackToList),
        ),
      ],
      _Asking(:final request) || _Deciding(:final request) => _details(
        context,
        request,
        deciding: _phase is _Deciding,
      ),
      _Left(:final request, :final approved) => [
        Icon(
          approved ? Icons.check_circle_outline : Icons.block,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: HlSpace.s5),
        Text(
          switch ((request?.clientName, approved)) {
            (final client?, true) => l10n.consentDone(client),
            (null, _) => l10n.consentDoneNoClient,
            (final client?, false) => l10n.consentDeclined(client),
          },
          key: const ValueKey('consent-done'),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      ],
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_phase) {
          _Failed() => l10n.consentErrorTitle,
          _Left(approved: true) => l10n.consentConnectedTitle,
          _Left(approved: false) => l10n.consentDeclinedTitle,
          _ => l10n.consentTitle,
        }),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: body,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _details(
    BuildContext context,
    NeedsConsent request, {
    required bool deciding,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final clientUri = request.clientUri;
    final email = request.email;
    return [
      Text(request.clientName, style: theme.textTheme.headlineSmall),
      if (clientUri != null) Text(clientUri, style: theme.textTheme.bodySmall),
      const SizedBox(height: 16),
      if (email != null) Text(l10n.consentSignedInAs(email)),
      Text(
        widget.several
            ? l10n.consentDefaultHousehold(widget.household.name)
            : l10n.consentHousehold(widget.household.name),
      ),
      const SizedBox(height: 16),
      Text(
        l10n.consentWants(request.clientName),
        style: theme.textTheme.titleMedium,
      ),
      for (final permission in [
        l10n.consentListAccess(request.clientName),
        for (final scope in request.scopes) scopeLabel(l10n, scope),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check),
          title: Text(permission),
        ),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: deciding
                ? null
                : () => unawaited(_decide(request, approve: false)),
            child: Text(l10n.consentDeny),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: deciding
                ? null
                : () => unawaited(_decide(request, approve: true)),
            child: Text(l10n.consentAllow),
          ),
        ],
      ),
    ];
  }
}
