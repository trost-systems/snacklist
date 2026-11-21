import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('probe335 app')))));
  final tmp = Directory.systemTemp.path;
  final caseFile = File('$tmp/case.txt');
  if (!caseFile.existsSync()) return;
  final parts = caseFile.readAsStringSync().trim().split('|');
  caseFile.deleteSync();
  final id = parts[0];
  final op = parts[1];
  final uri = Uri.parse(parts[2]);
  await Future<void>.delayed(const Duration(seconds: 2));
  final out = <String, Object?>{'id': id, 'op': op, 'uri': uri.toString()};
  final sw = Stopwatch()..start();
  try {
    out['result'] = switch (op) {
      'externalApplication' => await launchUrl(uri, mode: LaunchMode.externalApplication),
      'externalNonBrowserApplication' => await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication),
      'platformDefault' => await launchUrl(uri),
      'canLaunchUrl' => await canLaunchUrl(uri),
      _ => throw ArgumentError(op),
    };
  } on Object catch (e) {
    out['error'] = '$e';
  }
  out['ms'] = sw.elapsedMilliseconds;
  File('$tmp/result_$id.json').writeAsStringSync(jsonEncode(out));
}
