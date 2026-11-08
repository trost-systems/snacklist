import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a token is for.
enum AccessKind() {
  /// Made by the user, for the MCP server or a Shortcut.
  pat,

  /// Made by the app for native Siri on one iPhone, bound to its session.
  siri,

  /// Made by the user for the public REST API (job 73, docs/API.md); never
  /// accepted by the MCP server or Siri.
  api,
}

/// What an API key may do: the two scope sets the server accepts.
enum ApiScopes(final List<String> wire) {
  read(['read']),
  readWrite(['read', 'write']);

  /// The row's `scopes`; null for every kind but [AccessKind.api].
  static ApiScopes? parse(Object? scopes) => switch (scopes) {
    final List<Object?> s when s.contains('write') => readWrite,
    List<Object?>() => read,
    _ => null,
  };
}

/// A personal access token as the settings list shows it. The secret itself
/// is never readable after creation.
@immutable
class const AccessToken({
  required final String id,
  required final String name,

  /// The last four characters, to tell tokens apart.
  required final String hint,
  required final DateTime createdAt,
  final AccessKind kind = AccessKind.pat,

  /// Set exactly for [AccessKind.api].
  final ApiScopes? scopes,
  final DateTime? lastUsedAt,
}) {
  factory fromJson(Map<String, dynamic> json) => AccessToken(
    id: json['id']! as String,
    name: json['name']! as String,
    kind: switch (json['kind']) {
      'siri' => AccessKind.siri,
      'api' => AccessKind.api,
      _ => AccessKind.pat,
    },
    scopes: ApiScopes.parse(json['scopes']),
    hint: json['token_hint']! as String,
    createdAt: DateTime.parse(json['created_at']! as String).toLocal(),
    lastUsedAt: switch (json['last_used_at']) {
      final String at => DateTime.parse(at).toLocal(),
      _ => null,
    },
  );
}

/// A freshly created token; [token] is the only copy of the secret.
@immutable
class const NewToken({required final String name, required final String token});

/// An OAuth client the user granted access to.
@immutable
class const ConnectedApp({
  required final String clientId,
  required final String name,
  required final DateTime grantedAt,
  required final List<String> scopes,

  /// Where it was approved, like `Chrome · macOS`; null for grants from
  /// before job 80 or a label that could not be recorded.
  final String? device,

  /// Its newest token refresh, about hourly while in use; null before the
  /// first.
  final DateTime? lastUsedAt,
});

/// The server refused a request; [code] is its message, e.g.
/// `too_many_tokens`.
final class const AccessError(final String code) implements Exception;

/// The settings screen's only door to the backend.
abstract interface class AccessRepository() {
  /// Active tokens, newest first. Revoked tokens are not listed.
  Future<List<AccessToken>> fetchTokens();

  /// An MCP token.
  Future<NewToken> createToken(String name);

  /// Throws [AccessError] `too_many_tokens` (10 per member),
  /// `session_required` (not the app's own sign-in) or `api_disabled` (the
  /// server's public API is switched off).
  Future<NewToken> createApiToken(String name, ApiScopes scopes);

  Future<void> revokeToken(String id);

  Future<List<ConnectedApp>> fetchApps();

  Future<void> disconnect(String clientId);
}

/// [household]: the one new tokens and API keys are bound to, the
/// household shown (job 169b); null binds them to the default household.
class SupabaseAccessRepository(
  final SupabaseClient _client, {
  final String? household,
}) implements AccessRepository {
  @override
  Future<List<AccessToken>> fetchTokens() => _guard(() async {
    final rows = await _client.rest
        .from('personal_access_tokens')
        .select('id, name, kind, scopes, token_hint, created_at, last_used_at')
        .isFilter('revoked_at', null)
        .order('created_at', ascending: false);
    return rows.map(AccessToken.fromJson).toList();
  });

  @override
  Future<NewToken> createToken(String name) => _guard(() async {
    final row = await _client
        .rpc<List<Map<String, dynamic>>>(
          'create_personal_access_token',
          params: {'p_name': name, 'p_household': ?household},
        )
        .single();
    return NewToken(
      name: row['name']! as String,
      token: row['token']! as String,
    );
  });

  @override
  Future<NewToken> createApiToken(String name, ApiScopes scopes) =>
      _guard(() async {
        final row = await _client
            .rpc<List<Map<String, dynamic>>>(
              'create_api_token',
              params: {
                'p_name': name,
                'p_scopes': scopes.wire,
                'p_household': ?household,
              },
            )
            .single();
        return NewToken(
          name: row['name']! as String,
          token: row['token']! as String,
        );
      });

  @override
  Future<void> revokeToken(String id) => _guard(
    () => _client.rest
        .from('personal_access_tokens')
        .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id),
  );

  @override
  Future<List<ConnectedApp>> fetchApps() => _guard(() async {
    final details = _details();
    final grants = await _client.auth.oauth.listGrants();
    final byClient = await details;
    return [
      for (final grant in grants)
        ConnectedApp(
          clientId: grant.client.clientId,
          name: grant.client.clientName ?? grant.client.clientId,
          grantedAt: grant.grantedAt.toLocal(),
          scopes: grant.scopes,
          device: byClient[grant.client.clientId]?.device,
          lastUsedAt: byClient[grant.client.clientId]?.lastUsedAt,
        ),
    ];
  });

  /// Job 80's device label and last activity per client id. Never throws:
  /// a server without them yet (the web app deploys next to the migration)
  /// or a failed call leaves the rows without, and a failure of the grants
  /// themselves must not leave this future's error unhandled.
  Future<Map<String, ({String? device, DateTime? lastUsedAt})>>
  _details() async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _client.rpc<List<Map<String, dynamic>>>(
        'connected_app_details',
      );
    } on Object catch (e) {
      debugPrint('connected_app_details: $e');
      return const {};
    }
    return {
      for (final row in rows)
        row['client_id']! as String: (
          device: row['device'] as String?,
          lastUsedAt: switch (row['last_used_at']) {
            final String at => DateTime.parse(at).toLocal(),
            _ => null,
          },
        ),
    };
  }

  @override
  Future<void> disconnect(String clientId) =>
      _guard(() => _client.auth.oauth.revokeGrant(clientId));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      throw AccessError(e.message);
    } on AuthException catch (e) {
      throw AccessError(e.message);
    }
  }
}
