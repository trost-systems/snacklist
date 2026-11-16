import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/catalog_index.g.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart'
    show debugProfileLayoutsEnabled, debugProfilePaintsEnabled;
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../test/list/fake_repository.dart';
import '../test/list/memory_cache.dart';
import 'timeline_profile.dart';

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
///
/// Then, not in the table: `[timing-cpu]`, the UI isolate's CPU samples
/// from each key to its frame's build end, by function, per mode
/// ([_cpuRounds]); and, on request, `[timing-profile]`, the VM timeline
/// with every build, layout and paint ([_profileRounds]). The round
/// counts come from the entrypoint's arguments (`flutter run
/// --dart-entrypoint-args=--rounds=1`, or after the desktop binary).
Future<void> main(List<String> args) async {
  _args = args;
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
        keys.addAll(
          await _typeLines(mode, cadence, logs, (line) async {
            if (round == 0 && line == 0) {
              // Frames while the open sheet waits: the caret's blink only.
              final before = timings.length;
              await Future<void>.delayed(const Duration(seconds: 2));
              idle.add(timings.length - before);
            }
          }),
        );
      }
    }
  }
  if (_cpuRounds > 0) {
    await _cpuProfile(timings, logs);
  }
  if (_profileRounds > 0) {
    await _profile(binding, timings, logs);
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

var _args = const <String>[];

/// Rounds per mode and typing speed.
final _rounds = _setting('rounds', 3);

/// Rounds after the measured ones that record the VM timeline with every
/// build, layout and paint as an event (slower: not in the table), for the
/// `[timing-profile]` lines: where a key's frame spends its time.
final _profileRounds = _setting('profile-rounds', 0);

/// Rounds that sample the UI isolate's CPU (every 100 us), for the
/// `[timing-cpu]` lines: the functions a key's frame and its ranking spend
/// their time in, per mode.
final _cpuRounds = _setting('cpu-rounds', 1);

/// `--<name>=<n>` among the arguments, else [fallback].
int _setting(String name, int fallback) {
  for (final arg in _args) {
    if (arg.startsWith('--$name=')) {
      return int.parse(arg.substring(name.length + 3));
    }
  }
  return fallback;
}

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

  /// The build of the frame that showed the server's answer for this
  /// text, when it came before the next key: the frame the device's rows
  /// spare the other modes.
  required final double? answerBuild,
}) {
  String get csv =>
      '$mode,$cadence,$line,$len,$log,$rank,$frame,$build,$raster,$skew,'
      '$answerBuild';
}

final _rowsLine = RegExp(
  r'len=(\d+) (?:rows rank=([\d.]+) ms|cached) ([\d.]+) ms$',
);
final _answerLine = RegExp(r'len=\d+ answer ([\d.]+) ms$');

_Sample _sample(_Key key, int? next, List<FrameTiming> timings) {
  double? log;
  double? rank;
  double? answer;
  for (final line in key.logs) {
    if (_rowsLine.firstMatch(line) case final m?) {
      rank = m.group(2) == null ? null : double.parse(m.group(2)!);
      log = double.parse(m.group(3)!);
    } else if (_answerLine.firstMatch(line) case final m?) {
      answer = double.parse(m.group(1)!);
    }
  }
  // The answer's log is that frame's post-frame callback.
  final answered = answer == null ? null : key.at + (answer * 1000).round();
  final answerFrame = answered == null
      ? null
      : timings.where((f) {
          final end = f.timestampInMicroseconds(FramePhase.buildFinish);
          return (end - answered).abs() < 4000;
        }).firstOrNull;
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
    answerBuild: answerFrame == null
        ? null
        : ms(answerFrame.buildDuration.inMicroseconds),
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
    ..householdIndex = _household
    ..suggestions.addAll(_answers);
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

/// Types every line of [_lines] in a fresh app in [mode], [after] called
/// once per line with its index, after the line and the server's answer.
Future<List<_Key>> _typeLines(
  _Mode mode,
  Duration cadence,
  List<String> logs,
  Future<void> Function(int line) after, {
  Future<void> Function()? afterKey,
}) async {
  final keys = <_Key>[];
  runApp(_app(mode));
  await _settle();
  for (final (line, text) in _lines.indexed) {
    await _tap(_field());
    await _settle();
    if (line == 0) {
      await after(-1);
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
      await afterKey?.call();
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
    await after(line);
  }
  return keys;
}

/// [_profileRounds] at the slow cadence with every build, layout and paint
/// on the timeline; per mode, the mean time per key of the UI thread's
/// events in the key's frame (from the key to that frame's build end),
/// by event name, own time without children: the widgets and render
/// objects that cost the most, and GC.
Future<void> _profile(
  WidgetsBinding binding,
  List<FrameTiming> timings,
  List<String> logs,
) async {
  final reader = await TimelineReader.start();
  if (reader == null) {
    debugPrintSynchronously('[timing-profile] no VM service');
    return;
  }
  debugProfileBuildsEnabled = true;
  debugProfileLayoutsEnabled = true;
  debugProfilePaintsEnabled = true;
  final perMode = <String, (List<_Key>, List<Span>)>{};
  for (var round = 0; round < _profileRounds; round++) {
    for (final mode in _modes) {
      final (keys, spans) = perMode[mode.name] ??= ([], []);
      await reader.take();
      keys.addAll(
        await _typeLines(
          mode,
          _cadences.last,
          logs,
          (line) => reader.take(),
          // The VM's timeline buffer holds about one key's events.
          afterKey: () async => spans.addAll(await reader.take()),
        ),
      );
    }
  }
  debugProfileBuildsEnabled = false;
  debugProfileLayoutsEnabled = false;
  debugProfilePaintsEnabled = false;
  await reader.close();
  await Future<void>.delayed(const Duration(seconds: 2));
  final out = StringBuffer();
  for (final MapEntry(key: mode, value: (keys, spans)) in perMode.entries) {
    final uiThread = spans.firstWhere((s) => s.name == 'BUILD').tid;
    final self = <String, int>{};
    final total = <String, int>{};
    var counted = 0;
    for (final (i, key) in keys.indexed) {
      final next = keys.elementAtOrNull(i + 1)?.at;
      final frame = timings.where((f) {
        final start = f.timestampInMicroseconds(FramePhase.buildStart);
        return start >= key.at && (next == null || start < next);
      }).firstOrNull;
      if (frame == null) {
        continue;
      }
      counted++;
      final end = frame.timestampInMicroseconds(FramePhase.buildFinish);
      for (final s in spans) {
        if (s.start >= key.at && s.end <= end) {
          final name = s.tid != uiThread
              ? 'other thread: ${s.name}'
              : s.depth < 3
              ? '${'>' * (s.depth + 1)} ${s.name}'
              : s.name;
          self.update(name, (v) => v + s.self, ifAbsent: () => s.self);
          total.update(
            name,
            (v) => v + s.end - s.start,
            ifAbsent: () => s.end - s.start,
          );
        }
      }
    }
    String ms(int us) => (us / 1000 / counted).toStringAsFixed(2);
    out.writeln('$mode: $counted keys, ms per key, own | with children');
    final outer = total.keys.where((n) => n.startsWith('>')).toList()
      ..sort((a, b) => total[b]!.compareTo(total[a]!));
    final names = self.keys.toList()
      ..sort((a, b) => self[b]!.compareTo(self[a]!));
    final byTotal = total.keys.toList()
      ..sort((a, b) => total[b]!.compareTo(total[a]!));
    for (final name in [
      ...outer.take(25),
      ...names.take(40),
      ...byTotal.take(80),
    ]) {
      out.writeln('  $name: ${ms(self[name]!)} | ${ms(total[name]!)}');
    }
  }
  out
      .toString()
      .split('\n')
      .forEach((line) => debugPrintSynchronously('[timing-profile] $line'));
}

Future<void> _cpuProfile(List<FrameTiming> timings, List<String> logs) async {
  final reader = await TimelineReader.start();
  if (reader == null) {
    debugPrintSynchronously('[timing-cpu] no VM service');
    return;
  }
  await reader.setFlag('profiler', 'true');
  await reader.setFlag('profile_period', '100');
  final perMode = <String, (List<_Key>, List<(int, List<String>)>)>{};
  for (var round = 0; round < _cpuRounds; round++) {
    for (final mode in _modes) {
      final (keys, samples) = perMode[mode.name] ??= ([], []);
      await reader.cpuSamples();
      keys.addAll(
        await _typeLines(
          mode,
          _cadences.last,
          logs,
          (line) async => samples.addAll(await reader.cpuSamples()),
        ),
      );
    }
  }
  await reader.close();
  await Future<void>.delayed(const Duration(seconds: 2));
  final out = StringBuffer();
  for (final MapEntry(key: mode, value: (keys, samples)) in perMode.entries) {
    final windows = <(int, int)>[];
    for (final (i, key) in keys.indexed) {
      final next = keys.elementAtOrNull(i + 1)?.at;
      final frame = timings.where((f) {
        final start = f.timestampInMicroseconds(FramePhase.buildStart);
        return start >= key.at && (next == null || start < next);
      }).firstOrNull;
      if (frame != null) {
        windows.add((
          key.at,
          frame.timestampInMicroseconds(FramePhase.buildFinish),
        ));
      }
    }
    final self = <String, int>{};
    final inclusive = <String, int>{};
    var counted = 0;
    for (final (at, stack) in samples) {
      if (!windows.any((w) => at >= w.$1 && at <= w.$2)) {
        continue;
      }
      counted++;
      self.update(stack.firstOrNull ?? '?', (v) => v + 1, ifAbsent: () => 1);
      for (final name in stack.toSet()) {
        inclusive.update(name, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    // The ranking's own subtree: what under suggestEntries costs the most.
    final ranking = <String, int>{};
    final rankingSelf = <String, int>{};
    for (final (at, stack) in samples) {
      final top = stack.indexOf('suggestEntries');
      if (top < 0 || !windows.any((w) => at >= w.$1 && at <= w.$2)) {
        continue;
      }
      rankingSelf.update(stack.first, (v) => v + 1, ifAbsent: () => 1);
      for (final name in stack.take(top + 1).toSet()) {
        ranking.update(name, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    String share(int n) => '${(100 * n / counted).toStringAsFixed(1)} %';
    out
      ..writeln(
        "$mode: ${windows.length} keys, $counted samples in the keys' "
        "windows (key to its frame's build end), "
        '${(counted * 0.1 / windows.length).toStringAsFixed(2)} ms per key',
      )
      ..writeln('  own:');
    for (final name
        in (self.keys.toList()..sort((a, b) => self[b]!.compareTo(self[a]!)))
            .take(30)) {
      out.writeln('    ${share(self[name]!)} $name');
    }
    out.writeln('  with callees:');
    for (final name
        in (inclusive.keys.toList()
              ..sort((a, b) => inclusive[b]!.compareTo(inclusive[a]!)))
            .take(120)) {
      out.writeln('    ${share(inclusive[name]!)} $name');
    }
    if (ranking.isNotEmpty) {
      out.writeln('  under suggestEntries, with callees:');
      for (final name
          in (ranking.keys.toList()
                ..sort((a, b) => ranking[b]!.compareTo(ranking[a]!)))
              .take(50)) {
        out.writeln('    ${share(ranking[name]!)} $name');
      }
      out.writeln('  under suggestEntries, own:');
      for (final name
          in (rankingSelf.keys.toList()
                ..sort((a, b) => rankingSelf[b]!.compareTo(rankingSelf[a]!)))
              .take(25)) {
        out.writeln('    ${share(rankingSelf[name]!)} $name');
      }
    }
  }
  out
      .toString()
      .split('\n')
      .forEach((line) => debugPrintSynchronously('[timing-cpu] $line'));
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

/// The server's answer for every text the probe types: its rows as
/// public.suggest_entries ranks them (the device's port, held to it by the
/// parity test), made before the first key so no mode pays for them. Up
/// to 8 rows, as the real answer: the frame that shows them is the one
/// the device's rows spare the other modes. Made from copies of the
/// catalog and the household, so the device's lookups and caches for them
/// start as cold as without the probe.
final _answers = () {
  final catalog = CatalogIndex.bundled.apply(
    const CatalogDelta(version: catalogVersion, full: false),
  );
  final household = HouseholdIndex(
    history: _household.history,
    brands: _household.brands,
    unserved: _household.unserved,
    known: _household.known,
  );
  return {
    for (final line in _lines)
      for (var len = 1; len <= line.length; len++)
        if (line.substring(0, len).trim() case final text when text.isNotEmpty)
          text: suggestEntries(
            text,
            catalog: catalog,
            household: household,
            categories: Catalog(categories: _categories),
            known: const {},
          ),
  };
}();

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
