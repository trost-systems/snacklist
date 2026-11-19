import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/feedback/annotator.dart';
import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_sheet.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/report/report_cubit.dart';
import 'package:family_groceries/report/report_repository.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../feedback/fb2_harness.dart'
    show android, key, markUpAndFinish, tapKey, until;
import '../feedback/fb4_harness.dart' show fb4Server;
import '../more/more_harness.dart';
import 'fakes.dart';
import 'report_harness.dart';

void main() {
  setUpAll(fakeSupabase);

  group('flag off', () {
    testWidgets('More, the feedback form and the hub show no report entry', (
      tester,
    ) async {
      await pumpMore(tester);
      await openRow(tester);
      expect(rowText('Auch: Inhalte melden'), findsNothing);
      expect(key('feedback-sheet'), findsOneWidget);
      expect(key('report-entry'), findsNothing);
      expect(find.text('Inhalt melden'), findsNothing);
    });

    testWidgets('with FB4: the row and the hub as before', (tester) async {
      await pumpMore(tester, flags: {feedbackFb4Flag}, feedback: fb4Server());
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(rowText('Feedback & Ideen'), findsOneWidget);
      expect(rowText('Auch: Inhalte melden'), findsNothing);
      await tapKey(tester, 'more-feedback');
      expect(key('feedback-hub'), findsOneWidget);
      expect(key('report-entry'), findsNothing);
    });
  });

  group('flag on, without FB4', () {
    testWidgets('the row says reporting is there; the feedback form starts '
        'with Inhalt melden, which closes it and opens the report form; ✕ '
        'comes back to More', (tester) async {
      final more = await pumpMore(tester, flags: report);
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(rowText('Feedback senden'), findsOneWidget);
      expect(rowText('Auch: Inhalte melden'), findsOneWidget);
      await tapKey(tester, 'more-feedback');
      final entry = tester.getRect(key('report-entry'));
      expect(
        entry.bottom,
        lessThan(tester.getRect(key('feedback-message')).top),
        reason: 'above the message',
      );
      expect(
        find.text('Nur wir lesen die Meldung, niemand in deinem Haushalt.'),
        findsOneWidget,
      );
      await tapKey(tester, 'report-entry');
      expect(key('feedback-sheet'), findsNothing);
      expect(key('report-form'), findsOneWidget);
      expect(find.text('Inhalt melden'), findsOneWidget, reason: 'title');
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(key('report-form'), findsNothing);
      expect(location(more), morePath);
      expect(more.report.sent, isEmpty);
    });

    testWidgets('a shake opens the feedback form without the entry', (
      tester,
    ) async {
      await pumpMore(tester, flags: report);
      final more = tester.element(find.byType(MoreScreen));
      final open = showFeedbackSheet(
        more,
        entryPoint: FeedbackEntryPoint.shake,
      );
      await tester.pumpAndSettle();
      expect(key('feedback-sheet'), findsOneWidget);
      expect(key('report-entry'), findsNothing);
      await tapKey(tester, 'feedback-close');
      expect(await open, isFalse);
    });
  });

  group('flag on, with FB4', () {
    testWidgets('the hub row says reporting is there; the hub has Inhalt '
        'melden right under writing to support; Done goes back to the hub', (
      tester,
    ) async {
      final more = await pumpMore(
        tester,
        flags: reportFb4,
        feedback: fb4Server(),
        seed: seedHousehold,
      );
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(rowText('Feedback & Ideen'), findsOneWidget);
      expect(rowText('Auch: Inhalte melden'), findsOneWidget);
      await tapKey(tester, 'more-feedback');
      final write = tester.getRect(key('feedback-write'));
      final entry = tester.getRect(key('report-entry'));
      expect(entry.top, greaterThan(write.bottom));
      expect(
        entry.bottom,
        lessThan(tester.getRect(find.text('DEINE NOTIZEN')).top),
      );
      await tapKey(tester, 'feedback-write');
      expect(
        key('report-entry'),
        findsOneWidget,
        reason: "the hub's; the form from the hub has none of its own",
      );
      await tapKey(tester, 'feedback-close');

      await tapKey(tester, 'report-entry');
      await fillIn(tester);
      await send(tester);
      await tapKey(tester, 'report-done');
      expect(key('report-form'), findsNothing);
      expect(key('feedback-hub'), findsOneWidget);
      expect(location(more), feedbackPath);
    });
  });

  group('prefill', () {
    testWidgets('name and e-mail address come from the sign-in, editable, '
        'and are sent', (tester) async {
      final reports = FakeReportRepository(who: mia);
      await openForm(tester, reports: reports);
      await show(tester, 'report-name');
      expect(find.text('Mia Brandt'), findsOneWidget);
      expect(find.text('mia.brandt@example.com'), findsOneWidget);
      expect(find.text('Dein Name (empfohlen)'), findsOneWidget);
      await tester.enterText(key('report-name'), 'Mia B.');
      await fillIn(tester);
      await send(tester);
      final sent = reports.sent.single;
      expect(sent.name, 'Mia B.');
      expect(sent.email, 'mia.brandt@example.com');
      expect(
        find.text('Eine Bestätigung ist an mia.brandt@example.com unterwegs.'),
        findsOneWidget,
      );
    });

    testWidgets('no provider name: the name stays empty, and none goes', (
      tester,
    ) async {
      final reports = FakeReportRepository(
        who: const Reporter(email: 'mia.brandt@example.com'),
      );
      await openForm(tester, reports: reports);
      await show(tester, 'report-name');
      expect(
        tester.widget<TextField>(key('report-name')).controller?.text,
        isEmpty,
      );
      await fillIn(tester);
      await send(tester);
      expect(reports.sent.single.name, isNull);
      expect(reports.sent.single.email, 'mia.brandt@example.com');
    });

    testWidgets('a long provider name is trimmed and cut to what the server '
        'takes, in code points', (tester) async {
      final reports = FakeReportRepository(
        who: Reporter(name: '  ${'👍🏽' * 150}  '),
      );
      await openForm(tester, reports: reports);
      await show(tester, 'report-name');
      expect(
        tester.widget<TextField>(key('report-name')).controller?.text,
        '👍🏽' * 100,
      );
      await fillIn(tester);
      await send(tester);
      expect(reports.sent.single.name, '👍🏽' * 100);
    });
  });

  group('child sexual abuse material', () {
    testWidgets('hides name and e-mail behind the note and sends neither', (
      tester,
    ) async {
      final reports = FakeReportRepository(who: mia);
      await openForm(tester, reports: reports);
      await fillIn(tester, category: ReportCategory.csam);
      expect(key('report-name'), findsNothing);
      expect(key('report-email'), findsNothing);
      expect(
        find.text(
          'Bei Darstellungen sexuellen Kindesmissbrauchs kannst du ohne '
          'Namen und E-Mail-Adresse melden.',
        ),
        findsOneWidget,
      );
      await send(tester);
      final sent = reports.sent.single;
      expect(sent.category, ReportCategory.csam);
      expect(sent.body['category'], 'csam');
      expect(sent.body.containsKey('name'), isFalse);
      expect(sent.body.containsKey('email'), isFalse);
      expect(
        find.text(
          'Du hast keine E-Mail-Adresse angegeben, darum können wir dir nicht '
          'antworten. Heb die Nummer auf, wenn du nachfragen willst.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('added, they show empty with the note as their help, and '
        'only what is typed goes', (tester) async {
      final reports = FakeReportRepository(who: mia);
      await openForm(tester, reports: reports);
      await fillIn(tester, category: ReportCategory.csam);
      await show(tester, 'report-csam-add');
      await tapKey(tester, 'report-csam-add');
      expect(
        tester.widget<TextField>(key('report-name')).controller?.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(key('report-email')).controller?.text,
        isEmpty,
      );
      expect(find.text('Mia Brandt'), findsNothing);
      expect(
        tester.widget<Text>(key('report-contact-help')).data,
        'Bei Darstellungen sexuellen Kindesmissbrauchs kannst du ohne Namen '
        'und E-Mail-Adresse melden.',
      );
      await send(tester);
      expect(reports.sent.single.body.containsKey('name'), isFalse);
      expect(reports.sent.single.body.containsKey('email'), isFalse);
    });

    testWidgets('typed after adding, they go', (tester) async {
      final reports = FakeReportRepository(who: mia);
      await openForm(tester, reports: reports);
      await fillIn(tester, category: ReportCategory.csam);
      await show(tester, 'report-csam-add');
      await tapKey(tester, 'report-csam-add');
      await show(tester, 'report-email');
      await tester.enterText(key('report-email'), 'anders@example.com');
      await tester.pump();
      await send(tester);
      expect(reports.sent.single.email, 'anders@example.com');
      expect(reports.sent.single.body.containsKey('name'), isFalse);
    });

    testWidgets('another kind after it brings the prefill back', (
      tester,
    ) async {
      final reports = FakeReportRepository(who: mia);
      await openForm(tester, reports: reports);
      await fillIn(tester, category: ReportCategory.csam);
      await show(tester, 'report-category-hate');
      await tapKey(tester, 'report-category-hate');
      expect(
        tester.widget<TextField>(key('report-name')).controller?.text,
        'Mia Brandt',
      );
      await send(tester);
      expect(reports.sent.single.name, 'Mia Brandt');
      expect(reports.sent.single.email, 'mia.brandt@example.com');
    });

    testWidgets('a cleared name and e-mail stay cleared when the kind '
        'changes, and neither goes', (tester) async {
      final reports = FakeReportRepository(who: mia);
      await openForm(tester, reports: reports);
      await fillIn(tester);
      await clearContact(tester);
      await show(tester, 'report-category-danger');
      await tapKey(tester, 'report-category-danger');
      expect(
        tester.widget<TextField>(key('report-name')).controller?.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(key('report-email')).controller?.text,
        isEmpty,
      );
      await send(tester);
      expect(reports.sent.single.body.containsKey('name'), isFalse);
      expect(reports.sent.single.body.containsKey('email'), isFalse);
    });

    testWidgets('cleared before it, they stay cleared after leaving it', (
      tester,
    ) async {
      final reports = FakeReportRepository(who: mia);
      await openForm(tester, reports: reports);
      await fillIn(tester);
      await clearContact(tester);
      await show(tester, 'report-category-csam');
      await tapKey(tester, 'report-category-csam');
      await show(tester, 'report-category-ip');
      await tapKey(tester, 'report-category-ip');
      await send(tester);
      expect(reports.sent.single.body.containsKey('name'), isFalse);
      expect(reports.sent.single.body.containsKey('email'), isFalse);
    });
  });

  testWidgets('„Woanders“ stays in reach above a long household', (
    tester,
  ) async {
    await pumpMore(
      tester,
      flags: report,
      seed: (repo) {
        seedHousehold(repo);
        for (var i = 0; i < 40; i++) {
          repo.remoteAdd('Eintrag $i', listId: 'weekly');
        }
      },
    );
    await openRow(tester);
    await tapKey(tester, 'report-entry');
    await show(tester, 'report-where-choose');
    await tapKey(tester, 'report-where-choose');
    expect(key('report-pick-elsewhere').hitTestable(), findsOneWidget);
  });

  group('validation', () {
    testWidgets('Send on an empty form names each missing part, scrolls to '
        'the first and sends nothing', (tester) async {
      final more = await openForm(tester);
      await send(tester);
      expect(more.report.sent, isEmpty);
      for (final text in [
        'Wähle, worum es geht.',
        'Wähle, wo der Inhalt ist.',
        'Mindestens 20 Zeichen (noch 20).',
        'Bitte bestätige das, um die Meldung zu senden.',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      final form = tester.getRect(key('report-form'));
      final first = tester.getRect(key('report-error-category'));
      expect(
        form.contains(first.center),
        isTrue,
        reason: 'scrolled back to the first',
      );
    });

    testWidgets('a short reason counts down, a long one is refused, an '
        'e-mail address must be one', (tester) async {
      final more = await openForm(tester);
      await fillIn(tester);
      await show(tester, 'report-reason');
      await tester.enterText(key('report-reason'), ' Zu kurz. ');
      await tester.pump();
      expect(find.text('8 / 5.000'), findsOneWidget);
      await tester.enterText(key('report-reason'), 'x' * 5001);
      await tester.pump();
      expect(find.text('5.001 / 5.000'), findsOneWidget);
      await send(tester);
      expect(find.text('Höchstens 5.000 Zeichen.'), findsOneWidget);
      await show(tester, 'report-reason');
      await tester.enterText(key('report-reason'), 'Zu kurz.');
      await show(tester, 'report-email');
      await tester.enterText(key('report-email'), 'mia.brandt@');
      await send(tester);
      expect(find.text('Mindestens 20 Zeichen (noch 12).'), findsOneWidget);
      expect(find.text('Prüfe die E-Mail-Adresse.'), findsOneWidget);
      expect(more.report.sent, isEmpty);
    });

    testWidgets('an address the server would refuse is an error here too', (
      tester,
    ) async {
      final more = await openForm(tester);
      await fillIn(tester);
      await show(tester, 'report-email');
      await tester.enterText(key('report-email'), 'a@b.c');
      await send(tester);
      expect(find.text('Prüfe die E-Mail-Adresse.'), findsOneWidget);
      expect(more.report.sent, isEmpty);
      await show(tester, 'report-email');
      await tester.enterText(key('report-email'), 'a@b.co');
      await send(tester);
      expect(more.report.sent.single.email, 'a@b.co');
    });

    testWidgets('name and place stop at the server limits in code points, '
        'not characters', (tester) async {
      final reports = FakeReportRepository();
      await openForm(tester, reports: reports);
      await fillIn(tester);
      await pickElsewhere(tester);
      await show(tester, 'report-elsewhere');
      await tester.enterText(key('report-elsewhere'), '👍🏽' * 1500);
      await show(tester, 'report-name');
      await tester.enterText(key('report-name'), '👍🏽' * 150);
      await send(tester);
      final body = reports.sent.single.body;
      expect((body['location']! as String).runes, hasLength(2000));
      expect((body['name']! as String).runes, hasLength(200));
    });

    test('a screenshot over 2 MiB is refused before it is sent', () async {
      final reports = FakeReportRepository();
      final cubit = ReportCubit(reports, locale: 'de')
        ..pick(ReportCategory.hate)
        ..describe('Haushalt „WG Süd“')
        ..write('Dieser Eintrag beleidigt meinen Nachbarn.')
        ..confirm(goodFaith: true)
        ..attach(Uint8List(2 * 1024 * 1024 + 1));
      expect(await cubit.send(), isFalse);
      expect(
        cubit.state.status,
        isA<ReportFailed>().having(
          (f) => f.error,
          'error',
          isA<ReportScreenshotTooLarge>(),
        ),
      );
      expect(reports.sent, isEmpty);
      cubit.attach(Uint8List(2 * 1024 * 1024));
      expect(await cubit.send(), isTrue, reason: '2 MiB fit');
      await cubit.close();
    });
  });

  group('sending', () {
    testWidgets('the picked item goes with its place, the trimmed reason and '
        'the good faith; the confirmation shows the number to copy, and '
        'Done goes back to More', (tester) async {
      final reports = FakeReportRepository(who: mia);
      final more = await openForm(tester, reports: reports);
      await fillIn(tester);
      await show(tester, 'report-picked');
      expect(find.text('„Hafermilch“'), findsOneWidget);
      expect(find.text('Liste „Wocheneinkauf“ · Zuhause'), findsOneWidget);
      await send(tester);
      expect(reports.sent.single.body, {
        'locale': 'de',
        'category': 'hate',
        'target': {'kind': 'item', 'id': 'remote-0'},
        'location':
            'item "Hafermilch" in list "Wocheneinkauf", household "Zuhause"',
        'reason': 'Dieser Eintrag beleidigt meinen Nachbarn mit vollem Namen.',
        'name': 'Mia Brandt',
        'email': 'mia.brandt@example.com',
        'good_faith': true,
      });
      expect(key('report-sent'), findsOneWidget);
      expect(find.text('Meldung gesendet'), findsOneWidget);
      expect(find.text('M-7K2M-4Q9P'), findsOneWidget);
      expect(
        find.text(
          'Danke, deine Meldung ist eingegangen. Nummer: M-7K2M-4Q9P. Wir '
          'prüfen sie selbst – ohne automatische Entscheidung – und melden '
          'uns, wenn du eine E-Mail-Adresse angegeben hast.',
        ),
        findsOneWidget,
      );
      final clipboard = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map<Object?, Object?>)['text']);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tapKey(tester, 'report-copy');
      expect(clipboard, ['M-7K2M-4Q9P']);
      expect(find.text('Kopiert'), findsOneWidget);
      await show(tester, 'report-done');
      await tapKey(tester, 'report-done');
      expect(key('report-sent'), findsNothing);
      expect(location(more), morePath);
      expect(find.byType(MoreScreen), findsOneWidget);
    });

    testWidgets('a picked list goes with its place; the picker searches '
        'items and lists', (tester) async {
      final reports = FakeReportRepository();
      await openForm(tester, reports: reports);
      await fillIn(tester);

      await tapKey(tester, 'report-where-choose');
      await tester.enterText(key('report-picker-search'), 'party');
      await tester.pumpAndSettle();
      expect(key('report-pick-item-remote-0'), findsNothing);
      expect(key('report-pick-list-weekly'), findsNothing);
      await tapKey(tester, 'report-pick-list-party');
      await send(tester);
      expect(reports.sent.last.body['target'], {'kind': 'list', 'id': 'party'});
      expect(
        reports.sent.last.body['location'],
        'list "Party am Samstag", household "Zuhause"',
      );
    });

    testWidgets("somewhere else: Legal's help with the field, the text is "
        'the place', (tester) async {
      final reports = FakeReportRepository();
      await openForm(tester, reports: reports);
      await fillIn(tester);
      await pickElsewhere(tester);
      expect(
        find.text(
          'Beschreibe, wo er ist: Name des Haushalts und der Liste und der '
          'genaue Text des Eintrags. Je genauer, desto schneller finden wir '
          'ihn.',
        ),
        findsOneWidget,
      );
      await send(tester);
      expect(reports.sent, isEmpty, reason: 'no place described yet');
      expect(find.text('Wähle, wo der Inhalt ist.'), findsOneWidget);
      await show(tester, 'report-elsewhere');
      await tester.enterText(
        key('report-elsewhere'),
        ' Haushalt „WG Süd“, Eintrag „…“ ',
      );
      await send(tester);
      expect(reports.sent.single.body['target'], {'kind': 'elsewhere'});
      expect(
        reports.sent.single.body['location'],
        'Haushalt „WG Süd“, Eintrag „…“',
      );
    });

    for (final (error, text) in [
      (
        const ReportRateLimited() as ReportError,
        'Deine Meldung wurde nicht gesendet, weil gerade zu viele Meldungen '
            'ankommen. Deine Angaben sind noch da. Bitte versuch es in einer '
            'Stunde noch einmal oder schick sie per E-Mail an unsere '
            'Kontaktstelle support@snacklist.app: worum es geht, wo der Inhalt '
            'ist und warum er rechtswidrig ist. Auch so bearbeiten wir deine '
            'Meldung.',
      ),
      (
        const ReportScreenshotTooLarge(),
        'Der Screenshot ist zu groß. Entferne ihn und sende die Meldung noch '
            'einmal.',
      ),
      (
        const ReportOffline(),
        'Keine Verbindung. Deine Angaben sind noch da: Bitte versuch es gleich '
            'noch einmal.',
      ),
      (
        const ReportRefused('503'),
        'Die Meldung konnte gerade nicht gesendet werden. Bitte versuch es '
            'gleich noch einmal oder schreib an support@snacklist.app.',
      ),
    ]) {
      testWidgets('${error.runtimeType}: says so, keeps everything, and the '
          'next tap sends it', (tester) async {
        final reports = FakeReportRepository()
          ..failNext = 1
          ..error = error;
        await openForm(tester, reports: reports);
        await fillIn(tester);
        await send(tester);
        expect(find.text(text), findsOneWidget);
        expect(key('report-sent'), findsNothing);
        expect(
          tester.widget<TextField>(key('report-reason')).controller?.text,
          contains('beleidigt meinen Nachbarn'),
        );
        await send(tester);
        expect(reports.sent, hasLength(2));
        expect(reports.sent.last.body, reports.sent.first.body);
        expect(key('report-sent'), findsOneWidget);
      });
    }

    testWidgets('while sending: a spinner, and a second tap sends nothing', (
      tester,
    ) async {
      final reports = FakeReportRepository()..hold = Completer<void>();
      await openForm(tester, reports: reports);
      await fillIn(tester);
      await show(tester, 'report-send');
      await tester.tap(key('report-send'));
      await tester.pump();
      expect(
        find.descendant(
          of: key('report-send'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(key('report-send'));
      await tester.pump();
      expect(reports.sent, hasLength(1));
      reports.hold?.complete();
      await tester.pumpAndSettle();
      expect(key('report-sent'), findsOneWidget);
    });

    testWidgets('while sending neither ✕ nor back closes the page', (
      tester,
    ) async {
      final reports = FakeReportRepository()..hold = Completer<void>();
      await openForm(tester, reports: reports);
      expect(find.byType(CloseButton), findsOneWidget);
      await fillIn(tester);
      await show(tester, 'report-send');
      await tester.tap(key('report-send'));
      await tester.pump();
      expect(find.byType(CloseButton), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(key('report-form'), findsOneWidget);
      reports.hold?.complete();
      await tester.pumpAndSettle();
      expect(key('report-sent'), findsOneWidget, reason: 'the number shows');
    });
  });

  group('screenshot', () {
    testWidgets('without feedback-fb2 there is no screenshot row', (
      tester,
    ) async {
      await openForm(tester);
      expect(key('report-screenshot'), findsNothing);
    });

    testWidgets('with feedback-fb2 but no picture of the screen before More '
        'there is none either', (tester) async {
      final more = await openForm(
        tester,
        flags: {reportContentEntryFlag, feedbackFb2Flag},
      );
      expect(more.capture.beforeMore, isNull);
      expect(key('report-screenshot'), findsNothing);
    });

    testWidgets('with feedback-fb2 the screen before More is attached only '
        'on a tap, covered in the annotator, and sent', (tester) async {
      final reports = FakeReportRepository();
      final more = await pumpMore(
        tester,
        location: listPath,
        app: true,
        flags: {reportContentEntryFlag, feedbackFb2Flag},
        report: reports,
        seed: seedHousehold,
      );
      await tapKey(tester, 'tab-more');
      await until(tester, () => more.capture.beforeMore != null);
      await openRow(tester);
      await tapKey(tester, 'report-entry');
      await show(tester, 'report-screenshot-add');
      expect(find.text('Screenshot anhängen (optional)'), findsOneWidget);
      expect(key('report-screenshot-preview'), findsNothing);

      await tapKey(tester, 'report-screenshot-add');
      expect(key('annotator-canvas'), findsOneWidget);
      expect(key('annotator-tool-cover'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Annotator),
          matching: find.text(
            'Verdecke darauf, was nichts mit der Meldung zu tun hat.',
          ),
        ),
        findsOneWidget,
        reason: "the annotator's hint",
      );
      await markUpAndFinish(tester);
      await show(tester, 'report-screenshot-preview');
      expect(find.text('Screenshot angehängt'), findsOneWidget);

      await fillIn(tester);
      await send(tester);
      final png = reports.sent.single.screenshot;
      expect(png, isNotNull);
      expect(png!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(reports.sent.single.body['screenshot'], isA<String>());
    }, variant: android);

    testWidgets('Remove takes the screenshot off again', (tester) async {
      final reports = FakeReportRepository();
      final more = await pumpMore(
        tester,
        location: listPath,
        app: true,
        flags: {reportContentEntryFlag, feedbackFb2Flag},
        report: reports,
        seed: seedHousehold,
      );
      await tapKey(tester, 'tab-more');
      await until(tester, () => more.capture.beforeMore != null);
      await openRow(tester);
      await tapKey(tester, 'report-entry');
      await show(tester, 'report-screenshot-add');
      await tapKey(tester, 'report-screenshot-add');
      await markUpAndFinish(tester);
      await show(tester, 'report-screenshot-remove');
      await tapKey(tester, 'report-screenshot-remove');
      expect(key('report-screenshot-preview'), findsNothing);
      expect(key('report-screenshot-add'), findsOneWidget);
      await fillIn(tester);
      await send(tester);
      expect(reports.sent.single.screenshot, isNull);
      expect(reports.sent.single.body.containsKey('screenshot'), isFalse);
    }, variant: android);

    testWidgets('child sexual abuse material hides the screenshot row and '
        'drops the attached screenshot (Legal N-287)', (tester) async {
      final reports = FakeReportRepository();
      final more = await pumpMore(
        tester,
        location: listPath,
        app: true,
        flags: {reportContentEntryFlag, feedbackFb2Flag},
        report: reports,
        seed: seedHousehold,
      );
      await tapKey(tester, 'tab-more');
      await until(tester, () => more.capture.beforeMore != null);
      await openRow(tester);
      await tapKey(tester, 'report-entry');
      await show(tester, 'report-screenshot-add');
      await tapKey(tester, 'report-screenshot-add');
      await markUpAndFinish(tester);
      await show(tester, 'report-screenshot-preview');

      await show(tester, 'report-category-csam');
      await tapKey(tester, 'report-category-csam');
      expect(key('report-screenshot'), findsNothing);
      expect(key('report-screenshot-add'), findsNothing);

      await fillIn(tester, category: ReportCategory.csam);
      await send(tester);
      expect(reports.sent.single.category, ReportCategory.csam);
      expect(reports.sent.single.screenshot, isNull);
      expect(reports.sent.single.body.containsKey('screenshot'), isFalse);
    }, variant: android);

    testWidgets('leaving child sexual abuse material shows the row again, '
        'without the dropped screenshot', (tester) async {
      final more = await pumpMore(
        tester,
        location: listPath,
        app: true,
        flags: {reportContentEntryFlag, feedbackFb2Flag},
        report: FakeReportRepository(),
        seed: seedHousehold,
      );
      await tapKey(tester, 'tab-more');
      await until(tester, () => more.capture.beforeMore != null);
      await openRow(tester);
      await tapKey(tester, 'report-entry');
      await show(tester, 'report-screenshot-add');
      await tapKey(tester, 'report-screenshot-add');
      await markUpAndFinish(tester);
      await show(tester, 'report-category-csam');
      await tapKey(tester, 'report-category-csam');
      await show(tester, 'report-category-hate');
      await tapKey(tester, 'report-category-hate');
      await show(tester, 'report-screenshot-add');
      expect(key('report-screenshot-preview'), findsNothing);
    }, variant: android);
  });
}
