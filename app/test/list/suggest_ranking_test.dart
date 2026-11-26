import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'suggest_fixture/fixture.dart';

void main() {
  test('the frozen 40 queries rank the 5,000 usuals as before', () {
    final expected =
        (jsonDecode(
          File('test/list/suggest_fixture/expected.json').readAsStringSync(),
        ) as Map<String, Object?>).map(
          (query, names) => MapEntry(query, [
            for (final name in names! as List<Object?>) name! as String,
          ]),
        );
    expect(SuggestFixture.load().ranked(), expected);
  });

  test('and every match below the top 5 keeps its place', () {
    final ranked = SuggestFixture.load().ranked(limit: 5000);
    final digest = sha256.convert(utf8.encode(jsonEncode(ranked))).toString();
    expect(
      (
        count: ranked.values.fold<int>(0, (n, names) => n + names.length),
        sha256: digest,
      ),
      (count: _allMatches, sha256: _allMatchesSha256),
    );
  });

  test('a smaller limit is the top of the full ranking', () {
    final fixture = SuggestFixture.load();
    final all = fixture.ranked(limit: 5000);
    for (var limit = 1; limit <= 20; limit++) {
      expect(fixture.ranked(limit: limit), {
        for (final MapEntry(:key, :value) in all.entries)
          key: value.take(limit).toList(),
      }, reason: 'limit $limit');
    }
  });
}

/// Every match of the 40 queries in order (`limit: 5000`), as 698ebeba ranks.
const _allMatches = 4520;
const _allMatchesSha256 =
    'b5888b0e48307ed989a116f10812883385a35e7768e1ce82936b9af22aa1142d';
