import 'dart:async';

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/dictation.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// Hears whatever the test completes `finish` with.
class FakeDictation({final DictationProblem? problem}) implements Dictation {
  final finish = Completer<Dictated>();

  /// The language of each [prepare].
  final prepared = <SpokenLanguage>[];

  @override
  Future<DictationProblem?> prepare(SpokenLanguage language) async {
    prepared.add(language);
    return problem;
  }

  @override
  Future<Dictated> listen({
    required void Function(String words) onWords,
  }) async {
    final dictated = await finish.future;
    if (dictated case Heard(:final text)) {
      onWords(text);
    }
    return dictated;
  }

  @override
  Future<void> stop() async {}
}

/// Reports words as the test says them, like a recognizer's partial
/// results, and hears the last ones when `finish` completes.
class SpeakingDictation() implements Dictation {
  final finish = Completer<void>();
  void Function(String words)? say;
  var _said = '';

  @override
  Future<DictationProblem?> prepare(SpokenLanguage language) async => null;

  @override
  Future<Dictated> listen({
    required void Function(String words) onWords,
  }) async {
    say = (words) => onWords(_said = words);
    await finish.future;
    return Heard(_said);
  }

  @override
  Future<void> stop() async {}
}

/// Gets ready only when the test completes `ready`, as the recognizer
/// does while it asks for the microphone or checks the offline model.
class SlowDictation() implements Dictation {
  final ready = Completer<void>();
  var finish = Completer<Dictated>();
  var prepares = 0;
  var listens = 0;

  @override
  Future<DictationProblem?> prepare(SpokenLanguage language) async {
    prepares++;
    await ready.future;
    return null;
  }

  void Function(String words) say = (_) {};

  @override
  Future<Dictated> listen({
    required void Function(String words) onWords,
  }) async {
    listens++;
    say = onWords;
    return await finish.future;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  late FakeRepository repo;

  Future<void> pumpList(
    WidgetTester tester,
    Dictation? dictation, {
    Locale locale = const Locale('de'),
  }) async {
    // A phone: the microphone is a phone feature.
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);
    repo = FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: BlocProvider(
          create: (_) =>
              ListCubit(repo, MemoryListCache(), userId: 'peter')..start(),
          child: ShoppingList(dictation: dictation),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder addField() => find.byType(TextField);
  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(addField()).controller!.text;

  test('the microphone exists on iOS and Android apps only', () {
    for (final platform in TargetPlatform.values) {
      final mobile =
          platform == TargetPlatform.iOS || platform == TargetPlatform.android;
      expect(
        ListScreen.dictationFor(platform, web: false),
        mobile ? isA<DeviceDictation>() : isNull,
        reason: '$platform',
      );
      expect(ListScreen.dictationFor(platform, web: true), isNull);
    }
  });

  testWidgets('no microphone without a recognizer (web)', (tester) async {
    await pumpList(tester, null);
    expect(find.byTooltip('Diktieren'), findsNothing);
  });

  testWidgets('a dictated sentence becomes separate items', (tester) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pump();
    expect(find.byTooltip('Diktat beenden'), findsOneWidget);
    expect(find.text('Ich höre zu …'), findsOneWidget);

    dictation.finish.complete(Heard('Milch, 2 Gurken und Klopapier'));
    await tester.pumpAndSettle();

    expect(repo.rows.values.map((i) => (i.name, i.quantity)), [
      ('Milch', null),
      ('Gurken', '2'),
      ('Klopapier', null),
    ]);
    expect(
      find.text('Hinzugefügt: Milch, 2 Gurken, Klopapier.'),
      findsOneWidget,
    );
    expect(fieldText(tester), isEmpty);
    expect(find.byTooltip('Diktieren'), findsOneWidget);
    expect(tester.widget<TextField>(addField()).focusNode!.hasFocus, isTrue);
    expect(dictation.prepared, [SpokenLanguage.de]);
    expect(repo.spokenLanguages, [SpokenLanguage.de]);
  });

  testWidgets('in the English app the user dictates in English and the '
      'server splits English (job 256)', (tester) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation, locale: const Locale('en'));
    await tester.tap(find.byTooltip('Dictate'));
    await tester.pump();
    dictation.finish.complete(Heard('Milk, 2 cucumbers'));
    await tester.pumpAndSettle();

    expect(dictation.prepared, [SpokenLanguage.en]);
    expect(repo.spokenLanguages, [SpokenLanguage.en]);
    expect(repo.rows.values.map((i) => i.name), ['Milk', 'cucumbers']);
  });

  testWidgets('while the user speaks, the field shows the latest words', (
    tester,
  ) async {
    final dictation = SpeakingDictation();
    await pumpList(tester, dictation);
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pump();
    dictation.say!('Pizza, Orangensaft und zwei Packungen Fischstäbchen');
    await tester.pump();
    await tester.pump();

    final field = tester
        .state<EditableTextState>(
          find.descendant(of: addField(), matching: find.byType(EditableText)),
        )
        .renderEditable;
    final end = field.localToGlobal(
      field
          .getLocalRectForCaret(TextPosition(offset: fieldText(tester).length))
          .centerLeft,
    );
    expect(
      tester.getRect(addField()).contains(end),
      isTrue,
      reason: 'the last word is inside the field',
    );
  });

  testWidgets('a dictated item gets its brand and details split off, as a '
      'typed one does (job 111)', (tester) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    repo.parsed['Windeln Pampers Größe 3'] = const ParsedEntry(
      name: 'Windeln',
      brand: 'Pampers',
      properties: 'Größe 3',
    );
    await tester.tap(find.byTooltip('Diktieren'));
    dictation.finish.complete(Heard('Windeln Pampers Größe 3 und 2 Gurken'));
    await tester.pumpAndSettle();

    expect(
      repo.rows.values.map((i) => (i.name, i.brand, i.properties, i.quantity)),
      [('Windeln', 'Pampers', 'Größe 3', null), ('Gurken', null, null, '2')],
    );
    expect(
      find.text('Hinzugefügt: Windeln Pampers Größe 3, 2 Gurken.'),
      findsOneWidget,
    );
  });

  testWidgets('more than 30 dictated items: the first 30 are added and the '
      'rest is not dropped silently (job 111)', (tester) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    await tester.tap(find.byTooltip('Diktieren'));
    dictation.finish.complete(
      Heard([for (var i = 1; i <= 32; i++) 'Ding $i'].join(', ')),
    );
    await tester.pumpAndSettle();

    expect(repo.rows, hasLength(30));
    expect(
      find.textContaining(
        'Mehr als dreißig auf einmal gehen nicht; sag den Rest bitte noch '
        'einmal.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('items already on the list are named, not doubled', (
    tester,
  ) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    await tester.enterText(addField(), 'Milch');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Diktieren'));
    dictation.finish.complete(Heard('Milch und Brot'));
    await tester.pumpAndSettle();

    expect(repo.rows.values.map((i) => i.name), ['Milch', 'Brot']);
    expect(
      find.text('Hinzugefügt: Brot. Schon auf der Liste: Milch.'),
      findsOneWidget,
    );
  });

  testWidgets('a second tap while the recognizer gets ready starts no '
      'second session (job 457)', (tester) async {
    final dictation = SlowDictation();
    await pumpList(tester, dictation);
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pump();
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pump();
    dictation.ready.complete();
    await tester.pump();
    expect(dictation.prepares, 1);
    expect(dictation.listens, 1);
    expect(find.byTooltip('Diktat beenden'), findsOneWidget);

    dictation.finish.complete(Heard('Milch und Brot'));
    await tester.pumpAndSettle();
    expect(repo.rows.values.map((i) => i.name), ['Milch', 'Brot']);
    expect(find.byTooltip('Diktieren'), findsOneWidget);
  });

  testWidgets('a tap while the server splits the sentence starts the next '
      'one, and the first answer leaves its live words alone (job 457)', (
    tester,
  ) async {
    final dictation = SlowDictation()..ready.complete();
    await pumpList(tester, dictation);
    final gate = repo.spokenGate = Completer<void>();
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pump();
    dictation.say('Milch und Brot');
    dictation.finish.complete(Heard('Milch und Brot'));
    await tester.pump();
    expect(fieldText(tester), 'Milch und Brot');

    dictation.finish = Completer<Dictated>();
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pump();
    expect(find.byTooltip('Diktat beenden'), findsOneWidget);
    dictation.say('Eier');
    await tester.pump();

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(repo.rows.values.map((i) => i.name), ['Milch', 'Brot']);
    expect(fieldText(tester), 'Eier', reason: 'the live words stay');
    expect(
      tester.widget<TextField>(addField()).focusNode!.hasFocus,
      isFalse,
      reason: 'no keyboard while the next sentence is heard',
    );
    expect(find.byTooltip('Diktat beenden'), findsOneWidget);

    dictation.finish.complete(Heard('Eier'));
    await tester.pumpAndSettle();
    expect(repo.rows.values.map((i) => i.name), ['Milch', 'Brot', 'Eier']);
    expect(fieldText(tester), isEmpty);
    expect(find.byTooltip('Diktieren'), findsOneWidget);
  });

  testWidgets('when the next sentence hears nothing, the first answer '
      'still hands the field back (job 457)', (tester) async {
    final dictation = SlowDictation()..ready.complete();
    await pumpList(tester, dictation);
    final gate = repo.spokenGate = Completer<void>();
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pump();
    dictation.say('Milch und Brot');
    dictation.finish.complete(Heard('Milch und Brot'));
    await tester.pump();

    dictation.finish = Completer<Dictated>();
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pump();
    dictation.finish.complete(NothingHeard());
    await tester.pump();
    expect(find.byTooltip('Diktieren'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.rows.values.map((i) => i.name), ['Milch', 'Brot']);
    expect(fieldText(tester), isEmpty);
    expect(tester.widget<TextField>(addField()).focusNode!.hasFocus, isTrue);
  });

  testWidgets('offline, the sentence stays in the field', (tester) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    repo.online = false;
    await tester.tap(find.byTooltip('Diktieren'));
    dictation.finish.complete(Heard('Milch und Brot'));
    await tester.pumpAndSettle();

    expect(fieldText(tester), 'Milch und Brot');
    expect(find.textContaining('Keine Verbindung'), findsOneWidget);
    expect(repo.rows, isEmpty);
  });

  testWidgets('silence adds nothing', (tester) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    await tester.tap(find.byTooltip('Diktieren'));
    dictation.finish.complete(NothingHeard());
    await tester.pumpAndSettle();

    expect(find.text('Ich habe nichts gehört.'), findsOneWidget);
    expect(repo.rows, isEmpty);
  });

  testWidgets('a refused microphone explains where to allow it', (
    tester,
  ) async {
    await pumpList(
      tester,
      FakeDictation(problem: DictationProblem.unavailable),
    );
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mikrofon'), findsOneWidget);
    expect(find.byTooltip('Diktieren'), findsOneWidget);
  });

  // Each app language names its own offline speech recognition.
  for (final (locale, dictate, listening, missing, downloading) in [
    (
      const Locale('de'),
      'Diktieren',
      'Ich höre zu …',
      'Dafür fehlt hier die deutsche Offline-Spracherkennung.',
      'Snacklist hat Android gebeten, die deutsche Offline-Spracherkennung '
          'herunterzuladen.',
    ),
    (
      const Locale('en'),
      'Dictate',
      'Listening…',
      'This device is missing English offline speech recognition.',
      'Snacklist asked Android to download English offline speech '
          'recognition.',
    ),
  ]) {
    for (final (problem, says) in [
      (DictationProblem.noOfflineSpeech, missing),
      (DictationProblem.offlineSpeechDownloading, downloading),
    ]) {
      testWidgets('${problem.name} in the ${locale.languageCode} app: the '
          'microphone says why and stays off', (tester) async {
        await pumpList(tester, FakeDictation(problem: problem), locale: locale);
        await tester.tap(find.byTooltip(dictate));
        await tester.pumpAndSettle();

        expect(find.textContaining(says), findsOne);
        expect(find.text(listening), findsNothing);
        expect(find.byTooltip(dictate), findsOneWidget);
      });
    }

    testWidgets('a recognizer that finds no ${locale.languageCode} model '
        'mid-way says why', (tester) async {
      final dictation = FakeDictation();
      await pumpList(tester, dictation, locale: locale);
      await tester.tap(find.byTooltip(dictate));
      dictation.finish.complete(Refused(DictationProblem.noOfflineSpeech));
      await tester.pumpAndSettle();

      expect(find.textContaining(missing), findsOne);
      expect(repo.rows, isEmpty);
    });
  }
}
