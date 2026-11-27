import 'package:family_groceries/session/household_name.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue limit(String text) => const HouseholdNameLimit()
    .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));

void main() {
  const family = '👨‍👩‍👧‍👦';

  test('a name within 80 code points stays as typed', () {
    final name = '${'A' * 73}$family';
    expect(name.runes.length, 80);
    expect(limit(name).text, name);
    expect(validHouseholdName(name), isTrue);
  });

  test('past 80 code points whole characters go, never half an emoji', () {
    final cut = limit('${'A' * 74}$family');
    expect(cut.text, 'A' * 74);
    expect(cut.selection, const TextSelection.collapsed(offset: 74));
    expect(validHouseholdName(cut.text), isTrue);
    expect(limit('${'A' * 79}é🙂').text, '${'A' * 79}é');
  });
}
