import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/rendering.dart' show SemanticsData;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/link.dart';

import '../more/more_harness.dart';
import 'fakes.dart';
import 'fb2_harness.dart' show key, tapKey;
import 'fb4_harness.dart';

String location(More more) =>
    more.router.routerDelegate.currentConfiguration.uri.toString();

Future<void> scrollTo(WidgetTester tester, String k) async {
  await tester.scrollUntilVisible(
    key(k),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

/// Nothing on screen or read to a screen reader names a person.
void expectNoPeter(WidgetTester tester) {
  expect(find.textContaining('Peter'), findsNothing);
  expect(find.bySemanticsLabel(RegExp('Peter')), findsNothing);
}

void main() {
  setUpAll(fakeSupabase);

  group('flag off', () {
    testWidgets("More's row is Feedback senden and opens the form, as "
        'before; the hub routes lead back to More', (tester) async {
      final server = fb4Server();
      final more = await pumpMore(tester, feedback: server);
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final row = find.descendant(
        of: key('more-feedback'),
        matching: find.byType(Text),
      );
      expect(tester.widget<Text>(row).data, 'Feedback senden');
      expect(
        find.descendant(
          of: key('more-feedback'),
          matching: find.byIcon(Icons.feedback_outlined),
        ),
        findsOneWidget,
      );
      expect(key('more-feedback-badge'), findsNothing);
      expect(server.reads, 0, reason: 'nothing is read with the flag off');
      await tapKey(tester, 'more-feedback');
      expect(key('feedback-sheet'), findsOneWidget);
      expect(location(more), morePath);

      more.router.go(feedbackPath);
      await tester.pumpAndSettle();
      expect(location(more), morePath);
      more.router.go(feedbackNotePath('n-fixed'));
      await tester.pumpAndSettle();
      expect(location(more), morePath);
      expect(key('feedback-hub'), findsNothing);
    });
  });

  testWidgets('a flag that arrives after More is shown turns the row into '
      'the hub and loads its badge', (tester) async {
    final server = fb4Server();
    await pumpMore(tester, feedback: server);
    expect(server.reads, 0);
    tester.element(find.byType(MoreScreen)).read<Flags>().replace({
      feedbackFb4Flag: true,
    });
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      key('more-feedback-badge'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Feedback & Ideen'), findsOneWidget);
    expect(server.reads, greaterThan(0));
  });

  group('flag on', () {
    testWidgets('the row is Feedback & Ideen with a badge of unopened '
        'answers, named for screen readers; it opens the hub', (tester) async {
      final semantics = tester.ensureSemantics();
      final more = await pumpMore(tester, flags: fb4, feedback: fb4Server());
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: key('more-feedback'),
          matching: find.text('Feedback & Ideen'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('more-feedback'),
          matching: find.byIcon(Icons.forum_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('more-feedback-badge'),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Feedback & Ideen, 2 Neuigkeiten'),
        findsOneWidget,
      );
      await tapKey(tester, 'more-feedback');
      expect(location(more), feedbackPath);
      expect(key('feedback-hub'), findsOneWidget);
      expect(find.text('Feedback & Ideen'), findsOneWidget, reason: 'title');
      semantics.dispose();
    });

    testWidgets('no badge without unopened answers', (tester) async {
      await pumpMore(
        tester,
        flags: fb4,
        feedback: FakeFeedbackRepository()
          ..serverNotes.addAll([plannedNote, sentNote]),
      );
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(key('more-feedback-badge'), findsNothing);
    });

    testWidgets('the hub lists the notes newest first with their status, '
        'marks unopened answers, and lists the ideas', (tester) async {
      await pumpMore(
        tester,
        location: feedbackPath,
        flags: fb4,
        feedback: fb4Server(),
      );
      expect(find.text('An Snacklist Support schreiben'), findsOneWidget);
      expect(find.text('DEINE NOTIZEN'), findsOneWidget);
      String statusOf(String id) => tester
          .widget<Text>(
            find.descendant(
              of: find.descendant(
                of: key('feedback-note-$id'),
                matching: key('feedback-status'),
              ),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(statusOf('n-fixed'), 'Behoben in 1.4.1');
      expect(statusOf('n-read'), 'Gelesen');
      expect(statusOf('n-planned'), 'Geplant');
      expect(statusOf('n-sent'), 'Gesendet');
      expect(statusOf('n-fixed-plain'), 'Behoben');
      final ids = [
        for (final card
            in find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith(
                        'feedback-note-n-',
                      ),
                )
                .evaluate())
          (card.widget.key! as ValueKey<String>).value,
      ];
      expect(ids, [
        'feedback-note-n-fixed',
        'feedback-note-n-read',
        'feedback-note-n-planned',
        'feedback-note-n-sent',
        'feedback-note-n-fixed-plain',
      ]);
      expect(
        find.descendant(
          of: key('feedback-note-n-fixed'),
          matching: find.text('Neue Antwort'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('feedback-note-n-read'),
          matching: find.text('Neuer Status'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('feedback-note-new')), findsNWidgets(2));
      final message = tester.widget<Text>(
        find.text('Hafermilch landet unter Vorrat statt im Kühlregal.'),
      );
      expect(message.maxLines, 3);

      await scrollTo(tester, 'feedback-ideas-note');
      expect(find.text('IDEEN, DIE WIR ABWÄGEN'), findsOneWidget);
      expect(find.text('Liste in der Reihenfolge der Gänge'), findsOneWidget);
      expect(find.text('Wochenplan für Essen'), findsOneWidget);
      expect(find.text('Wird überlegt'), findsOneWidget);
      expect(
        find.text(
          'Ideen schreibt Snacklist Support. Andere sehen nur die Zahl, nie '
          'wer abgestimmt hat.',
        ),
        findsOneWidget,
      );
      expectNoPeter(tester);
    });

    testWidgets('in English: ideas by their English title', (tester) async {
      await pumpMore(
        tester,
        location: feedbackPath,
        flags: fb4,
        language: AppLanguage.en,
        feedback: fb4Server(),
      );
      expect(find.text('Write to Snacklist Support'), findsOneWidget);
      expect(find.text('Fixed in 1.4.1'), findsOneWidget);
      expect(find.text('New reply'), findsOneWidget);
      await scrollTo(tester, 'feedback-ideas-note');
      expect(find.text('Weekly meal plan'), findsOneWidget);
      expect(find.text('Being considered'), findsOneWidget);
      expect(find.text('Liste in der Reihenfolge der Gänge'), findsNothing);
      expectNoPeter(tester);
    });

    testWidgets('no notes: the empty text; no ideas: no ideas section', (
      tester,
    ) async {
      await pumpMore(tester, location: feedbackPath, flags: fb4);
      expect(key('feedback-no-notes'), findsOneWidget);
      expect(find.text('IDEEN, DIE WIR ABWÄGEN'), findsNothing);
      expect(key('feedback-ideas-note'), findsNothing);
    });

    testWidgets('a failed load offers a retry instead of the list', (
      tester,
    ) async {
      // The hub's load: its notes and its ideas.
      final server = fb4Server()..failReads = 2;
      await pumpMore(
        tester,
        location: feedbackPath,
        flags: fb4,
        feedback: server,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Konnte nicht geladen werden.'), findsOneWidget);
      expect(key('feedback-note-n-fixed'), findsNothing);
      await tapKey(tester, 'feedback-retry-load');
      expect(key('feedback-failed'), findsNothing);
      expect(key('feedback-note-n-fixed'), findsOneWidget);
    });

    testWidgets('writing from the hub opens the form; once sent the note '
        'is on top as Gesendet', (tester) async {
      final server = fb4Server();
      await pumpMore(
        tester,
        location: feedbackPath,
        flags: fb4,
        feedback: server,
      );
      await tapKey(tester, 'feedback-write');
      expect(key('feedback-sheet'), findsOneWidget);
      expect(find.text('Deine Nachricht'), findsOneWidget);
      expectNoPeter(tester);
      await tester.enterText(key('feedback-message'), 'Mehr Platz für Notizen');
      await tester.pump();
      await tapKey(tester, 'feedback-send');
      expect(key('feedback-sheet'), findsNothing);
      final sent = server.rows.values.single;
      final card = key('feedback-note-${sent.id}');
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Gesendet')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('Mehr Platz für Notizen'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(card).dy,
        lessThan(tester.getTopLeft(key('feedback-note-n-fixed')).dy),
      );
    });

    testWidgets('a note with a reply: Snacklist Support answers, Behoben in '
        'links to its changelog, opening marks it seen and the badge drops', (
      tester,
    ) async {
      final server = fb4Server();
      final more = await pumpMore(tester, flags: fb4, feedback: server);
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: key('more-feedback-badge'),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'more-feedback');
      await tapKey(tester, 'feedback-note-n-fixed');
      expect(location(more), '/more/feedback/n-fixed');
      expect(find.text('Deine Notiz'), findsOneWidget, reason: 'title');
      expect(
        find.descendant(
          of: key('feedback-status'),
          matching: find.text('Behoben in 1.4.1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('feedback-note-message'),
          matching: find.text(fixedNote.message),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('feedback-note-message'),
          matching: find.textContaining('· gelesen'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('feedback-note-reply'),
          matching: find.text(fixedNote.reply!),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('feedback-note-reply'),
          matching: find.textContaining('Snacklist Support · '),
        ),
        findsOneWidget,
      );
      expect(find.text('Was ist neu in 1.4.1'), findsOneWidget);
      final link = tester.widget<Link>(
        find.descendant(
          of: key('feedback-whats-new'),
          matching: find.byType(Link),
        ),
      );
      expect(link.uri.toString(), 'https://snacklist.app/de/changelog#v1-4-1');
      expect(
        tester
            .getSize(
              find.descendant(
                of: key('feedback-whats-new'),
                matching: find.byType(TextButton),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(server.seen, ['n-fixed']);
      expectNoPeter(tester);

      more.router.go(morePath);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: key('more-feedback-badge'),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a sent note shows no read mark and no reply; opening a '
        'read note marks nothing', (tester) async {
      final server = fb4Server();
      final more = await pumpMore(
        tester,
        location: feedbackNotePath('n-sent'),
        flags: fb4,
        feedback: server,
      );
      expect(
        find.descendant(
          of: key('feedback-note-message'),
          matching: find.textContaining('gelesen'),
        ),
        findsNothing,
      );
      expect(key('feedback-note-reply'), findsNothing);
      expect(key('feedback-whats-new'), findsNothing);
      more.router.go(feedbackNotePath('n-planned'));
      await tester.pumpAndSettle();
      expect(key('feedback-whats-new'), findsNothing);
      expect(server.seen, isEmpty);
    });

    testWidgets('an id that is not among the notes says so', (tester) async {
      await pumpMore(
        tester,
        location: feedbackNotePath('n-unknown'),
        flags: fb4,
        feedback: fb4Server(),
      );
      expect(find.text('Diese Notiz gibt es nicht.'), findsOneWidget);
    });

    testWidgets('+1 counts at once for the household, toggles back, and a '
        'refused +1 is undone with a notice', (tester) async {
      final semantics = tester.ensureSemantics();
      final server = fb4Server();
      await pumpMore(
        tester,
        location: feedbackPath,
        flags: fb4,
        feedback: server,
      );
      await scrollTo(tester, 'feedback-ideas-note');
      final vote = key('feedback-vote-i-meal');
      SemanticsData data() => tester.getSemantics(vote).getSemanticsData();
      expect(data().label, 'Wochenplan für Essen: +1, 9 Stimmen');
      expect(data().flagsCollection.isToggled, Tristate.isFalse);
      expect(tester.getSize(vote).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(vote).width, greaterThanOrEqualTo(48));

      server.holdVote = Completer();
      await tester.tap(vote);
      await tester.pump();
      expect(
        find.descendant(of: vote, matching: find.text('10')),
        findsOneWidget,
        reason: 'shown before the server answers',
      );
      server.holdVote!.complete();
      server.holdVote = null;
      await tester.pumpAndSettle();
      expect(data().label, 'Wochenplan für Essen: +1, 10 Stimmen');
      expect(data().flagsCollection.isToggled, Tristate.isTrue);
      expect(server.votes.single, (
        idea: 'i-meal',
        household: 'home',
        on: true,
      ));

      await tester.tap(vote);
      await tester.pumpAndSettle();
      expect(data().label, 'Wochenplan für Essen: +1, 9 Stimmen');
      expect(server.votes.last.on, isFalse);

      server.failVotes = 1;
      await tester.tap(vote);
      await tester.pump();
      await tester.pump();
      expect(data().label, 'Wochenplan für Essen: +1, 9 Stimmen');
      expect(data().flagsCollection.isToggled, Tristate.isFalse);
      expect(key('feedback-vote-failed'), findsOneWidget);
      expect(
        find.text('Deine Stimme ist nicht angekommen. Versuch es noch einmal.'),
        findsWidgets,
      );
      semantics.dispose();
    });

    testWidgets('a household switch with the hub open shows and votes for '
        'the new household', (tester) async {
      final sessions = StreamController<Session>();
      addTearDown(sessions.close);
      final server = fb4Server()
        ..serverIdeas = [mealIdea.withVote(voted: true, votes: 10)];
      await pumpMore(
        tester,
        location: feedbackPath,
        flags: fb4,
        feedback: server,
        sessions: sessions.stream,
      );
      await scrollTo(tester, 'feedback-ideas-note');
      final vote = key('feedback-vote-i-meal');
      expect(find.descendant(of: vote, matching: find.text('10')), findsOne);

      server.serverIdeas = [mealIdea];
      const work = Household(id: 'work', name: 'Büro');
      sessions.add(
        const InHousehold('peter', work, [
          Household(id: 'home', name: 'Zuhause'),
          work,
        ]),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: vote, matching: find.text('9')),
        findsOne,
        reason: "the new household's count, not the old one's",
      );
      await tester.tap(vote);
      await tester.pumpAndSettle();
      expect(server.votes.single, (
        idea: 'i-meal',
        household: 'work',
        on: true,
      ));
    });

    testWidgets("More's badge reads again when the app comes back", (
      tester,
    ) async {
      final server = FakeFeedbackRepository()..serverNotes.add(sentNote);
      await pumpMore(tester, flags: fb4, feedback: server);
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(key('more-feedback-badge'), findsNothing);

      server.serverNotes
        ..clear()
        ..add(readNote);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(key('more-feedback-badge'), findsOneWidget);
    });

    testWidgets("selecting the More tab reads More's badge again", (
      tester,
    ) async {
      final server = FakeFeedbackRepository()..serverNotes.add(sentNote);
      await pumpMore(tester, app: true, flags: fb4, feedback: server);
      await tapKey(tester, 'tab-list');
      server.serverNotes
        ..clear()
        ..add(readNote);
      final reads = server.reads;
      await tapKey(tester, 'tab-more');
      expect(server.reads, greaterThan(reads));
      await tester.scrollUntilVisible(
        key('more-feedback-badge'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(key('more-feedback-badge'), findsOneWidget);
    });

    testWidgets('the hub and a note sit beside More on a wide screen', (
      tester,
    ) async {
      final more = await pumpMore(
        tester,
        location: feedbackPath,
        size: const Size(1200, 900),
        flags: fb4,
        feedback: fb4Server(),
      );
      expect(key('more-screen'), findsOneWidget);
      expect(key('feedback-hub'), findsOneWidget);
      expect(tester.widget<ListTile>(key('more-feedback')).selected, isTrue);
      await tapKey(tester, 'feedback-note-n-fixed');
      expect(location(more), '/more/feedback/n-fixed');
      expect(key('feedback-note-reply'), findsOneWidget);
      expect(tester.widget<ListTile>(key('more-feedback')).selected, isTrue);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(location(more), feedbackPath);
      expect(tester.takeException(), isNull);
    });

    for (final (scale, brightness) in [
      (1.3, Brightness.light),
      (1.6, Brightness.light),
      (1.6, Brightness.dark),
    ]) {
      testWidgets('hub and note fit at ${(scale * 100).round()} % text, '
          '${brightness.name}', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final more = await pumpMore(
          tester,
          location: feedbackPath,
          flags: fb4,
          deviceBrightness: brightness,
          feedback: fb4Server(),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(key('feedback-write')).height,
          greaterThanOrEqualTo(48),
        );
        await scrollTo(tester, 'feedback-ideas-note');
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(key('feedback-vote-i-aisle')).height,
          greaterThanOrEqualTo(48),
        );
        more.router.go(feedbackNotePath('n-fixed'));
        await tester.pumpAndSettle();
        await scrollTo(tester, 'feedback-whats-new');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
