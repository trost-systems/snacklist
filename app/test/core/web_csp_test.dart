import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/core/environment.dart';
import 'package:flutter_test/flutter_test.dart';

/// The web app fetches the item icon table from its default host (job 147).
/// A host missing from vercel.json's connect-src is blocked in the browser
/// without an error the app can show (job 174 moved it to snacklist.app).
void main() {
  test("vercel.json's connect-src lets the web app fetch the item icons", () {
    final vercel = jsonDecode(
      File('../vercel.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final csp = [
      for (final rule
          in (vercel['headers']! as List).cast<Map<String, Object?>>())
        for (final header
            in (rule['headers']! as List).cast<Map<String, Object?>>())
          if (header['key'] == 'Content-Security-Policy')
            header['value']! as String,
    ];
    expect(csp, isNotEmpty);
    final origin = Uri.parse(Environment.itemIconsUrl).origin;
    for (final policy in csp) {
      final connect = policy
          .split(';')
          .map((d) => d.trim())
          .firstWhere((d) => d.startsWith('connect-src'));
      expect(connect.split(' '), contains(origin), reason: policy);
    }
  });
}
