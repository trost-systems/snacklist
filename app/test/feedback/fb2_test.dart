import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';
import 'fb2_harness.dart';

void main() {
  setUpAll(fakeSupabase);

  group('a shake (flag on, phones)', () {
    testWidgets('asks in a bottom sheet; Ohne Bildschirmfoto opens the form '
        'with the live screen name, no picture', (tester) async {
      final (:more, :samples) = await app(tester, location: editPath);
      expect(key('stores-screen'), findsOneWidget);
      await shake(tester, samples);
      await until(tester, () => key('shake-sheet').evaluate().isNotEmpty);
      expect(
        find.text('Problem mit diesem Bildschirm melden?'),
        findsOneWidget,
      );
      expect(find.text('Mit Bildschirmfoto'), findsOneWidget);
      expect(find.text('Ohne Bildschirmfoto'), findsOneWidget);
      expect(find.text('Nicht jetzt'), findsNothing, reason: 'Peter t960u');
      expect(
        tester.getSize(key('shake-without')).height,
        greaterThanOrEqualTo(48),
      );
      await tapKey(tester, 'shake-without');
      expect(key('feedback-sheet'), findsOneWidget);
      expect(find.text('Bildschirmname'), findsOneWidget);
      expect(find.textContaining('Keine Listeneinträge.'), findsOneWidget);
      expect(find.text('stores'), findsOneWidget);
      expect(key('feedback-send-screenshot'), findsNothing);
      await tester.enterText(key('feedback-message'), 'Lidl hakt');
      await tester.pump();
      await tapKey(tester, 'feedback-send');
      final note = more.feedback.rows.values.single;
      expect(note.context.entryPoint, FeedbackEntryPoint.shake);
      expect(note.context.screen, 'stores');
      expect(note.screenshot, isNull);
    }, variant: phones);

    testWidgets('Mit Bildschirmfoto: mark up the screen, then the form shows '
        'the picture that goes; switched off, it stays home', (tester) async {
      final (:more, :samples) = await app(tester);
      await shake(tester, samples);
      await until(tester, () => key('shake-sheet').evaluate().isNotEmpty);
      await tapKey(tester, 'shake-with-screenshot');
      expect(key('annotator-canvas'), findsOneWidget);
      await markUpAndFinish(tester);
      expect(key('feedback-screenshot-preview'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(
        tester
            .getSemantics(
              find.descendant(
                of: key('feedback-screenshot-preview'),
                matching: find.byType(RawImage),
              ),
            )
            .label,
        'Vorschau des Bildschirmfotos',
        reason: 'one named image, no unnamed one inside it',
      );
      semantics.dispose();
      expect(find.text('Bildschirmfoto'), findsOneWidget);
      expect(
        find.textContaining('Keine Listeneinträge.'),
        findsNothing,
        reason: 'the screenshot can show list items',
      );
      expect(
        find.textContaining(
          'auch Einträge und Namen aus deinem Haushalt. Verdecke vorher',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(key('feedback-send')).onPressed,
        isNull,
        reason: 'the text is still required',
      );
      await tester.enterText(key('feedback-message'), 'Mit Bild');
      await tester.pump();
      await tapKey(tester, 'feedback-send');
      final png = more.feedback.rows.values.single.screenshot;
      expect(png, isNotNull);
      expect(png!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47], reason: 'a PNG');
      expect(more.feedback.rows.values.single.context.screen, 'list');
      // "Danke!" goes away.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await shake(tester, samples, atMs: 5000);
      await until(tester, () => key('shake-sheet').evaluate().isNotEmpty);
      await tapKey(tester, 'shake-with-screenshot');
      await markUpAndFinish(tester);
      await tester.enterText(key('feedback-message'), 'Ohne alles');
      await tester.pumpAndSettle();
      await tapKey(tester, 'feedback-send-screenshot');
      expect(
        find.textContaining('Keine Listeneinträge.'),
        findsOneWidget,
        reason: 'switched off, the screenshot stays home',
      );
      await tapKey(tester, 'feedback-send-screen');
      await tapKey(tester, 'feedback-send');
      final last = more.feedback.calls.last;
      expect(last.message, 'Ohne alles');
      expect(last.screenshot, isNull);
      expect(last.context.screen, isNull);
    }, variant: android);

    testWidgets('at 160 % text in dark: question, annotator and form fit, '
        'every button in reach', (tester) async {
      tester.platformDispatcher
        ..textScaleFactorTestValue = 1.6
        ..platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final (:more, :samples) = await app(tester);
      await shake(tester, samples);
      await until(tester, () => key('shake-sheet').evaluate().isNotEmpty);
      await tapKey(tester, 'shake-with-screenshot');
      for (final k in ['annotator-tool-rectangle', 'annotator-done']) {
        await tester.ensureVisible(key(k));
        await tester.pumpAndSettle();
        expect(tester.getSize(key(k)).height, greaterThanOrEqualTo(48));
        expect(
          tester.getRect(key(k)).bottom,
          lessThanOrEqualTo(844),
          reason: k,
        );
      }
      await tester.tap(key('annotator-done'));
      await until(tester, () => key('annotator-canvas').evaluate().isEmpty);
      await tester.enterText(key('feedback-message'), 'Groß');
      await tester.pumpAndSettle();
      await tapKey(tester, 'feedback-send');
      expect(more.feedback.rows.values.single.screenshot, isNotNull);
    }, variant: android);

    testWidgets('✕ or a tap beside the question sends nothing', (tester) async {
      final (:more, :samples) = await app(tester);
      await shake(tester, samples);
      await until(tester, () => key('shake-sheet').evaluate().isNotEmpty);
      await tapKey(tester, 'shake-close');
      expect(key('shake-sheet'), findsNothing);
      expect(key('feedback-sheet'), findsNothing);
      await shake(tester, samples, atMs: 5000);
      await until(tester, () => key('shake-sheet').evaluate().isNotEmpty);
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(key('shake-sheet'), findsNothing);
      expect(key('feedback-sheet'), findsNothing);
      expect(more.feedback.calls, isEmpty);
    }, variant: android);

    testWidgets("the annotator's ✕ ends it: no form, nothing sent", (
      tester,
    ) async {
      final (:more, :samples) = await app(tester);
      await shake(tester, samples);
      await until(tester, () => key('shake-sheet').evaluate().isNotEmpty);
      await tapKey(tester, 'shake-with-screenshot');
      await tapKey(tester, 'annotator-close');
      await tester.pumpAndSettle();
      expect(key('annotator-canvas'), findsNothing);
      expect(key('feedback-sheet'), findsNothing);
      expect(more.feedback.calls, isEmpty);
    }, variant: android);

    testWidgets('a second shake while the question or the form shows opens '
        'nothing more', (tester) async {
      final (more: _, :samples) = await app(tester);
      await shake(tester, samples);
      await until(tester, () => key('shake-sheet').evaluate().isNotEmpty);
      await shake(tester, samples, atMs: 5000);
      await tester.pumpAndSettle();
      expect(key('shake-sheet'), findsOneWidget);
      await tapKey(tester, 'shake-without');
      await shake(tester, samples, atMs: 10000);
      await tester.pumpAndSettle();
      expect(key('shake-sheet'), findsNothing);
      expect(key('feedback-sheet'), findsOneWidget);
    }, variant: android);

    testWidgets('under another dialog a shake opens nothing', (tester) async {
      final (more: _, :samples) = await app(tester);
      showDialog<void>(
        context: tester.element(find.byType(Scaffold).first),
        builder: (_) => const AlertDialog(
          key: ValueKey('other-dialog'),
          content: SizedBox.square(dimension: 48),
        ),
      );
      await tester.pumpAndSettle();
      await shake(tester, samples);
      await tester.pumpAndSettle();
      expect(key('shake-sheet'), findsNothing);
      Navigator.of(tester.element(key('other-dialog'))).pop();
      await tester.pumpAndSettle();
      await shake(tester, samples, atMs: 5000);
      await until(tester, () => key('shake-sheet').evaluate().isNotEmpty);
    }, variant: android);

    testWidgets('in the background the accelerometer is off; back, it is on', (
      tester,
    ) async {
      final (more: _, :samples) = await app(tester);
      expect(samples.hasListener, isTrue);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(samples.hasListener, isFalse);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(samples.hasListener, isTrue);
    }, variant: android);
    testWidgets('a rebuild while inactive leaves the accelerometer off', (
      tester,
    ) async {
      final (:more, :samples) = await app(tester);
      // The app switcher or Control Center: frames still run.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(samples.hasListener, isFalse);
      // The switch flips on another screen's sync, a route moves: the shell
      // builds the listener again.
      more.shake.set(on: false);
      await tester.pump();
      more.shake.set(on: true);
      await tester.pump();
      more.router.go(appSettingsPath);
      await tester.pumpAndSettle();
      expect(samples.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(samples.hasListener, isTrue);
    }, variant: android);
  });

  group('no shake', () {
    testWidgets('with the flag off: the accelerometer is never asked', (
      tester,
    ) async {
      final (more: _, :samples) = await app(tester, flags: const {});
      expect(samples.hasListener, isFalse);
    }, variant: phones);

    testWidgets('on a desktop (and the web, `shakeSupported`)', (tester) async {
      final (more: _, :samples) = await app(tester);
      expect(samples.hasListener, isFalse);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('switched off under Einstellungen, kept on the device', (
      tester,
    ) async {
      final (:more, :samples) = await app(tester, location: appSettingsPath);
      expect(samples.hasListener, isTrue);
      expect(find.text('Schütteln für Feedback'), findsOneWidget);
      await tapKey(tester, 'settings-shake');
      expect(samples.hasListener, isFalse);
      expect(await more.cache.shakeToFeedback(), isFalse);
      await tapKey(tester, 'settings-shake');
      expect(samples.hasListener, isTrue);
      expect(await more.cache.shakeToFeedback(), isTrue);
    }, variant: android);

    testWidgets('no switch with the flag off or off the phone', (tester) async {
      await app(tester, location: appSettingsPath, flags: const {});
      expect(key('settings-shake'), findsNothing);
    }, variant: phones);

    testWidgets('no switch on a desktop', (tester) async {
      await app(tester, location: appSettingsPath);
      expect(key('settings-shake'), findsNothing);
    }, variant: TargetPlatformVariant.desktop());
  });

  group("More's row", () {
    Future<void> openFromMore(WidgetTester tester) async {
      await tapKey(tester, 'tab-more');
      await until(tester, () => key('more-screen').evaluate().isNotEmpty);
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.descendant(
          of: key('more-screen'),
          matching: find.byType(Scrollable),
        ),
      );
      await tapKey(tester, 'more-feedback');
    }

    testWidgets('flag on: no screen name; the screen before More can be '
        'added, marked up and sent', (tester) async {
      final (:more, samples: _) = await app(tester);
      await openFromMore(tester);
      expect(key('feedback-send-screen'), findsNothing);
      expect(find.text('Bildschirmname'), findsNothing);
      expect(find.text('Bildschirmfoto hinzufügen'), findsOneWidget);
      expect(
        tester.getSize(key('feedback-add-screenshot')).height,
        greaterThanOrEqualTo(48),
      );
      await tapKey(tester, 'feedback-add-screenshot');
      expect(key('annotator-canvas'), findsOneWidget);
      await markUpAndFinish(tester);
      expect(key('feedback-screenshot-preview'), findsOneWidget);
      expect(key('feedback-add-screenshot'), findsNothing);
      await tester.enterText(key('feedback-message'), 'Aus dem Menü');
      await tester.pump();
      await tapKey(tester, 'feedback-send');
      final note = more.feedback.rows.values.single;
      expect(note.context.entryPoint, FeedbackEntryPoint.settings);
      expect(note.context.screen, isNull);
      expect(note.screenshot, isNotNull);
    }, variant: android);

    testWidgets('a refused screenshot says to send without it; switched off '
        'it goes', (tester) async {
      final (:more, samples: _) = await app(tester);
      await openFromMore(tester);
      await tapKey(tester, 'feedback-add-screenshot');
      await markUpAndFinish(tester);
      await tester.enterText(key('feedback-message'), 'Zu viele Bilder');
      await tester.pump();
      more.feedback
        ..failNext = 1
        ..error = const FeedbackScreenshotRefused('storage_403');
      await tapKey(tester, 'feedback-send');
      expect(
        find.text(
          'Das Bildschirmfoto wurde nicht angenommen. Schalte es aus, dann '
          'geht deine Nachricht ohne Bild.',
        ),
        findsOneWidget,
      );
      expect(more.feedback.rows, isEmpty);
      await tapKey(tester, 'feedback-send-screenshot');
      await tapKey(tester, 'feedback-send');
      expect(more.feedback.rows.values.single.screenshot, isNull);
    }, variant: android);

    testWidgets('the router leaving More under the open annotator: drawing '
        'and Fertig still give the PNG', (tester) async {
      final (:more, samples: _) = await app(tester);
      await openFromMore(tester);
      await tapKey(tester, 'feedback-add-screenshot');
      expect(key('annotator-canvas'), findsOneWidget);
      // A link or a household switch: the screen before More is stale.
      more.router.go(listPath);
      await tester.pump();
      expect(more.capture.beforeMore, isNull);
      await markUpAndFinish(tester);
      expect(tester.takeException(), isNull);
      expect(key('feedback-screenshot-preview'), findsOneWidget);
    }, variant: android);

    testWidgets('flag on: text only still goes, without a picture', (
      tester,
    ) async {
      final (:more, samples: _) = await app(tester);
      await openFromMore(tester);
      await tester.enterText(key('feedback-message'), 'Nur Text');
      await tester.pump();
      await tapKey(tester, 'feedback-send');
      expect(more.feedback.rows.values.single.screenshot, isNull);
    });

    testWidgets('flag off: the form as before, nothing pictured', (
      tester,
    ) async {
      final (:more, samples: _) = await app(tester, flags: const {});
      await openFromMore(tester);
      expect(more.capture.beforeMore, isNull);
      expect(key('feedback-add-screenshot'), findsNothing);
      expect(
        find.textContaining(
          'App-Version, Gerät und Sprache. Keine Listeneinträge.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Bildschirm'), findsNothing);
    });

    testWidgets('leaving More drops the picture', (tester) async {
      final (:more, samples: _) = await app(tester);
      await tapKey(tester, 'tab-more');
      await until(tester, () => more.capture.beforeMore != null);
      await tapKey(tester, 'tab-list');
      expect(more.capture.beforeMore, isNull);
    });
  });

  testWidgets('the paywall has no feedback entry, flag on', (tester) async {
    await pumpMore(tester, location: premiumPath, flags: fb2);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('feedback'),
      ),
      findsNothing,
    );
    expect(find.textContaining('Feedback'), findsNothing);
    expect(find.textContaining('Bildschirmfoto'), findsNothing);
  });

  test('no Peter in what the feedback and shake screens say', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final text in [
        l10n.feedbackContact,
        l10n.feedbackAttached,
        l10n.feedbackAttachedBasics,
        l10n.feedbackScreenName,
        l10n.feedbackScreenshot,
        l10n.feedbackScreenshotNote,
        l10n.feedbackAddScreenshot,
        l10n.feedbackShakeTitle,
        l10n.feedbackShakeWithScreenshot,
        l10n.feedbackShakeWithout,
        l10n.feedbackShakeOffHint,
        l10n.feedbackAnnotateHint,
        l10n.feedbackAnnotateDone,
        l10n.shakeToFeedback,
        l10n.shakeToFeedbackHint,
      ]) {
        expect(text, isNot(contains('Peter')), reason: '$locale: $text');
      }
      expect(l10n.feedbackContact, startsWith('Snacklist Support'));
    }
  });
}
