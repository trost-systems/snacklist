import 'package:family_groceries/feedback/shake.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';

final _start = DateTime.utc(2026, 11, 6, 12);

/// A sample at [ms] after the start, [g] times gravity along y.
AccelerometerEvent sample(int ms, double g) =>
    AccelerometerEvent(0, g * 9.81, 0, _start.add(Duration(milliseconds: ms)));

/// Swings of [g] every [every] ms from [from] on, the phone at rest in
/// between, sampled every 20 ms (the game interval).
List<AccelerometerEvent> swings(
  int count, {
  int from = 0,
  int every = 200,
  double g = 3.2,
}) => [
  for (var i = 0; i < count; i++) ...[
    for (var ms = 0; ms < every; ms += 20)
      sample(from + i * every + ms, ms < 60 ? g : 1),
  ],
];

/// The times (ms after the start) at which [samples] made a shake.
List<int> shakesIn(List<AccelerometerEvent> samples) {
  final detector = ShakeDetector();
  return [
    for (final s in samples)
      if (detector.add(s)) s.timestamp.difference(_start).inMilliseconds,
  ];
}

void main() {
  test('a phone at rest or carried while walking is no shake', () {
    expect(
      shakesIn([for (var ms = 0; ms < 5000; ms += 20) sample(ms, 1)]),
      isEmpty,
    );
    // Steps peak around 1.5 g, twice a second.
    expect(shakesIn(swings(20, every: 500, g: 1.5)), isEmpty);
  });

  test('one bump, or two, is no shake', () {
    expect(shakesIn(swings(1, g: 4)), isEmpty);
    expect(shakesIn(swings(2, g: 4)), isEmpty);
  });

  test('three swings spread over more than 800 ms are no shake', () {
    expect(shakesIn(swings(3, every: 500)), isEmpty);
  });

  test('one swing held over many samples counts once', () {
    expect(
      shakesIn([for (var ms = 0; ms < 1000; ms += 20) sample(ms, 3.5)]),
      isEmpty,
    );
  });

  test('a real shake fires once, on its third swing', () {
    expect(shakesIn(swings(3)), [400]);
    expect(shakesIn(swings(6)), [400], reason: 'the rest is in the cooldown');
  });

  test('a second shake inside the cooldown is ignored; after it, it fires '
      'again', () {
    expect(shakesIn([...swings(3), ...swings(3, from: 800)]), [400]);
    expect(shakesIn([...swings(3), ...swings(3, from: 2000)]), [400, 2400]);
  });

  test('shake only on phones', () {
    for (final platform in TargetPlatform.values) {
      expect(
        shakeSupported(web: false, platform: platform),
        platform == TargetPlatform.android || platform == TargetPlatform.iOS,
        reason: platform.name,
      );
      expect(shakeSupported(web: true, platform: platform), isFalse);
    }
  });
}
