import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
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
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../test/list/fake_repository.dart';
import '../test/list/memory_cache.dart';

/// Profile entrypoint for job 274's measurement of keystroke to stable rows
/// in the add sheet (`.github/workflows/add-sheet-timing.yml`, on an
/// Android emulator): the list screen with an in-memory server and a
/// 2,000-row household, the flags off, `input-stable-rows` only and
/// `on-device-catalog` on. Every prefix of [_lines] is typed through the
/// field's text input client at two typing speeds, [_rounds] times per
/// mode, the modes interleaved. Prints `[timing-table]` and
/// `[timing-sample]` lines (lengths and line numbers, never text), then
/// exits.
///
/// A plain binding, not integration_test's: its live test binding
/// schedules a new frame after every frame a pump did not ask for, so the
/// screen redraws without pause and each key's frame queues behind
/// redundant ones (the first emulator runs).
///
/// Per key: `log`, the app's own `[add-sheet timing]` time from the key to
/// the end of the frame with its rows (its post-frame callback); `rank`,
/// the device's time to make the rows; that frame's `build` and `raster`
/// (FrameTiming, the first frame built after the key) and `frame`, from
/// the key to its raster end: the rows' pixels.
Future<void> main() async {
  if (kReleaseMode) {
    throw StateError('add_sheet_timing_probe.dart is for profile builds.');
  }
  Timer(const Duration(minutes: 40), () {
    debugPrintSynchronously('[timing-error] timed out');
    exit(2);
  });
  final binding = WidgetsFlutterBinding.ensureInitialized();
  try {
    await _run(binding);
  } on Object catch (error, stack) {
    debugPrintSynchronously('[timing-error] $error\n$stack');
    exit(3);
  }
  exit(0);
}

Future<void> _run(WidgetsBinding binding) async {
  final timings = <FrameTiming>[];
  binding.addTimingsCallback(timings.addAll);
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    if (message != null && message.startsWith('[add-sheet timing]')) {
      logs.add(message);
    } else {
      original(message, wrapWidth: wrapWidth);
    }
  };

  final keys = <_Key>[];
  final idle = <int>[];
  for (var round = 0; round < _rounds; round++) {
    for (final cadence in _cadences) {
      for (final mode in _modes) {
        runApp(_app(mode));
        await _settle();
        for (final (line, text) in _lines.indexed) {
          await _tap(_field());
          await _settle();
          if (round == 0 && line == 0) {
            // Frames while the open sheet waits: the caret's blink only.
            final before = timings.length;
            await Future<void>.delayed(const Duration(seconds: 2));
            idle.add(timings.length - before);
          }
          final editable = _editable();
          for (var len = 1; len <= text.length; len++) {
            final typed = text.substring(0, len);
            final logged = logs.length;
            final at = Timeline.now;
            editable.updateEditingValue(
              TextEditingValue(
                text: typed,
                selection: TextSelection.collapsed(offset: len),
              ),
            );
            await Future<void>.delayed(cadence);
            // A space changes no rows; the sheet logs nothing for it.
            if (typed.endsWith(' ')) {
              continue;
            }
            keys.add((
              mode: mode.name,
              cadence: cadence.inMilliseconds,
              line: line,
              len: typed.trim().length,
              at: at,
              logs: logs.sublist(logged),
            ));
          }
          await Future<void>.delayed(_pause);
          _field().read<AddSheetCubit>().dismiss();
          await _settle();
        }
      }
    }
  }
  // FrameTimings arrive in batches; let the last one in.
  await Future<void>.delayed(const Duration(seconds: 2));
  binding.removeTimingsCallback(timings.addAll);
  debugPrint = original;

  final samples = [
    for (final (i, key) in keys.indexed)
      _sample(key, keys.elementAtOrNull(i + 1)?.at, timings),
  ];
  _report(samples, idle)
      .split('\n')
      .forEach((line) => debugPrintSynchronously('[timing-table] $line'));
  for (final s in samples) {
    debugPrintSynchronously('[timing-sample] ${s.csv}');
  }
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
/// every key).
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

  /// The frame's build end minus the log's time: near zero (the log is
  /// that frame's post-frame callback) when the frame is the right one.
  required final double? skew,
}) {
  String get csv =>
      '$mode,$cadence,$line,$len,$log,$rank,$frame,$build,$raster,$skew';
}

final _rowsLine = RegExp(
  r'len=(\d+) (?:rows rank=([\d.]+) ms|cached) ([\d.]+) ms$',
);

_Sample _sample(_Key key, int? next, List<FrameTiming> timings) {
  double? log;
  double? rank;
  for (final line in key.logs) {
    if (_rowsLine.firstMatch(line) case final m?) {
      rank = m.group(2) == null ? null : double.parse(m.group(2)!);
      log = double.parse(m.group(3)!);
    }
  }
  final frame = timings.where((f) {
    final start = f.timestampInMicroseconds(FramePhase.buildStart);
    return start >= key.at && (next == null || start < next);
  }).firstOrNull;
  double ms(int us) => us / 1000;
  int at(FramePhase phase) => frame!.timestampInMicroseconds(phase);
  return _Sample(
    mode: key.mode,
    cadence: key.cadence,
    line: key.line,
    len: key.len,
    log: log,
    rank: rank,
    frame: frame == null ? null : ms(at(FramePhase.rasterFinish) - key.at),
    build: frame == null ? null : ms(frame.buildDuration.inMicroseconds),
    raster: frame == null ? null : ms(frame.rasterDuration.inMicroseconds),
    skew: frame == null || log == null
        ? null
        : ms(at(FramePhase.buildFinish) - key.at) - log,
  );
}

String _report(List<_Sample> samples, List<int> idle) {
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
          '| ${cadence.inMilliseconds} | ${mode.name} | $len '
          '| ${group.length} '
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
  out
    ..writeln()
    ..writeln(
      'Frame check, |build end - log| p50 | p95 | max (ms): '
      '${stats(samples.map((s) => s.skew?.abs()))}',
    )
    ..writeln('Frames in 2 s with the sheet open and idle: ${idle.join(', ')}');
  double worst(_Sample s) => [s.rank ?? 0, s.build ?? 0].reduce(math.max);
  final slow = [
    for (final s in samples)
      if (worst(s) > 16) s,
  ]..sort((a, b) => worst(b).compareTo(worst(a)));
  out.writeln(
    'Keys with rank or build over 16 ms: ${slow.length} (the worst 40)',
  );
  for (final s in slow.take(40)) {
    out.writeln(
      '- gap ${s.cadence} ${s.mode} line ${s.line} len ${s.len}: '
      'log ${s.log} rank ${s.rank} build ${s.build} raster ${s.raster}',
    );
  }
  return out.toString();
}

Widget _app(_Mode mode) {
  final repo = FakeRepository()
    ..categories = _categories
    ..householdIndex = _household;
  return MaterialApp(
    key: UniqueKey(),
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
  );
}

Element? _find(bool Function(Element) test) {
  Element? found;
  void visit(Element e) {
    if (found != null) {
      return;
    }
    if (test(e)) {
      found = e;
      return;
    }
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

Element _field() =>
    _find((e) => e.widget.key == const ValueKey('add-item-field')) ??
    (throw StateError('no add field'));

EditableTextState _editable() {
  EditableTextState? state;
  void visit(Element e) {
    if (e is StatefulElement && e.state is EditableTextState) {
      state = e.state as EditableTextState;
    } else if (state == null) {
      e.visitChildElements(visit);
    }
  }

  _field().visitChildElements(visit);
  return state ?? (throw StateError('no EditableText in the add field'));
}

var _pointer = 0;

Future<void> _tap(Element target) async {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final box = target.renderObject! as RenderBox;
  final at = box.localToGlobal(box.size.center(Offset.zero));
  final pointer = ++_pointer;
  Duration now() => Duration(microseconds: Timeline.now);
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
      timeStamp: now(),
      position: at,
      viewId: view.viewId,
      pointer: pointer,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 50));
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
      timeStamp: now(),
      position: at,
      viewId: view.viewId,
      pointer: pointer,
    ),
  );
}

/// Until no frame is scheduled or animating for 100 ms.
Future<void> _settle() async {
  final binding = SchedulerBinding.instance;
  var still = 0;
  final watch = Stopwatch()..start();
  while (still < 5) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final busy =
        binding.hasScheduledFrame ||
        binding.transientCallbackCount > 0 ||
        binding.schedulerPhase != SchedulerPhase.idle;
    still = busy ? 0 : still + 1;
    if (watch.elapsed > const Duration(seconds: 20)) {
      throw StateError('never settled');
    }
  }
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
