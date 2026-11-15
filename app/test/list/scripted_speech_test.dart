import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/list/dictation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

import '../../test_driver/scripted_speech.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SpeechToTextPlatform before;
  setUp(() => before = SpeechToTextPlatform.instance);
  tearDown(() => SpeechToTextPlatform.instance = before);

  DeviceDictation dictation(List<String> sentences) {
    SpeechToTextPlatform.instance = ScriptedSpeech(sentences);
    return DeviceDictation(
      speech: SpeechToText.withMethodChannel(),
      offlineCheck: (locales) async => {
        'status': 'installed',
        'locale': locales.first,
      },
    );
  }

  test('the app hears the sentence word by word, then hears all of it '
      'after the pause', () {
    fakeAsync((async) {
      final mic = dictation(['Milch, Eier und zwei Gurken']);
      final words = <String>[];
      Dictated? dictated;
      unawaited(
        mic.prepare(SpokenLanguage.de).then((problem) async {
          expect(problem, isNull);
          dictated = await mic.listen(onWords: words.add);
        }),
      );
      async.elapse(const Duration(seconds: 3));
      expect(words.last, 'Milch, Eier und zwei Gurken');
      expect(words.first, 'Milch,');
      expect(dictated, isNull, reason: 'still listening during the pause');
      async.elapse(const Duration(seconds: 6));
      expect(dictated, isA<Heard>());
      expect((dictated! as Heard).text, 'Milch, Eier und zwei Gurken');
    });
  });

  test('a session past the script hears nothing', () {
    fakeAsync((async) {
      final mic = dictation(['Milch']);
      final results = <Dictated>[];
      Future<void> session() async {
        await mic.prepare(SpokenLanguage.de);
        results.add(await mic.listen(onWords: (_) {}));
      }

      unawaited(session().then((_) => session()));
      async.elapse(const Duration(seconds: 20));
      expect(results, [isA<Heard>(), isA<NothingHeard>()]);
    });
  });
}
