import 'dart:async';
import 'dart:ui' show Locale;

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/list/dictation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// The native side of speech_to_text: records what the app asked for.
class _Recognizer() extends SpeechToTextPlatform {
  final listened = <SpeechListenOptions?>[];

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async => true;

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    listened.add(options);
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  void says(String words) => onTextRecognition!(
    '{"alternates":[{"recognizedWords":"$words","confidence":0.9}],'
    '"resultType":${ResultType.finalResult.value}}',
  );

  void fails(String error) =>
      onError!('{"errorMsg":"$error","permanent":true}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Recognizer recognizer;
  late List<Object?> asked;

  /// The native check answers [answer] and records the locales it got.
  void offlineSpeech(Object? answer) => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(DeviceDictation.offlineSpeech, (call) async {
        if (call.method != 'offlineSpeech') {
          throw MissingPluginException();
        }
        asked.add((call.arguments as Map<Object?, Object?>)['locales']);
        return answer;
      });

  const installedDe = {'status': 'installed', 'locale': 'de_DE'};

  DeviceDictation onDevice(List<Locale> deviceLocales) => DeviceDictation(
    speech: SpeechToText.withMethodChannel(),
    deviceLocales: () => deviceLocales,
  );

  late DeviceDictation dictation;

  setUp(() {
    asked = [];
    recognizer = _Recognizer();
    SpeechToTextPlatform.instance = recognizer;
    dictation = onDevice(const [Locale('de', 'DE')]);
  });

  Future<SpeechListenOptions> listened(DeviceDictation dictation) async {
    final dictated = dictation.listen(onWords: (_) {});
    await pumpEventQueue();
    recognizer.says('Milch und Brot');
    expect(
      await dictated,
      isA<Heard>().having((h) => h.text, 'text', 'Milch und Brot'),
    );
    return recognizer.listened.single!;
  }

  test('a German app listens in German on the device only', () async {
    offlineSpeech(installedDe);
    expect(await dictation.prepare(SpokenLanguage.de), isNull);
    expect(asked, [
      ['de_DE'],
    ]);

    final options = await listened(dictation);
    expect(options.onDevice, isTrue);
    expect(options.localeId, 'de_DE');
  });

  test('a German app on an English device still listens in German', () async {
    offlineSpeech(installedDe);
    final dictation = onDevice(const [Locale('en', 'GB')]);
    expect(await dictation.prepare(SpokenLanguage.de), isNull);
    expect(asked, [
      ['de_DE'],
    ]);
    expect((await listened(dictation)).localeId, 'de_DE');
  });

  test("an English app asks for the device's English first and listens in "
      'the locale the check found', () async {
    offlineSpeech({'status': 'installed', 'locale': 'en-GB'});
    final dictation = onDevice(const [
      Locale('de', 'DE'),
      Locale('en', 'GB'),
      Locale('en'),
      Locale('en', 'US'),
    ]);
    expect(await dictation.prepare(SpokenLanguage.en), isNull);
    expect(asked, [
      ['en_GB', 'en_US'],
    ]);

    final options = await listened(dictation);
    expect(options.onDevice, isTrue);
    expect(options.localeId, 'en-GB');
  });

  test('an English app on a device without English asks for en_US', () async {
    offlineSpeech({'status': 'installed', 'locale': 'en_US'});
    final dictation = onDevice(const [Locale('de', 'AT')]);
    expect(await dictation.prepare(SpokenLanguage.en), isNull);
    expect(asked, [
      ['en_US'],
    ]);
    expect((await listened(dictation)).localeId, 'en_US');
  });

  test('a language Android is downloading says so and never listens', () async {
    offlineSpeech({'status': 'downloading'});
    expect(
      await dictation.prepare(SpokenLanguage.de),
      DictationProblem.offlineSpeechDownloading,
    );
    expect(recognizer.listened, isEmpty);
  });

  for (final (name, answer) in <(String, Object?)>[
    ('missing', {'status': 'missing'}),
    ('null', null),
    ('installed without a locale', {'status': 'installed'}),
    ('the old yes', true),
  ]) {
    test('a check answering $name is no offline speech', () async {
      offlineSpeech(answer);
      expect(
        await dictation.prepare(SpokenLanguage.en),
        DictationProblem.noOfflineSpeech,
      );
      expect(recognizer.listened, isEmpty);
    });
  }

  test('a platform without the check counts as no offline speech', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DeviceDictation.offlineSpeech, null);
    expect(
      await dictation.prepare(SpokenLanguage.de),
      DictationProblem.noOfflineSpeech,
    );
  });

  test('a check that throws counts as no offline speech', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          DeviceDictation.offlineSpeech,
          (call) async => throw PlatformException(code: 'boom'),
        );
    expect(
      await dictation.prepare(SpokenLanguage.de),
      DictationProblem.noOfflineSpeech,
    );
  });

  test('a check that never answers counts as no offline speech', () {
    fakeAsync((async) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            DeviceDictation.offlineSpeech,
            (call) => Completer<Object?>().future,
          );
      DictationProblem? problem;
      unawaited(dictation.prepare(SpokenLanguage.de).then((p) => problem = p));
      async.elapse(const Duration(seconds: 6));
      expect(problem, DictationProblem.noOfflineSpeech);
      expect(recognizer.listened, isEmpty);
    });
  });

  for (final error in [
    'error_language_not_supported',
    'error_language_unavailable',
  ]) {
    test(
      'the on-device recognizer reporting $error is no offline speech',
      () async {
        offlineSpeech(installedDe);
        await dictation.prepare(SpokenLanguage.de);
        final dictated = dictation.listen(onWords: (_) {});
        await pumpEventQueue();
        recognizer.fails(error);

        expect(
          await dictated,
          isA<Refused>().having(
            (r) => r.problem,
            'problem',
            DictationProblem.noOfflineSpeech,
          ),
        );
      },
    );
  }

  test('other recognizer errors end with nothing heard', () async {
    offlineSpeech(installedDe);
    await dictation.prepare(SpokenLanguage.de);
    final dictated = dictation.listen(onWords: (_) {});
    await pumpEventQueue();
    recognizer.fails('error_no_match');

    expect(await dictated, isA<NothingHeard>());
  });
}
