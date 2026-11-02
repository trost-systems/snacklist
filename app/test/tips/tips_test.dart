import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/tips/tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Tip _tip(
  String id, {
  Set<TipSurface>? surfaces,
  String? minVersion,
  String? maxVersion,
}) => Tip(
  id: id,
  title: (_) => id,
  body: (_) => id,
  icon: Icons.lightbulb_outline,
  surfaces: surfaces,
  minVersion: minVersion,
  maxVersion: maxVersion,
);

String? _next(
  List<Tip> queue, {
  TipSurface surface = TipSurface.android,
  String? appVersion = '1.0.0',
  Set<String> dismissed = const {},
}) => nextTip(
  queue,
  surface: surface,
  appVersion: appVersion,
  dismissed: dismissed,
)?.id;

void main() {
  test('the first tip in order shows', () {
    expect(_next([_tip('a'), _tip('b')]), 'a');
  });

  test('a dismissed tip is skipped', () {
    final queue = [_tip('a'), _tip('b')];
    expect(_next(queue, dismissed: {'a'}), 'b');
    expect(_next(queue, dismissed: {'a', 'b'}), isNull);
  });

  test('a tip for other surfaces is skipped', () {
    final queue = [
      _tip('ios', surfaces: {TipSurface.ios}),
      _tip('all'),
    ];
    expect(_next(queue, surface: TipSurface.ios), 'ios');
    expect(_next(queue), 'all');
    expect(_next(queue, surface: TipSurface.web), 'all');
  });

  test('version bounds are inclusive and compared per segment', () {
    final queue = [
      _tip('new', minVersion: '0.1.10'),
      _tip('old', maxVersion: '0.1.9'),
    ];
    expect(_next(queue, appVersion: '0.1.10'), 'new');
    expect(_next(queue, appVersion: '0.2.0+7'), 'new');
    expect(_next(queue, appVersion: '0.1.9'), 'old');
    expect(_next(queue, appVersion: '0.1.2'), 'old');
    expect(
      _next([_tip('window', minVersion: '1.0.0', maxVersion: '1.0.0')]),
      'window',
    );
  });

  test('without a readable version only unbounded tips show', () {
    final queue = [_tip('bounded', minVersion: '0.0.1'), _tip('any')];
    expect(_next(queue, appVersion: null), 'any');
    expect(_next(queue, appVersion: '1.0'), 'any');
    expect(_next(queue, appVersion: 'dev'), 'any');
  });

  test('the surface follows the platform, the web first', () {
    expect(
      TipSurface.current(web: true, platform: TargetPlatform.iOS),
      TipSurface.web,
    );
    expect(
      TipSurface.current(web: false, platform: TargetPlatform.iOS),
      TipSurface.ios,
    );
    expect(
      TipSurface.current(web: false, platform: TargetPlatform.macOS),
      TipSurface.macos,
    );
  });

  test('every tip has its own id', () {
    expect({for (final tip in tips) tip.id}, hasLength(tips.length));
  });

  for (final locale in AppLocalizations.supportedLocales) {
    test('the amounts tip quotes lines that parse with an amount, '
        '${locale.languageCode}', () {
      final body = lookupAppLocalizations(locale).tipAmountsBody;
      final examples = [
        for (final m in RegExp('[„“]([^“”]+)[“”]').allMatches(body)) m[1]!,
      ];
      expect(examples, hasLength(2));
      for (final line in examples) {
        expect(parseEntry(line).quantity, isNotNull, reason: line);
      }
    });
  }
}
