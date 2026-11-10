import 'dart:async';
import 'dart:io';

import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef IdTokenCall = ({OAuthProvider provider, String idToken, String? nonce});

/// Records what the app sends to Supabase Auth.
class FakeAuth() extends Fake implements GoTrueClient {
  final states = StreamController<AuthState>.broadcast();
  final idTokenCalls = <IdTokenCall>[];
  final metadataUpdates = <Map<String, Object?>>[];
  final signOutScopes = <SignOutScope>[];
  Exception? idTokenError;
  User? user;

  @override
  Stream<AuthState> get onAuthStateChange => states.stream;

  @override
  User? get currentUser => user;

  Future<void> close() => states.close();

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) async {
    if (idTokenError case final error?) {
      throw error;
    }
    idTokenCalls.add((provider: provider, idToken: idToken, nonce: nonce));
    return AuthResponse();
  }

  /// Clears the session and tells listeners, as GoTrue does.
  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    signOutScopes.add(scope);
    user = null;
    states.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  @override
  Future<UserResponse> updateUser(
    UserAttributes attributes, {
    String? emailRedirectTo,
  }) async {
    metadataUpdates.add(attributes.data! as Map<String, Object?>);
    return UserResponse.fromJson({});
  }
}

/// A client whose database is unreachable; [onQuery] sees each attempt.
class FakeClient(final FakeAuth fakeAuth, {final void Function()? onQuery})
    extends Fake
    implements SupabaseClient {
  @override
  GoTrueClient get auth => fakeAuth;

  @override
  PostgrestClient get rest {
    onQuery?.call();
    throw const SocketException('offline');
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    Object? get,
  }) {
    onQuery?.call();
    throw const SocketException('offline');
  }
}

/// The device cache, in memory; [households] is its contents.
class MemorySessionCache() implements SessionCache {
  final households = <String, ({List<Household> households, String? shown})>{};
  var forgotten = 0;

  /// Each user's told removals, which [forget] keeps.
  final toldRemovalsOf = <String, Set<String>>{};

  /// Caches [household] as the user's only one, shown.
  void only(String userId, Household household) =>
      households[userId] = (households: [household], shown: household.id);

  @override
  Future<({List<Household> households, String? shown})?> householdsOf(
    String userId,
  ) async => households[userId];

  @override
  Future<void> remember(
    String userId, {
    required List<Household> households,
    String? shown,
  }) async {
    if (households.isEmpty) {
      this.households.remove(userId);
    } else {
      this.households[userId] = (households: households, shown: shown);
    }
  }

  @override
  Future<void> forget() async {
    households.clear();
    forgotten++;
  }

  @override
  Future<Set<String>> toldRemovals(String userId) async =>
      toldRemovalsOf[userId] ?? const {};

  @override
  Future<void> rememberToldRemovals(String userId, Set<String> keys) async =>
      toldRemovalsOf[userId] = keys;
}

/// A provider dialog that answers with [result] or throws [error].
class FakeNativeSignIn() extends Fake implements NativeSignIn {
  final hashedNonces = <(SocialProvider, String)>[];
  NativeCredential result = (
    idToken: 'id-token',
    givenName: null,
    familyName: null,
  );
  Exception? error;

  @override
  Future<NativeCredential> signIn(
    SocialProvider provider, {
    required String hashedNonce,
  }) async {
    hashedNonces.add((provider, hashedNonce));
    if (error case final error?) {
      throw error;
    }
    return result;
  }
}
