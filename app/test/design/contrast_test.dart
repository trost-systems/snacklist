import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/core/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The token source; `flutter test` runs in app/.
final _tokens = jsonDecode(
  File('../design/tokens/snacklist.tokens.json').readAsStringSync(),
) as Map<String, dynamic>;

Color _color(String mode, String name) {
  final modes = _tokens['color'] as Map<String, dynamic>;
  final token = (modes[mode] as Map<String, dynamic>)[name];
  if (token == null) {
    throw ArgumentError('no color.$mode.$name');
  }
  final value = (token as Map<String, dynamic>)[r'$value'];
  final hex = (value as Map<String, dynamic>)['hex'] as String;
  return Color(int.parse('ff${hex.substring(1)}', radix: 16));
}

double _ratio(String mode, String a, String b) =>
    contrastRatio(_color(mode, a), _color(mode, b));

Map<String, dynamic> get _rules =>
    (_tokens[r'$extensions'] as Map<String, dynamic>)['com.snacklist']
        as Map<String, dynamic>;

void main() {
  test("the dark yellow is option 6's, the same as light", () {
    expect(_color('light', 'honey'), const Color(0xFFFFE24A));
    expect(_color('dark', 'honey'), const Color(0xFFFFE24A));
    expect(_color('dark', 'honey-edge'), const Color(0xFFB39B1A));
  });

  // Every pair the design pairs up (text on a fill, a control on its
  // ground), in the modes it is used in: a palette change that drops one
  // under its minimum fails here.
  for (final pair in _rules['contrastPairs'] as List<dynamic>) {
    final [fg as String, bg as String, min as num, ...rest] = pair as List;
    final modes = rest.isEmpty ? ['light', 'dark'] : [rest.single as String];
    for (final mode in modes) {
      test('$mode: $fg on $bg ≥ $min', () {
        expect(_ratio(mode, fg, bg), greaterThanOrEqualTo(min));
      });
    }
  }

  // Pairs that fail alone and are only allowed with the navy contour
  // between them (or never): the rule must stay true, and the contour must
  // carry them.
  for (final rule
      in (_rules['contourRequired'] as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
    final [a as String, b as String] = rule['pair'] as List<dynamic>;
    final modes = rule['mode'] == null
        ? ['light', 'dark']
        : [rule['mode'] as String];
    for (final mode in modes) {
      if (rule['never'] == true) {
        test('$mode: $a on $b is never used: below 4.5', () {
          expect(_ratio(mode, a, b), lessThan(4.5));
        });
        continue;
      }
      final contour = rule['contour'] as String;
      test('$mode: $a next to $b needs the contour: alone < 3, '
          'with $contour ≥ 3 against both', () {
        expect(_ratio(mode, a, b), lessThan(3), reason: 'else drop the rule');
        expect(_ratio(mode, contour, a), greaterThanOrEqualTo(3));
        expect(_ratio(mode, contour, b), greaterThanOrEqualTo(3));
      });
    }
  }

  // The brief's table (job 52), re-measured: the lemon pairs.
  test('the lemon pairs measure as recorded in docs/DESIGN.md', () {
    final measured = {
      'L navy on yellow': _ratio('light', 'on-honey', 'honey'),
      'L muted on yellow': _ratio('light', 'text-muted', 'honey'),
      'L cobalt on yellow': _ratio('light', 'brand', 'honey'),
      'L yellow on cobalt hero': _ratio('light', 'honey', 'cobalt'),
      'L navy on honey-soft': _ratio('light', 'text', 'honey-soft'),
      'D text on yellow': _ratio('dark', 'on-honey', 'honey'),
      'D yellow on cobalt field': _ratio('dark', 'honey', 'cobalt'),
      'D yellow on surface': _ratio('dark', 'honey', 'surface'),
      'D yellow on raised': _ratio('dark', 'honey', 'surface-raised'),
      'D contour vs yellow': _ratio('dark', 'edge', 'honey'),
      'D honey-edge vs surface': _ratio('dark', 'honey-edge', 'surface'),
      'D text on honey-soft': _ratio('dark', 'text', 'honey-soft'),
    };
    final rounded = measured.map(
      (k, v) => MapEntry(k, (v * 100).round() / 100),
    );
    expect(rounded, {
      'L navy on yellow': 13.87,
      'L muted on yellow': 5.9,
      'L cobalt on yellow': 6.85,
      'L yellow on cobalt hero': 6.85,
      'L navy on honey-soft': 15.82,
      'D text on yellow': 14.57,
      'D yellow on cobalt field': 5.87,
      'D yellow on surface': 14.57,
      'D yellow on raised': 12.89,
      'D contour vs yellow': 15.72,
      'D honey-edge vs surface': 6.84,
      'D text on honey-soft': 11.85,
    });
  });
}
