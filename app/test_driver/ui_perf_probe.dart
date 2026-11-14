import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui';

import 'package:family_groceries/list/add_sheet/add_sheet.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/dividers.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Profile entrypoint for the frame time measurement
/// (`tool/hillclimb/hc-ui-perf/measure.sh`): the real app against the fake
/// household, driven through four scripted flows with synthetic touches.
/// It prints one JSON line, every frame's build and raster time in
/// microseconds per flow, and exits.
Future<void> main() async {
  if (kReleaseMode) {
    throw StateError('ui_perf_probe.dart is for profile builds.');
  }
  Timer(const Duration(seconds: 240), () {
    stderr.writeln('ui_perf_probe: timed out');
    exit(2);
  });
  await app.bootstrap(() {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    unawaited(
      _run(binding).catchError((Object error, StackTrace stack) {
        stderr.writeln('ui_perf_probe: $error\n$stack');
        exit(3);
      }),
    );
    return binding;
  });
}

const _flows = {
  'fling': _fling,
  'add': _add,
  'tick': _tick,
  'sections': _sections,
};

final _frames = <FrameTiming>[];

Future<void> _run(WidgetsBinding binding) async {
  binding.addTimingsCallback(_frames.addAll);
  await _until(() => _rows().isNotEmpty, 'the list shows');
  await _settle();
  // trace.py turns the timeline on through the VM service meanwhile.
  final only = Platform.environment['HC108_TRACE_FLOW'];
  final churn = _SemanticsChurn();
  if (only != null) {
    await Future<void>.delayed(const Duration(seconds: 3));
    churn.watch();
  }
  final result = <String, Object>{};
  for (final MapEntry(:key, :value) in _flows.entries) {
    if (only != null && only != key) {
      continue;
    }
    await _quiet();
    _frames.clear();
    final watch = Stopwatch()..start();
    final steps = await value();
    stderr.writeln('ui_perf_probe: $key took ${watch.elapsed}');
    await _quiet();
    result[key] = {
      if (only != null) 'semantics': churn.take(),
      'steps': steps,
      'frames': [
        for (final f in _frames)
          [f.buildDuration.inMicroseconds, f.rasterDuration.inMicroseconds],
      ],
    };
  }
  _frames.clear();
  await _quiet();
  result['idle_frames'] = _frames.length;
  stdout.writeln(jsonEncode(result));
  await stdout.flush();
  if (only != null) {
    await Future<void>.delayed(const Duration(seconds: 20));
  }
  exit(0);
}

/// Fling the list to its end and back, a fling whenever the last one
/// came to rest.
Future<int> _fling() async {
  final position = _position();
  var flings = 0;
  for (final up in [true, false]) {
    while (flings < 60) {
      final atEnd = up
          ? position.pixels >= position.maxScrollExtent - 0.5
          : position.pixels <= position.minScrollExtent + 0.5;
      if (atEnd) {
        break;
      }
      await _drag(up ? -1 : 1);
      flings++;
      await _settle();
    }
  }
  if (position.pixels > position.minScrollExtent + 0.5) {
    throw StateError('fling: not back at the top');
  }
  return flings;
}

/// Add 20 items through the sheet: a tap on the field opens it, each name
/// is typed a letter per 40 ms and sent; then the sheet closes.
Future<int> _add() async {
  await _tap(_find((e) => e.widget is EditableText)!);
  await _settle();
  if (_find((e) => e.widget is AddSheet) == null) {
    throw StateError('add: no sheet');
  }
  for (final name in _newItems) {
    final field = _find((e) => e.widget is EditableText)!;
    final state = (field as StatefulElement).state as EditableTextState;
    for (var n = 1; n <= name.length; n++) {
      state.updateEditingValue(
        TextEditingValue(
          text: name.substring(0, n),
          selection: TextSelection.collapsed(offset: n),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    state.performAction(TextInputAction.send);
    await _settle();
  }
  _closeSheet();
  await _settle();
  final open = {
    for (final item in _list().items.values)
      if (item.status == ItemStatus.active) item.name,
  };
  if (!_newItems.every(open.contains)) {
    throw StateError('add: not every item landed');
  }
  return _newItems.length;
}

/// Tick the 20 rows at the top, a tap per 250 ms so their animations
/// overlap; then untick them one by one from "recently used".
Future<int> _tick() async {
  final position = _position()..jumpTo(0);
  await _settle();
  final ticked = <String>[];
  while (ticked.length < 20) {
    final row = _rows().firstWhere((r) {
      final item = (r.widget as ItemRow).item;
      return !ticked.contains(item.id) && _fullyVisible(r);
    });
    ticked.add((row.widget as ItemRow).item.id);
    await _tap(row);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  await _settle();
  final tile = _find(_isUsedTile)!;
  await Scrollable.ensureVisible(tile, alignment: 0.5);
  await _settle();
  await _tap(tile, at: _centre(tile).translate(0, 24 - _size(tile).height / 2));
  await _settle();
  for (final id in ticked.reversed) {
    final used = _find((e) => e.widget.key == ValueKey('used-$id'));
    if (used == null) {
      throw StateError('tick: $id is not under recently used');
    }
    await Scrollable.ensureVisible(used, alignment: 0.5);
    await _settle();
    await _tap(used);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  await _settle();
  final items = _list().items;
  if (ticked.any((id) => items[id]?.status != ItemStatus.active)) {
    throw StateError('tick: not every item came back');
  }
  position.jumpTo(0);
  await _settle();
  return ticked.length * 2;
}

/// Ten times: fold the topmost open section and open and close the add
/// sheet; then unfold the ten again.
Future<int> _sections() async {
  _position().jumpTo(0);
  await _settle();
  var taps = 0;
  for (var i = 0; i < 10; i++) {
    await _tap(
      await _inReach(
        () => _dividers().firstWhere((d) => !(d.widget as StoreDivider).folded),
      ),
    );
    taps++;
    await _settle();
    await _tap(_find((e) => e.widget is EditableText)!);
    await _settle();
    _closeSheet();
    await _settle();
  }
  // The folded dividers stand together at the top; the lowest opens first,
  // so the rest stay on screen.
  while (_list().prefs.folded.isNotEmpty) {
    await _tap(
      await _inReach(
        () => _dividers().lastWhere((d) => (d.widget as StoreDivider).folded),
      ),
    );
    taps++;
    await _settle();
  }
  return taps;
}

const _newItems = [
  'Feta', 'Rucola', 'Ingwer', 'Limetten', 'Kokosmilch', 'Couscous',
  'Linsen', 'Kichererbsen', 'Sesam', 'Basilikum', 'Pinienkerne', 'Datteln',
  'Hafermilch', 'Tofu', 'Zucchini', 'Aubergine', 'Mango', 'Heidelbeeren',
  'Walnüsse', 'Parmesan', //
];

bool _isUsedTile(Element e) => e.widget.key == const ValueKey('recently-used');

void _closeSheet() =>
    (_find((e) => e.widget is AddSheet)!.widget as AddSheet).onClose();

ScrollPosition _position() {
  final row = _rows().first;
  return Scrollable.of(row).position;
}

/// Every element matching [test], in tree order.
List<Element> _all(bool Function(Element) test) {
  final found = <Element>[];
  void visit(Element e) {
    if (test(e)) {
      found.add(e);
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Element? _find(bool Function(Element) test) => _all(test).firstOrNull;

List<Element> _rows() =>
    _all((e) => e.widget is ItemRow && _laidOut(e))
      ..sort((a, b) => _top(a).compareTo(_top(b)));

List<Element> _dividers() =>
    _all((e) => e.widget is StoreDivider && _laidOut(e))
      ..sort((a, b) => _top(a).compareTo(_top(b)));

ListState _list() => BlocProvider.of<ListCubit>(_rows().first).state;

bool _laidOut(Element e) {
  final box = e.renderObject;
  return box is RenderBox && box.attached && box.hasSize;
}

double _top(Element e) =>
    (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy;

Size _size(Element e) => (e.renderObject! as RenderBox).size;

Offset _centre(Element e) {
  final box = e.renderObject! as RenderBox;
  return box.localToGlobal(box.size.center(Offset.zero));
}

/// Inside the list's viewport.
bool _fullyVisible(Element e) {
  final viewport = Scrollable.of(e).context.findRenderObject()! as RenderBox;
  final top = viewport.localToGlobal(Offset.zero).dy;
  return _top(e) >= top &&
      _top(e) + _size(e).height <= top + viewport.size.height;
}

/// Whether a tap on [e]'s centre reaches it: on screen, under nothing.
bool _reaches(Element e) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, _centre(e), _view().viewId);
  return result.path.any((entry) => entry.target == e.renderObject);
}

/// The element [pick] finds, scrolled to the middle of the list when a tap
/// would not reach it: the list runs under the header and the add field.
Future<Element> _inReach(Element Function() pick) async {
  final found = pick();
  if (_reaches(found)) {
    return found;
  }
  await Scrollable.ensureVisible(found, alignment: 0.5);
  await _settle();
  return pick();
}

FlutterView _view() => WidgetsBinding.instance.platformDispatcher.implicitView!;

var _pointer = 100;

Duration _now() => Duration(microseconds: Timeline.now);

/// A tap on [target], at its centre unless [at], that must reach it.
Future<void> _tap(Element target, {Offset? at}) async {
  at ??= _centre(target);
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, at, _view().viewId);
  if (!result.path.any((entry) => entry.target == target.renderObject)) {
    // Profile builds print an Offset as "Instance of 'Offset'".
    throw StateError(
      'a tap at ${at.dx},${at.dy} misses ${target.widget.runtimeType}: '
      '${result.path.firstOrNull?.target.runtimeType} is on top',
    );
  }
  final pointer = ++_pointer;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
      timeStamp: _now(),
      position: at,
      viewId: _view().viewId,
      pointer: pointer,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 50));
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
      timeStamp: _now(),
      position: at,
      viewId: _view().viewId,
      pointer: pointer,
    ),
  );
}

/// A flick of the finger, [direction] -1 up: 6 moves of 60 px, 8 ms apart
/// by their time stamps (7500 px/s), one per frame, then let go.
Future<void> _drag(int direction) async {
  final view = _view();
  final height = view.physicalSize.height / view.devicePixelRatio;
  final x = view.physicalSize.width / view.devicePixelRatio / 2;
  var at = Offset(x, direction < 0 ? height * 0.7 : height * 0.3);
  final pointer = ++_pointer;
  var stamp = _now();
  void send(PointerEvent event) =>
      GestureBinding.instance.handlePointerEvent(event);
  send(
    PointerDownEvent(
      timeStamp: stamp,
      position: at,
      viewId: view.viewId,
      pointer: pointer,
    ),
  );
  for (var i = 0; i < 6; i++) {
    await WidgetsBinding.instance.endOfFrame;
    stamp += const Duration(milliseconds: 8);
    final delta = Offset(0, 60.0 * direction);
    at += delta;
    send(
      PointerMoveEvent(
        timeStamp: stamp,
        position: at,
        delta: delta,
        viewId: view.viewId,
        pointer: pointer,
      ),
    );
    WidgetsBinding.instance.scheduleFrame();
  }
  stamp += const Duration(milliseconds: 8);
  send(
    PointerUpEvent(
      timeStamp: stamp,
      position: at,
      viewId: view.viewId,
      pointer: pointer,
    ),
  );
}

/// Until nothing animates: no frame scheduled and no ticker running, for
/// 100 ms in a row.
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

/// Settled, and long enough after it for the engine's batched frame
/// timings to arrive.
Future<void> _quiet() async {
  await _settle();
  await Future<void>.delayed(const Duration(milliseconds: 1500));
}

Future<void> _until(bool Function() test, String what) async {
  final watch = Stopwatch()..start();
  while (!test()) {
    if (watch.elapsed > const Duration(seconds: 60)) {
      throw StateError('waited for $what');
    }
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }
}

/// Trace mode: how much of the semantics tree each update changes, by node
/// id: nodes added, removed and changed (rect, transform, label, value,
/// flags), and the updates sent.
class _SemanticsChurn() {
  var _last = <int, List<int>>{};
  final _counts = {'updates': 0, 'added': 0, 'removed': 0, 'changed': 0};
  final _changedBy = <String, int>{};

  void watch() {
    final owner = RendererBinding.instance.rootPipelineOwner;
    void hook(PipelineOwner o) {
      o.semanticsOwner?.addListener(_update);
      o.visitChildren(hook);
    }

    hook(owner);
    _last = _snapshot();
  }

  Map<int, List<int>> _snapshot() {
    final now = <int, List<int>>{};
    void visit(SemanticsNode node) {
      final data = node.getSemanticsData();
      now[node.id] = [
        node.rect.hashCode,
        node.transform.hashCode,
        Object.hash(data.label, data.value, data.hint),
        data.flagsCollection.hashCode,
        data.actions,
        Object.hashAll(
          node
              .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
              .map((c) => c.id),
        ),
      ];
      _labels[node.id] = data.label;
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    void root(PipelineOwner o) {
      if (o.semanticsOwner?.rootSemanticsNode case final node?) {
        visit(node);
      }
      o.visitChildren(root);
    }

    root(RendererBinding.instance.rootPipelineOwner);
    return now;
  }

  final _labels = <int, String>{};

  void _update() {
    final now = _snapshot();
    _counts['updates'] = _counts['updates']! + 1;
    for (final MapEntry(:key, :value) in now.entries) {
      final before = _last[key];
      if (before == null) {
        _counts['added'] = _counts['added']! + 1;
      } else if (!listEquals(before, value)) {
        _counts['changed'] = _counts['changed']! + 1;
        const fields = [
          'rect',
          'transform',
          'text',
          'flags',
          'actions',
          'kids',
        ];
        final what = [
          for (var i = 0; i < fields.length; i++)
            if (before[i] != value[i]) fields[i],
        ].join('+');
        final label = '${(_labels[key] ?? '').split('\n').first}#$key:$what';
        _changedBy[label] = (_changedBy[label] ?? 0) + 1;
      }
    }
    _counts['removed'] =
        _counts['removed']! +
        _last.keys.where((k) => !now.containsKey(k)).length;
    _last = now;
  }

  Map<String, Object> take() {
    final top = _changedBy.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final out = <String, Object>{
      ..._counts,
      'top_changed': {for (final e in top.take(12)) e.key: e.value},
    };
    _counts.updateAll((_, _) => 0);
    _changedBy.clear();
    return out;
  }
}
