import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_cubit.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../analytics/fakes.dart';
import 'fakes.dart';

void main() {
  late FakeFeedbackRepository repo;
  late NativePostHog sink;
  late Analytics analytics;
  late FeedbackCubit cubit;
  var ids = 0;

  Future<void> start({bool? consent = true}) async {
    repo = FakeFeedbackRepository();
    sink = NativePostHog()..install();
    analytics = await loadedAnalytics(MemoryAnalyticsStore());
    if (consent != null) {
      await analytics.decide(granted: consent);
    }
    analytics.setUser(customer);
    await analytics.flush();
    sink.calls.clear();
    cubit = FeedbackCubit(
      repo,
      analytics: analytics,
      newId: () => 'id-${++ids}',
    )..open(userId: 'max');
  }

  tearDown(() async {
    await cubit.close();
    await analytics.close();
  });

  Future<List<Map<String, Object?>>> sent() async {
    await analytics.flush();
    return [
      for (final e in sink.events)
        if (e['event'] == 'feedback_submitted') e,
    ];
  }

  test(
    'a note with only text: one row, no category, no contact (AC2)',
    () async {
      await start();
      cubit.edit('  Der Haken reagiert spät.  ');
      expect(await cubit.send(sampleContext), isTrue);
      expect(repo.rows, hasLength(1));
      final row = repo.rows.values.single;
      expect(row.message, 'Der Haken reagiert spät.');
      expect(row.category, isNull);
      expect(row.contactOk, isFalse);
      expect(row.context, sampleContext);
      expect(cubit.state.status, FeedbackStatus.sent);
    },
  );

  test('a double tap sends once', () async {
    await start();
    cubit.edit('Doppelt');
    repo.hold = Completer();
    final first = cubit.send(sampleContext);
    final second = cubit.send(sampleContext);
    repo.hold!.complete();
    expect(await (first, second).wait, (true, false));
    expect(repo.calls, hasLength(1));
    expect(await sent(), hasLength(1));
    expect(await cubit.send(sampleContext), isFalse, reason: 'already sent');
  });

  test('empty, blank or too long is not sent (AC4)', () async {
    await start();
    for (final text in ['', '   ', '\n\t ', ' 　']) {
      cubit.edit(text);
      expect(cubit.state.canSend, isFalse, reason: text);
      expect(await cubit.send(sampleContext), isFalse);
    }
    cubit.edit('a' * 2001);
    expect(cubit.state.tooLong, isTrue);
    expect(await cubit.send(sampleContext), isFalse);
    cubit.edit('  ${'a' * 2000}  ');
    expect(cubit.state.canSend, isTrue, reason: 'blanks around do not count');
    cubit.edit('🛒' * 2000);
    expect(cubit.state.length, 2000, reason: 'characters, not UTF-16 units');
    expect(cubit.state.canSend, isTrue);
    cubit.edit('🛒' * 2001);
    expect(cubit.state.canSend, isFalse);
    expect(repo.calls, isEmpty);
  });

  test('offline: the note stays, Retry sends it once (AC7)', () async {
    await start();
    cubit
      ..edit('Offline geschrieben')
      ..pick(FeedbackCategory.bug)
      ..setContact(ok: true);
    repo.failNext = 1;
    expect(await cubit.send(sampleContext), isFalse);
    expect(cubit.state.status, FeedbackStatus.failed);
    expect(cubit.state.message, 'Offline geschrieben');
    expect(cubit.state.category, FeedbackCategory.bug);
    expect(cubit.state.contactOk, isTrue);
    expect(repo.rows, isEmpty);
    expect(await sent(), isEmpty, reason: 'no event before the server has it');
    expect(await cubit.send(sampleContext), isTrue);
    expect(repo.rows, hasLength(1));
    expect(repo.calls.map((c) => c.id).toSet(), hasLength(1));
    expect(await sent(), hasLength(1));
  });

  test('a lost answer: Retry with the same id, one row, one event', () async {
    await start();
    cubit.edit('Angekommen, Antwort verloren');
    repo.landThenFail = 1;
    expect(await cubit.send(sampleContext), isFalse);
    expect(repo.rows, hasLength(1), reason: 'the server has it already');
    expect(await sent(), isEmpty);
    expect(await cubit.send(sampleContext), isTrue);
    expect(repo.calls.map((c) => c.id).toSet(), hasLength(1));
    expect(repo.rows, hasLength(1));
    expect(await sent(), hasLength(1));
  });

  test('closing the form keeps the note and its id', () async {
    await start();
    cubit.edit('Halb fertig');
    repo.failNext = 1;
    await cubit.send(sampleContext);
    final id = cubit.id;
    cubit.open(userId: 'max');
    expect(cubit.state.message, 'Halb fertig');
    expect(cubit.id, id);
  });

  test('a change after a failure is a new note with a new id', () async {
    await start();
    cubit.edit('Erster Text');
    repo.failNext = 1;
    await cubit.send(sampleContext);
    final first = cubit.id;
    cubit.edit('Erster Text, korrigiert');
    expect(cubit.id, isNot(first));
    expect(cubit.state.status, FeedbackStatus.editing);
  });

  test('someone else has the id: a new one, then it goes through', () async {
    await start();
    cubit.edit('Kollision');
    repo
      ..failNext = 1
      ..error = const FeedbackIdTaken();
    final first = cubit.id;
    expect(await cubit.send(sampleContext), isFalse);
    expect(cubit.id, isNot(first));
    expect(await cubit.send(sampleContext), isTrue);
  });

  test('after a send, or for another account, the form starts blank', () async {
    await start();
    cubit.edit('Gesendet');
    await cubit.send(sampleContext);
    final sentId = cubit.id;
    cubit.open(userId: 'max');
    expect(cubit.state.message, isEmpty);
    expect(cubit.id, isNot(sentId));
    cubit
      ..edit('Entwurf von Max')
      ..open(userId: 'barbie');
    expect(cubit.state.message, isEmpty);
  });

  test('the event: category, entry point, screen, contact, never the text '
      '(AC8)', () async {
    await start();
    cubit
      ..edit('Geheimer Text über Hafermilch')
      ..pick(FeedbackCategory.idea)
      ..setContact(ok: true);
    await cubit.send(sampleContext);
    final events = await sent();
    expect(events, hasLength(1));
    final properties = events.single['properties']! as Map<String, Object?>;
    expect(properties['category'], 'idea');
    expect(properties['entry_point'], 'settings');
    expect(properties, isNot(contains('screen')));
    expect(properties['contact_ok'], true);
    expect(
      '${events.single}',
      allOf(isNot(contains('Geheimer')), isNot(contains('Hafermilch'))),
    );
  });

  test('a shake note: entry point shake and its screen in the event', () async {
    await start();
    cubit.edit('Wackel');
    await cubit.send(
      const FeedbackContext(
        appVersion: '1.2.3',
        build: '45',
        platform: 'android',
        osVersion: 'Android 14 (SDK 34)',
        locale: 'de',
        entryPoint: FeedbackEntryPoint.shake,
        screen: 'list',
        isInternal: false,
      ),
    );
    final properties =
        (await sent()).single['properties']! as Map<String, Object?>;
    expect(properties['entry_point'], 'shake');
    expect(properties['screen'], 'list');
  });

  test('no category is "none"; a picked one can be unpicked', () async {
    await start();
    cubit
      ..edit('x')
      ..pick(FeedbackCategory.bug)
      ..pick(FeedbackCategory.bug);
    expect(cubit.state.category, isNull);
    await cubit.send(sampleContext);
    final properties =
        (await sent()).single['properties']! as Map<String, Object?>;
    expect(properties['category'], 'none');
  });

  test('declined consent: no event, the note is still saved', () async {
    await start(consent: false);
    cubit.edit('Ohne Analyse');
    expect(await cubit.send(sampleContext), isTrue);
    expect(repo.rows, hasLength(1));
    await analytics.flush();
    expect(sink.events, isEmpty);
  });

  test('no consent asked yet: no event either', () async {
    await start(consent: null);
    cubit.edit('Noch nicht gefragt');
    expect(await cubit.send(sampleContext), isTrue);
    await analytics.flush();
    expect(sink.events, isEmpty);
  });
}
