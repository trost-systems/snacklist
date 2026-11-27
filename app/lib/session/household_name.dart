import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// The longest household name, in characters (code points, as Postgres'
/// char_length counts them).
const maxHouseholdName = 80;

/// Whether [name] is a household name the server takes: 1 to 80
/// characters once trimmed.
bool validHouseholdName(String name) {
  final length = name.trim().runes.length;
  return length >= 1 && length <= maxHouseholdName;
}

/// Keeps a household name field within [maxHouseholdName] code points, the
/// server's count, cutting whole characters. A field's maxLength counts
/// characters, and an emoji can be several code points: a name the field
/// took and its counter showed as fitting was refused.
class const HouseholdNameLimit() extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maxHouseholdName) {
      return newValue;
    }
    var runes = 0;
    final kept = newValue.text.characters
        .takeWhile((c) => (runes += c.runes.length) <= maxHouseholdName)
        .string;
    return TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: kept.length),
    );
  }
}
