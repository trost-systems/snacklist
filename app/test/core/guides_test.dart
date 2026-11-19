import 'dart:io';

import 'package:family_groceries/core/guides.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('German UI opens the German Siri guide', () {
    expect(
      siriGuideUrl('de').toString(),
      'https://snacklist.app/de/anleitungen/siri-kurzbefehl',
    );
  });

  test('any other UI language opens the English Siri guide', () {
    for (final code in ['en', 'fr']) {
      expect(
        siriGuideUrl(code).toString(),
        'https://snacklist.app/en/guides/siri-shortcut',
      );
    }
  });

  /// The site builds one page per Markdown file; a renamed slug would break
  /// the app's link without failing anything else.
  test('both guide pages exist in site/', () {
    for (final path in [
      '../site/content/guides/de/siri-kurzbefehl.md',
      '../site/content/guides/en/siri-shortcut.md',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
