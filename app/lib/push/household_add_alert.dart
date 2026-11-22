import 'dart:async';

import 'package:family_groceries/push/push_registration.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// The signed-in user's household-add alert on the server
/// (`public.push_preferences`, docs/PUSH.md, "Household add").
abstract interface class HouseholdAddPrefs() {
  /// Whether the alert is on and the language its text is written in; null
  /// when the user never switched it.
  Future<({bool on, String language})?> load();

  Future<void> save({required bool on, required String language});
}

class const SupabaseHouseholdAddPrefs(final SupabaseClient _client)
    implements HouseholdAddPrefs {
  @override
  Future<({bool on, String language})?> load() async {
    final row = await _client
        .from('push_preferences')
        .select('household_add, language')
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return (
      on: row['household_add'] == true,
      language: row['language'] as String? ?? 'de',
    );
  }

  @override
  Future<void> save({required bool on, required String language}) =>
      _client.rpc<void>(
        'set_push_household_add',
        params: {'p_on': on, 'p_language': language},
      );
}

/// What a switch of the alert came to.
enum HouseholdAddResult() {
  done,

  /// The OS refuses notifications; nothing was switched on.
  blocked,

  /// The server did not take it (offline); the switch stays as it was.
  failed,
}

/// Whether the signed-in user gets a push when another member adds an item
/// (job 377). Null until the server has answered. Off by default: the
/// first yes is also what asks the OS for permission ([PushRegistration]).
class HouseholdAddAlert(
  final PushRegistration _push,
  final HouseholdAddPrefs _prefs,
) extends Cubit<bool?> {
  this : super(null);

  /// Reads the setting, and writes [language] again when the app's language
  /// changed since the alert was switched on, so the text follows it.
  Future<void> refresh(String language) async {
    try {
      final saved = await _prefs.load();
      emit(saved?.on ?? false);
      if (saved != null && saved.on && saved.language != language) {
        await _prefs.save(on: true, language: language);
      }
    } on Object {
      // Offline: the switch stays hidden until the next look.
    }
  }

  Future<HouseholdAddResult> set({
    required bool on,
    required String language,
  }) async {
    if (on && !await _push.optIn()) {
      return HouseholdAddResult.blocked;
    }
    try {
      await _prefs.save(on: on, language: language);
    } on Object {
      return HouseholdAddResult.failed;
    }
    emit(on);
    return HouseholdAddResult.done;
  }
}
