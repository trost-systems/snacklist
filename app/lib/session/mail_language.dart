import 'dart:async';
import 'dart:ui';

import 'package:family_groceries/app/language.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The `user_metadata` key Supabase Auth's mail templates read to pick
/// German or English (`{{ .Data.mail_locale }}`, supabase/templates/). Not
/// `locale`: that is an OIDC claim a Google sign-in may copy into the metadata.
const mailLocaleKey = 'mail_locale';

/// The `data` to send with a sign-up or magic link, so the very first mail
/// is already in the app's language.
Map<String, Object?> mailLocaleData(Locale appLocale) => {
  mailLocaleKey: mailLocaleOf(appLocale),
};

/// `de` or `en` for the language the app shows; the app's fallback for
/// anything else.
String mailLocaleOf(Locale appLocale) =>
    (AppLanguage.byCode(appLocale.languageCode) ?? AppLanguage.fallback).code;

/// The locale to save for a user whose metadata is [metadata] while the
/// app shows [appLocale]; null when it is saved already.
String? mailLocaleToSave(Map<String, dynamic>? metadata, Locale appLocale) {
  final wanted = mailLocaleOf(appLocale);
  return metadata?[mailLocaleKey] == wanted ? null : wanted;
}

/// Keeps the signed-in user's `user_metadata.mail_locale` on the language the
/// app shows (picked under Einstellungen, else the device's), so the next
/// confirm, sign-in or reset mail is in that language.
///
/// [sync] is cheap: it asks nothing when the saved locale matches, never
/// throws, and runs one update at a time.
class MailLanguageSync(final GoTrueClient _auth) {
  Future<void>? _running;

  /// Saves [appLocale] for the signed-in user if it differs; does nothing
  /// signed out.
  Future<void> sync(Locale appLocale) async {
    // One update at a time; the next call compares again afterwards.
    for (var running = _running; running != null; running = _running) {
      await running;
    }
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    final locale = mailLocaleToSave(user.userMetadata, appLocale);
    if (locale == null) {
      return;
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      await _auth.updateUser(UserAttributes(data: {mailLocaleKey: locale}));
    } on Object catch (e) {
      // Offline or a server hiccup: the next start or resume tries again.
      debugPrint('mail language not saved: ${e.runtimeType}');
    } finally {
      _running = null;
      done.complete();
    }
  }
}
