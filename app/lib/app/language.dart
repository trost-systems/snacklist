import 'dart:async';
import 'dart:ui';

import 'package:family_groceries/app/device_cache.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The languages the app speaks. Anything else falls back to [fallback].
///
/// A new language is a value here plus its `app_<code>.arb`. [nativeName]
/// is the language's name in itself, which the language list shows in
/// every UI language, so it is not in the ARB files.
enum AppLanguage(final String code, final String nativeName) {
  de('de', 'Deutsch'),
  en('en', 'English');

  /// For a device that prefers none of [values]: a French or Polish phone
  /// reads English sooner than German.
  static const fallback = en;

  static AppLanguage? byCode(String? code) =>
      values.where((l) => l.code == code).firstOrNull;
}

/// The language picked under More's Einstellungen, or null to follow the
/// device.
class LanguageCubit(final DeviceCache _cache, super.initialState)
    extends Cubit<AppLanguage?> {
  void pick(AppLanguage? language) {
    emit(language);
    unawaited(_cache.saveLanguage(language?.code));
  }
}

/// German or English by the device's preferred languages, in order;
/// [AppLanguage.fallback] when it prefers neither.
Locale resolveLocale(List<Locale>? preferred, AppLanguage? picked) {
  if (picked != null) {
    return Locale(picked.code);
  }
  for (final locale in preferred ?? const <Locale>[]) {
    if (AppLanguage.byCode(locale.languageCode) case final language?) {
      return Locale(language.code);
    }
  }
  return Locale(AppLanguage.fallback.code);
}
