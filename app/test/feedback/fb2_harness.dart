import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../more/more_harness.dart';

/// Shared by the FB2 tests and their review screenshots (job 267).
const fb2 = {feedbackFb2Flag};
const android = TargetPlatformVariant({TargetPlatform.android});
const phones = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
});

Finder key(String k) => find.byKey(ValueKey(k));

/// Frames and real time in turns, until [done]: a screenshot is taken and
/// encoded by the engine, outside the test's fake time.
Future<void> until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      // ast-grep-ignore: no-wall-time-wait-in-tests -- runAsync: engine work
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done(), isTrue, reason: 'waited 300 frames');
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.pumpAndSettle();
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

final _start = DateTime.utc(2026, 11, 15, 12);

/// Three hard swings from [atMs] on, sampled every 20 ms.
Future<void> shake(
  WidgetTester tester,
  StreamController<AccelerometerEvent> samples, {
  int atMs = 0,
}) async {
  for (var ms = 0; ms < 600; ms += 20) {
    final g = ms % 200 < 60 ? 3.5 : 1.0;
    samples.add(
      AccelerometerEvent(
        0,
        g * 9.81,
        0,
        _start.add(Duration(milliseconds: atMs + ms)),
      ),
    );
  }
  await tester.pump();
}

/// The app on [location] with [flags], its accelerometer in the record.
Future<({More more, StreamController<AccelerometerEvent> samples})> app(
  WidgetTester tester, {
  String location = listPath,
  Set<String> flags = fb2,
}) async {
  final samples = StreamController<AccelerometerEvent>.broadcast();
  addTearDown(samples.close);
  final more = await pumpMore(
    tester,
    location: location,
    app: true,
    flags: flags,
    shakeSamples: samples.stream,
  );
  return (more: more, samples: samples);
}

/// Pen stroke across the screenshot, then Fertig.
Future<void> markUpAndFinish(WidgetTester tester) async {
  final shown = tester.getRect(key('annotator-canvas'));
  final gesture = await tester.startGesture(shown.center);
  for (var i = 1; i <= 4; i++) {
    await gesture.moveBy(const Offset(12, 4));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
  await tester.tap(key('annotator-done'));
  await until(tester, () => key('annotator-canvas').evaluate().isEmpty);
}
