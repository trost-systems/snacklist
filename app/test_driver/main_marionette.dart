import 'dart:io';

import 'package:family_groceries/list/dictation.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

import 'marionette_material.dart';
import 'scripted_speech.dart';

/// Debug entrypoint for agents: the real app plus the Marionette binding,
/// which `.cursor/skills/verify-family-groceries` drives over the VM
/// service. Release builds use `lib/main.dart` and never reach this file;
/// marionette_flutter is a dev dependency, so `lib/` cannot import it.
///
/// `FG_DICTATION` gives the Linux build the phone's microphone: the add bar
/// shows it, and each listening session hears the next of its sentences
/// (separated by `|`; empty hears nothing), through [ScriptedSpeech].
Future<void> main() async {
  if (kReleaseMode) {
    throw StateError('main_marionette.dart is for debug and profile builds.');
  }
  if (Platform.environment['FG_DICTATION'] case final script?) {
    SpeechToTextPlatform.instance = ScriptedSpeech(script.split('|'));
    // The scripted recognizer is on the device: no audio leaves it.
    ListScreen.dictation = DeviceDictation(
      offlineCheck: (locales) async => {
        'status': 'installed',
        'locale': locales.first,
      },
    );
  }
  // A binding started outside the app's zone fails the launch instead of
  // logging an EXCEPTION block.
  BindingBase.debugZoneErrorsAreFatal = true;
  await app.bootstrap(
    () => MarionetteBinding.ensureInitialized(materialUiConfiguration),
  );
}
