import 'dart:async';

import 'package:family_groceries/session/your_name.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// The server's name for the one signed-in user: [row] answers reads,
/// [saved] has each save as sent.
class FakeNameRepository({
  var NameRow? row = (name: 'Lea Brandt', chosen: false, fromEmail: false),
}) implements NameRepository {
  final saved = <String>[];
  var reads = 0;

  /// The next reads throw this.
  Exception? readError;

  /// The next saves throw this.
  NameError? saveError;

  /// When set, [save] waits for it.
  Completer<void>? holdSave;

  @override
  Future<NameRow?> read() async {
    reads++;
    if (readError case final error?) {
      throw error;
    }
    return row;
  }

  @override
  Future<String> save(String name) async {
    saved.add(name);
    await holdSave?.future;
    if (saveError case final error?) {
      throw error;
    }
    row = (name: name, chosen: true, fromEmail: false);
    return name;
  }
}

/// The device's postponements, in memory.
class MemoryPostponements() implements NamePostponements {
  final postponed = <String>{};

  @override
  Future<bool> postponedNameFor(String userId) async =>
      postponed.contains(userId);

  @override
  Future<void> savePostponedName(String userId) async => postponed.add(userId);
}

/// [userId]'s sign-in as GoTrue tells it.
supabase.AuthState signedInAs(
  String userId, {
  supabase.AuthChangeEvent event = supabase.AuthChangeEvent.signedIn,
}) => supabase.AuthState(
  event,
  supabase.Session(
    accessToken: 'jwt',
    tokenType: 'bearer',
    user: supabase.User(
      id: userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-17T12:00:00Z',
    ),
  ),
);

/// A name cubit that never hears of a sign-in: it stays unread.
YourNameCubit idleYourName() => YourNameCubit(
  FakeNameRepository(),
  MemoryPostponements(),
  const Stream.empty(),
);
