import 'dart:io';

import 'package:family_groceries/analytics/events.dart';
import 'package:flutter_test/flutter_test.dart';

/// Privacy policy §9 is by category (Legal R9, 2026-11-26). Every allow-listed
/// event key must have a row in the Event catalog table of docs/ANALYTICS.md
/// with a Policy category (or "none: never sent").
void main() {
  late Map<String, String> table;

  setUpAll(() {
    table = policyCategoryByEvent();
  });

  test('every eventCatalog key has a policy category row', () {
    final missing = [
      for (final event in eventCatalog.keys)
        if (!table.containsKey(event)) event,
    ];
    expect(
      missing,
      isEmpty,
      reason: 'add a Policy category row in docs/ANALYTICS.md',
    );
  });

  test('every serverEventCatalog key has a policy category row', () {
    final missing = [
      for (final event in serverEventCatalogKeys())
        if (!table.containsKey(event)) event,
    ];
    expect(
      missing,
      isEmpty,
      reason: 'add a Policy category row in docs/ANALYTICS.md',
    );
  });

  test(r'$exception has a policy category row', () {
    expect(table[r'$exception'], isNotNull);
    expect(table[r'$exception'], contains('6'));
  });

  test('scan_started and off_miss are catalogued as never sent', () {
    expect(table['scan_started'], 'none: never sent');
    expect(table['off_miss'], 'none: never sent');
  });

  test('item_categorized is policy category 3', () {
    expect(table['item_categorized'], '3');
  });
}

/// Event name to the Policy category cell in the Event catalog table.
Map<String, String> policyCategoryByEvent() {
  final doc = File('../docs/ANALYTICS.md').readAsStringSync();
  final start = doc.indexOf('| Event | When | Properties | Policy category |');
  if (start < 0) {
    throw StateError('Event catalog table has no Policy category column');
  }
  final afterHeader = doc.indexOf('\n', doc.indexOf('\n', start) + 1) + 1;
  final map = <String, String>{};
  for (final line in doc.substring(afterHeader).split('\n')) {
    if (!line.startsWith('|')) {
      break;
    }
    final cells = [
      for (final cell in line.split('|'))
        if (cell.trim().isNotEmpty) cell.trim(),
    ];
    // Event, When, Properties, Policy category.
    if (cells.length < 4) {
      continue;
    }
    final category = cells[3];
    final events = RegExp('`([^`]+)`')
        .allMatches(cells[0])
        .map((m) => m.group(1)!);
    for (final event in events) {
      map[event] = category;
    }
  }
  return map;
}

/// Keys of `serverEventCatalog` in supabase/functions/_shared/telemetry.ts.
Set<String> serverEventCatalogKeys() {
  final src = File('../supabase/functions/_shared/telemetry.ts')
      .readAsStringSync();
  final start = src.indexOf('export const serverEventCatalog');
  if (start < 0) {
    throw StateError('serverEventCatalog not found in telemetry.ts');
  }
  final open = src.indexOf('{', start);
  final close = src.indexOf('\n};', open);
  final body = src.substring(open, close);
  final pattern = RegExp("^  '([a-z0-9_]+)':", multiLine: true);
  return {for (final m in pattern.allMatches(body)) m.group(1)!};
}
