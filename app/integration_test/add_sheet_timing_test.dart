import 'dart:developer' show Timeline;
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/catalog/catalog_index.g.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/list/fake_repository.dart';
import '../test/list/memory_cache.dart';

/// Job 274: keystroke to stable rows in the add sheet on a real device, the
/// flags off, `input-stable-rows` only and `on-device-catalog` on. Every
/// prefix of [_lines] is typed with real frames at two typing speeds,
/// [_rounds] times per mode, the modes interleaved. Logs lengths and line
/// numbers, never text.
///
/// Per key: `log`, the app's own `[add-sheet timing]` time from the key to
/// the end of the frame with its rows (its post-frame callback); `rank`,
/// the device's time to make the rows; that frame's `build` and `raster`
/// (FrameTiming) and `frame`, `log` plus the frame's time from build end to
/// raster end: the key to the rows' pixels.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('add sheet: keystroke to rows', (tester) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final timings = <FrameTiming>[];
    binding.addTimingsCallback(timings.addAll);
    // Each frame's vsync time (FrameTiming's clock) and when it built
    // (Timeline's): ties the app's log to the FrameTiming of its frame.
    final built = <_Built>[];
    binding.addPersistentFrameCallback((_) {
      built.add((
        vsync: binding.currentSystemFrameTimeStamp.inMicroseconds,
        now: Timeline.now,
      ));
    });
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null && message.startsWith('[add-sheet timing]')) {
        logs.add(message);
      } else {
        original(message, wrapWidth: wrapWidth);
      }
    };
    addTearDown(() => debugPrint = original);

    final keys = <_Key>[];
    for (var round = 0; round < _rounds; round++) {
      for (final cadence in _cadences) {
        for (final mode in _modes) {
          await _pumpList(tester, mode);
          for (final (line, text) in _lines.indexed) {
            await tester.tap(_field());
            await tester.pumpAndSettle();
            for (var len = 1; len <= text.length; len++) {
              final logged = logs.length;
              final at = Timeline.now;
              await tester.enterText(_field(), text.substring(0, len));
              await tester.pump();
              await binding.delayed(cadence);
              // A space changes no rows; the sheet logs nothing for it.
              if (text[len - 1] == ' ') {
                continue;
              }
              keys.add((
                mode: mode.name,
                cadence: cadence.inMilliseconds,
                line: line,
                len: text.substring(0, len).trim().length,
                at: at,
                logs: logs.sublist(logged),
              ));
            }
            await binding.delayed(_pause);
            tester.element(_field()).read<AddSheetCubit>().dismiss();
            await tester.pumpAndSettle();
          }
        }
      }
    }
    // FrameTimings arrive in batches; let the last one in.
    await binding.delayed(const Duration(seconds: 2));
    binding.removeTimingsCallback(timings.addAll);

    final byVsync = {
      for (final f in timings)
        f.timestampInMicroseconds(FramePhase.vsyncStart): f,
    };
    final samples = [for (final key in keys) _sample(key, built, byVsync)];
    final report = _report(
      samples,
      built: built.length,
      timed: built.where((b) => byVsync.containsKey(b.vsync)).length,
    );
    debugPrint = original;
    report.split('\n').forEach(debugPrintSynchronously);
    binding.reportData = {
      'table': report,
      'samples': [for (final s in samples) s.toJson()],
    };
  });
}

/// Every prefix of these is one key, spaces aside: lines from the parity
/// fixture (supabase/tests/suggest_parity.json), 138 keys.
const _lines = [
  'Milch laktosefrei',
  'Bio Eier',
  'Joghurt Erdbeere 4er Pack',
  'Klopapier 16 Rollen',
  'Kaffee Tchibo ganze Bohne',
  '2 kg Kartoffeln festkochend',
  'Windeln Größe 4 Big Pack',
  'Hafermlich',
];

const _rounds = 3;

/// The gap between keys: a quick typist's, under the sheet's 120 ms typing
/// pause (the server is asked once per line), and a slow one's (asked on
/// every key, and the frames of one key are done before the next).
const _cadences = [Duration(milliseconds: 100), Duration(milliseconds: 300)];

/// After a line: the server's answer comes in.
const _pause = Duration(milliseconds: 400);

typedef _Mode = ({String name, Set<String> flags});

const List<_Mode> _modes = [
  (name: 'off', flags: {}),
  (name: 'stable', flags: {inputStableRowsFlag}),
  (name: 'catalog', flags: {onDeviceCatalogFlag}),
];

typedef _Key = ({
  String mode,
  int cadence,
  int line,
  int len,
  int at,
  List<String> logs,
});

typedef _Built = ({int vsync, int now});

final class _Sample({
  required final String mode,
  required final int cadence,
  required final int line,
  required final int len,
  required final double? log,
  required final double? rank,
  required final double? frame,
  required final double? build,
  required final double? raster,
}) {
  Map<String, Object?> toJson() => {
    'mode': mode,
    'cadence': cadence,
    'line': line,
    'len': len,
    'log': log,
    'rank': rank,
    'frame': frame,
    'build': build,
    'raster': raster,
  };
}

final _rowsLine = RegExp(
  r'len=(\d+) (?:rows rank=([\d.]+) ms|cached) ([\d.]+) ms$',
);

_Sample _sample(_Key key, List<_Built> built, Map<int, FrameTiming> byVsync) {
  double? log;
  double? rank;
  for (final line in key.logs) {
    if (_rowsLine.firstMatch(line) case final m?) {
      rank = m.group(2) == null ? null : double.parse(m.group(2)!);
      log = double.parse(m.group(3)!);
    }
  }
  // The frame that logged: the last one built between the key and the log.
  final logged = log == null ? null : key.at + (log * 1000).round();
  final frame = logged == null
      ? null
      : built
            .where((b) => b.now >= key.at && b.now <= logged)
            .map((b) => byVsync[b.vsync])
            .lastOrNull;
  double ms(int us) => us / 1000;
  return _Sample(
    mode: key.mode,
    cadence: key.cadence,
    line: key.line,
    len: key.len,
    log: log,
    rank: rank,
    frame: frame == null || log == null
        ? null
        : log +
              ms(
                frame.timestampInMicroseconds(FramePhase.rasterFinish) -
                    frame.timestampInMicroseconds(FramePhase.buildFinish),
              ),
    build: frame == null ? null : ms(frame.buildDuration.inMicroseconds),
    raster: frame == null ? null : ms(frame.rasterDuration.inMicroseconds),
  );
}

String _report(
  List<_Sample> samples, {
  required int built,
  required int timed,
}) {
  String bucket(int len) => len >= 3 ? '3+' : '$len';
  String stats(Iterable<double?> values) {
    final sorted = [...values.nonNulls]..sort();
    if (sorted.isEmpty) {
      return '- | - | -';
    }
    double at(double q) => sorted[((sorted.length - 1) * q).round()];
    String f(double v) => v.toStringAsFixed(1);
    return '${f(at(0.5))} | ${f(at(0.95))} | ${f(sorted.last)}';
  }

  final out = StringBuffer()
    ..writeln(
      '| gap ms | mode | len | keys | no log | no frame '
      '| log p50 | p95 | max | rank p50 | p95 | max | frame p50 | p95 | max '
      '| build p50 | p95 | max | raster p50 | p95 | max |',
    )
    ..writeln('|---${'|---' * 20}|');
  for (final cadence in _cadences) {
    for (final mode in _modes) {
      for (final len in ['1', '2', '3+', 'all']) {
        final group = [
          for (final s in samples)
            if (s.cadence == cadence.inMilliseconds &&
                s.mode == mode.name &&
                (len == 'all' || bucket(s.len) == len))
              s,
        ];
        out.writeln(
          '| ${cadence.inMilliseconds} | ${mode.name} | $len | ${group.length} '
          '| ${group.where((s) => s.log == null).length} '
          '| ${group.where((s) => s.frame == null).length} '
          '| ${stats(group.map((s) => s.log))} '
          '| ${stats(group.map((s) => s.rank))} '
          '| ${stats(group.map((s) => s.frame))} '
          '| ${stats(group.map((s) => s.build))} '
          '| ${stats(group.map((s) => s.raster))} |',
        );
      }
    }
  }
  out.writeln(
    '\nFrames built: $built, with a FrameTiming of the same vsync: $timed',
  );
  double worst(_Sample s) => [s.rank ?? 0, s.build ?? 0].reduce(math.max);
  final slow = [
    for (final s in samples)
      if (worst(s) > 16) s,
  ]..sort((a, b) => worst(b).compareTo(worst(a)));
  out.writeln(
    '\nKeys with rank or build over 16 ms: ${slow.length} (the worst 40)',
  );
  for (final s in slow.take(40)) {
    out.writeln(
      '- gap ${s.cadence} ${s.mode} line ${s.line} len ${s.len}: '
      'log ${s.log} rank ${s.rank} build ${s.build} raster ${s.raster}',
    );
  }
  return out.toString();
}

Finder _field() => find.byKey(const ValueKey('add-item-field'));

Future<void> _pumpList(WidgetTester tester, _Mode mode) async {
  final repo = FakeRepository()
    ..categories = _categories
    ..householdIndex = _household;
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey(mode.name),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => Flags(forced: mode.flags)),
          BlocProvider(
            create: (_) => ListCubit(
              repo,
              MemoryListCache(),
              userId: 'peter',
              householdIndex: () => true,
            )..start(),
          ),
        ],
        child: const ShoppingList(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _hardware = {
  'building',
  'electrical',
  'fasteners',
  'garden',
  'paint',
  'plumbing',
  'tools',
};

final _categories = [
  for (final (i, seed) in const [
    'bakery',
    'chilled',
    'drinks',
    'drugstore',
    'frozen',
    'household',
    'meat',
    'other',
    'pantry',
    'produce',
    'sweets',
  ].indexed)
    Category(id: seed, name: seed, sortOrder: i, seedKey: seed),
];

/// A heavy household: 2,000 history rows over a year, made from the
/// bundled catalog's grocery terms, some with a brand, details and a
/// quantity, plus the parity fixture's taught brands.
final _household = () {
  final terms = [
    for (final (term, _, category) in catalogTerms)
      if (!_hardware.contains(category)) term,
  ];
  final brands = [for (final (_, brand, _, _) in catalogBrands) brand];
  const details = ['bio', 'laktosefrei', '1,5 %', 'groß', 'klein', 'light'];
  final now = DateTime.utc(2026, 11, 16, 12);
  final history = <HistoryRow>[];
  for (var i = 0; history.length < 2000; i++) {
    final term = terms[i % terms.length];
    final name = term[0].toUpperCase() + term.substring(1);
    final second = i >= terms.length;
    history.add((
      name: name,
      brand: i % 7 == 0 ? brands[i % brands.length] : null,
      properties: second || i % 5 == 0 ? details[i % details.length] : null,
      quantity: i % 3 == 0 ? '${i % 4 + 1}' : null,
      normalizedName: normalizeItemName(name),
      at: now.subtract(Duration(days: (i * 37) % 365, hours: i % 24)),
    ));
  }
  return HouseholdIndex(
    history: history,
    brands: const [
      (brand: 'Bergbauer', key: 'bergbaur'),
      (brand: 'Hofgut Sonnenschein', key: 'hofgutsonnenschein'),
      (brand: 'Zimtzauber', key: 'zimtzauber'),
    ],
    unserved: const [..._hardware],
    known: const ['gluehwein', 'grillkohle'],
  );
}();
