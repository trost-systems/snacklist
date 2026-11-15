import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// The language the user dictates in: the app's, so German speakers get
/// German recognition and the server's German splitter, English speakers
/// English ones. [code] is the voice function's `lang`, [fallbackLocale] the
/// recognizer locale when the device names no regional variant.
enum SpokenLanguage(final String code, final String fallbackLocale) {
  de('de', 'de_DE'),
  en('en', 'en_US');

  /// English for an English app, German for everything else.
  static SpokenLanguage of(Locale appLocale) =>
      appLocale.languageCode == 'en' ? en : de;

  /// The recognizer locales to try, best first: an English user's own
  /// variants from the device's languages (en_GB before en_US), German as
  /// de_DE.
  List<String> candidates(List<Locale> deviceLocales) => switch (this) {
    de => [fallbackLocale],
    en => {
      for (final locale in deviceLocales)
        if (locale.languageCode == code &&
            (locale.countryCode ?? '').isNotEmpty)
          '${code}_${locale.countryCode}',
      fallbackLocale,
    }.toList(),
  };
}

/// Why the microphone can't take a sentence.
enum DictationProblem() {
  /// No recognizer, or the user refused the microphone or speech recognition.
  unavailable,

  /// The device can't recognize the app's language without sending the audio
  /// to a server, and spoken words stay on the device (spec).
  noOfflineSpeech,

  /// Android was asked to download the language for on-device recognition,
  /// or is downloading it already.
  offlineSpeechDownloading,
}

/// What came of one listening session.
sealed class Dictated();

final class Heard(final String text) extends Dictated;

final class NothingHeard() extends Dictated;

final class Refused(final DictationProblem problem) extends Dictated;

/// Speech to text for the add field.
abstract interface class Dictation() {
  /// Null when [listen] can start in [language], otherwise why it can't.
  Future<DictationProblem?> prepare(SpokenLanguage language);

  /// Listens until the speaker pauses, reporting the words heard so far.
  Future<Dictated> listen({required void Function(String words) onWords});

  /// Ends listening early; [listen] completes with what was heard.
  Future<void> stop();
}

/// The platform recognizer (Siri's on iOS, Google's on Android), in the
/// language [prepare] was given and on the device only.
class DeviceDictation({
  SpeechToText? speech,

  /// Replaces the native offline-speech check, for the Linux capture
  /// entrypoint (`test_driver/main_marionette.dart`), which has none. Gets
  /// the candidate locale ids and answers as the channel does.
  Future<Object?> Function(List<String> locales)? offlineCheck,

  /// The device's preferred languages, which pick the English variant.
  List<Locale> Function()? deviceLocales,
}) implements Dictation {
  /// The app's own check (MainActivity.kt, AppDelegate.swift): with
  /// `onDevice` speech_to_text 7.5 falls back to the network recognizer on
  /// Android and can't tell whether a language is installed.
  static const offlineSpeech = MethodChannel('familygroceries/speech');

  /// The on-device recognizer's answer on Android when the language isn't
  /// installed (SpeechRecognizer.ERROR_LANGUAGE_*).
  static const _noLanguage = {
    'error_language_not_supported',
    'error_language_unavailable',
  };

  final SpeechToText _speech = speech ?? SpeechToText();
  final Future<Object?> Function(List<String> locales) _offlineCheck =
      offlineCheck ??
      ((locales) => offlineSpeech.invokeMethod<Object?>('offlineSpeech', {
        'locales': locales,
      }));
  final List<Locale> Function() _deviceLocales =
      deviceLocales ??
      (() => ServicesBinding.instance.platformDispatcher.locales);
  Completer<Dictated>? _done;
  var _heard = '';
  DictationProblem? _problem;
  var _localeId = SpokenLanguage.de.fallbackLocale;

  void _finish() {
    final done = _done;
    if (done != null && !done.isCompleted) {
      done.complete(switch (_problem) {
        final problem? => Refused(problem),
        null when _heard.trim().isEmpty => NothingHeard(),
        null => Heard(_heard),
      });
    }
  }

  @override
  Future<DictationProblem?> prepare(SpokenLanguage language) async {
    final ready =
        _speech.isAvailable ||
        await _speech.initialize(
          onStatus: (status) {
            if (status == SpeechToText.doneStatus ||
                status == SpeechToText.notListeningStatus) {
              _finish();
            }
          },
          onError: (error) {
            if (_noLanguage.contains(error.errorMsg)) {
              _problem = DictationProblem.noOfflineSpeech;
            }
            _finish();
          },
        );
    if (!ready) {
      return DictationProblem.unavailable;
    }
    final Object? answer;
    try {
      // A recognizer service that never answers counts as no.
      answer = await _offlineCheck(language.candidates(_deviceLocales()))
          .timeout(const Duration(seconds: 5));
    } on Exception {
      return DictationProblem.noOfflineSpeech;
    }
    switch (answer) {
      case {'status': 'installed', 'locale': final String locale}:
        _localeId = locale;
        return null;
      case {'status': 'downloading'}:
        return DictationProblem.offlineSpeechDownloading;
      default:
        return DictationProblem.noOfflineSpeech;
    }
  }

  @override
  Future<Dictated> listen({
    required void Function(String words) onWords,
  }) async {
    _heard = '';
    _problem = null;
    final done = _done = Completer<Dictated>();
    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          onDevice: true,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          listenMode: ListenMode.dictation,
          cancelOnError: true,
        ),
        onResult: (result) {
          _heard = result.recognizedWords;
          onWords(_heard);
          if (result.finalResult) {
            _finish();
          }
        },
      );
    } on ListenFailedException {
      _problem = DictationProblem.unavailable;
      _finish();
    }
    return await done.future;
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
    _finish();
  }
}
