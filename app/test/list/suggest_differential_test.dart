import 'dart:math';

import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// `suggestUsuals` against the plain ranking it replaced (698ebeba, inlined
/// below as `_reference*`), on seeded random catalogs with blanks, hyphens,
/// tabs, umlauts, duplicates and items on the list.
void main() {
  test('ranks random catalogs as the plain ranking does', () {
    final random = Random(131);
    const letters = 'aabeeilmnorstuchkäöüßAÖ -\t ';
    String text(int most) => String.fromCharCodes([
      for (var i = random.nextInt(most); i > 0; i--)
        letters.codeUnitAt(random.nextInt(letters.length)),
    ]);
    final at = DateTime.utc(2026, 11);
    for (var round = 0; round < 400; round++) {
      final names = [for (var i = 0; i < 80; i++) text(14)];
      final usuals = [
        for (var i = 0; i < 120; i++)
          Usual(name: names[random.nextInt(names.length)], due: false),
      ];
      final visible = [
        for (var i = 0; i < 6; i++)
          Item(
            id: '$i',
            name: names[random.nextInt(names.length)],
            status: ItemStatus.values[random.nextInt(ItemStatus.values.length)],
            createdAt: at,
            updatedAt: at,
          ),
      ];
      for (var query = 0; query < 10; query++) {
        final typed = random.nextBool()
            ? text(7)
            : names[random.nextInt(names.length)];
        final limit = random.nextInt(9);
        final expected = _referenceSuggest(usuals, visible, typed, limit);
        for (final list in [
          usuals,
          usuals,
          [...usuals]..shuffle(random),
        ]) {
          expect(
            suggestUsuals(list, visible, typed, limit: limit),
            orderedEquals(
              identical(list, usuals)
                  ? expected
                  : _referenceSuggest(list, visible, typed, limit),
            ),
            reason: 'round $round, ${typed.codeUnits}, limit $limit',
          );
        }
      }
    }
  });

  test('matches pairs as the plain matcher does', () {
    final random = Random(131);
    const letters = 'abeilmnorst -';
    String text(int most) => String.fromCharCodes([
      for (var i = random.nextInt(most); i > 0; i--)
        letters.codeUnitAt(random.nextInt(letters.length)),
    ]);
    for (var i = 0; i < 100000; i++) {
      final (typed, name) = (text(8), text(16));
      if (typed.isNotEmpty) {
        expect(
          suggestionMatch(typed, name),
          _referenceMatch(typed, name),
          reason: '"$typed" in "$name"',
        );
      }
    }
  });
}

List<Usual> _referenceSuggest(
  List<Usual> usuals,
  Iterable<Item> visible,
  String text,
  int limit,
) {
  final typed = foldName(text);
  if (typed.isEmpty) {
    return const [];
  }
  final active = {
    for (final item in visible)
      if (item.status == ItemStatus.active) item.name.toLowerCase(),
  };
  final ranked = [
    for (final (order, usual)
        in usuals.where((u) => !active.contains(u.name.toLowerCase())).indexed)
      if (_referenceMatch(typed, foldName(usual.name)) case final rank?)
        (rank, order, usual),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return [for (final (_, _, usual) in ranked.take(limit)) usual];
}

int? _referenceMatch(String typed, String name) {
  if (name == typed) {
    return 0;
  }
  if (name.startsWith(typed)) {
    return 1;
  }
  final words = name.split(RegExp('[ -]+'));
  if (words.any((w) => w.startsWith(typed))) {
    return 2;
  }
  if (typed.length < 3) {
    return null;
  }
  if (typed.length >= 4 && name.contains(typed)) {
    return 3;
  }
  final most = typed.length < 6 ? 1 : 2;
  for (final word in {name, ...words}) {
    if (word.isNotEmpty &&
        word[0] == typed[0] &&
        (word.length - typed.length).abs() <= most &&
        _referenceDistance(typed, word) <= most) {
      return 4;
    }
  }
  return null;
}

int _referenceDistance(String a, String b) {
  var previous = [for (var j = 0; j <= b.length; j++) j];
  for (var i = 1; i <= a.length; i++) {
    final current = [i];
    for (var j = 1; j <= b.length; j++) {
      current.add(
        min(
          min(previous[j], current[j - 1]) + 1,
          previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        ),
      );
    }
    previous = current;
  }
  return previous.last;
}
