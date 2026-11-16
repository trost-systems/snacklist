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
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/list/fake_repository.dart';
import '../test/list/memory_cache.dart';

/// Job 274: keystroke to stable rows in the add sheet on a real device, the
/// flags off, `input-stable-rows` only and `on-device-catalog` on. Every
/// prefix of [_lines] is typed with real frames, [_rounds] times per mode,
/// the modes interleaved. Logs lengths and line numbers, never text.
///
/// Per key: `log`, the app's own `[add-sheet timing]` time from the key to
/// the end of the frame with its rows (build and layout, not raster);
/// `rank`, the device's time to make the rows; `frame`, from the key to the
/// end of raster of the first frame built after it (FrameTiming).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('add sheet: keystroke to rows', (tester) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final frames = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(frames.addAll);
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
            await binding.delayed(_cadence);
            // A space changes no rows; the sheet logs nothing for it.
            if (text[len - 1] == ' ') {
              continue;
            }
            keys.add((
              mode: mode.name,
              round: round,
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
    // FrameTimings arrive in batches; let the last one in.
    await binding.delayed(const Duration(seconds: 2));
    SchedulerBinding.instance.removeTimingsCallback(frames.addAll);

    final samples = [
      for (final (i, key) in keys.indexed)
        _sample(key, keys.elementAtOrNull(i + 1)?.at, frames),
    ];
    final report = _report(samples);
    debugPrint = original;
    report.split('\n').forEach(debugPrintSynchronously);
    binding.reportData = {
      'table': report,
      'samples': [for (final s in samples) s.toJson()],
    };
  });
}

/// Every prefix of these is one key: lines from the parity fixture
/// (supabase/tests/suggest_parity.json), 155 keys in all.
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

/// A quick typist's gap between keys; under the sheet's 120 ms typing
/// pause, so the server is asked once per line.
const _cadence = Duration(milliseconds: 100);

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
  int round,
  int line,
  int len,
  int at,
  List<String> logs,
});

final class _Sample({
  required final String mode,
  required final int line,
  required final int len,
  required final double? log,
  required final double? rank,
  required final double? frame,
  required final double? build,
  required final double? raster,

  /// The matched frame's build end minus the logged time: near zero when
  /// Timeline.now and FrameTiming share a clock.
  required final double? skew,
}) {
  Map<String, Object?> toJson() => {
    'mode': mode,
    'line': line,
    'len': len,
    'log': log,
    'rank': rank,
    'frame': frame,
    'build': build,
    'raster': raster,
    'skew': skew,
  };
}

final _rowsLine = RegExp(
  r'len=(\d+) (?:rows rank=([\d.]+) ms|cached) ([\d.]+) ms$',
);

_Sample _sample(_Key key, int? next, List<FrameTiming> frames) {
  double? log;
  double? rank;
  for (final line in key.logs) {
    if (_rowsLine.firstMatch(line) case final m?) {
      rank = m.group(2) == null ? null : double.parse(m.group(2)!);
      log = double.parse(m.group(3)!);
    }
  }
  // The frame whose post-frame callback logged: the one whose build ended
  // nearest the logged time; without a log, the first after the key.
  final after = [
    for (final f in frames)
      if (f.timestampInMicroseconds(FramePhase.buildStart) >= key.at &&
          (next == null ||
              f.timestampInMicroseconds(FramePhase.buildStart) < next))
        f,
  ];
  final logged = log == null ? null : key.at + (log * 1000).round();
  int gap(FrameTiming f) =>
      (f.timestampInMicroseconds(FramePhase.buildFinish) - logged!).abs();
  final frame = logged == null || after.isEmpty
      ? after.firstOrNull
      : after.reduce((a, b) => gap(a) <= gap(b) ? a : b);
  double ms(int us) => us / 1000;
  return _Sample(
    mode: key.mode,
    line: key.line,
    len: key.len,
    log: log,
    rank: rank,
    frame: frame == null
        ? null
        : ms(frame.timestampInMicroseconds(FramePhase.rasterFinish) - key.at),
    build: frame == null ? null : ms(frame.buildDuration.inMicroseconds),
    raster: frame == null ? null : ms(frame.rasterDuration.inMicroseconds),
    skew: frame == null || logged == null
        ? null
        : ms(frame.timestampInMicroseconds(FramePhase.buildFinish) - logged),
  );
}

String _report(List<_Sample> samples) {
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
      '| mode | len | keys | no log | log p50 | p95 | max '
      '| rank p50 | p95 | max | frame p50 | p95 | max '
      '| build p50 | p95 | max | raster max |',
    )
    ..writeln('|---${'|---' * 16}|');
  for (final mode in _modes) {
    for (final len in ['1', '2', '3+', 'all']) {
      final group = [
        for (final s in samples)
          if (s.mode == mode.name && (len == 'all' || bucket(s.len) == len)) s,
      ];
      out.writeln(
        '| ${mode.name} | $len | ${group.length} '
        '| ${group.where((s) => s.log == null).length} '
        '| ${stats(group.map((s) => s.log))} '
        '| ${stats(group.map((s) => s.rank))} '
        '| ${stats(group.map((s) => s.frame))} '
        '| ${stats(group.map((s) => s.build))} '
        '| ${stats(group.map((s) => s.raster)).split(' | ').last} |',
      );
    }
  }
  out.writeln(
    '\nClock check, build end minus log time p50 | p95 | max (ms): '
    '${stats(samples.map((s) => s.skew?.abs()))}',
  );
  double worst(_Sample s) =>
      [s.rank ?? 0, s.build ?? 0, s.raster ?? 0].reduce(math.max);
  final slow = [
    for (final s in samples)
      if (worst(s) > 16) s,
  ]..sort((a, b) => worst(b).compareTo(worst(a)));
  out.writeln(
    '\nKeys with rank, build or raster over 16 ms: ${slow.length} '
    '(the worst 40)',
  );
  for (final s in slow.take(40)) {
    out.writeln(
      '- ${s.mode} line ${s.line} len ${s.len}: log ${s.log} rank ${s.rank} '
      'build ${s.build} raster ${s.raster} '
      'frame ${s.frame?.toStringAsFixed(1)}',
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
