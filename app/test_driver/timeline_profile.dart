import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

/// The app's own VM timeline, read over its VM service from inside the
/// app: [start] records the Dart and GC streams, [take] returns the
/// complete events recorded since the last [take] and clears the buffer.
final class TimelineReader._(final WebSocket _socket) {
  this {
    _socket.listen((message) {
      final json = jsonDecode(message as String) as Map<String, Object?>;
      _pending.remove(json['id'])?.complete(json);
    });
  }

  final _pending = <Object?, Completer<Map<String, Object?>>>{};
  var _id = 0;

  /// Null when the app runs without a VM service.
  static Future<TimelineReader?> start() async {
    final info = await developer.Service.getInfo();
    final uri = info.serverWebSocketUri;
    if (uri == null) {
      return null;
    }
    final reader = TimelineReader._(await WebSocket.connect(uri.toString()));
    await reader._call('setVMTimelineFlags', {
      'recordedStreams': ['Dart', 'GC', 'Embedder'],
    });
    await reader._call('clearVMTimeline');
    return reader;
  }

  Future<Map<String, Object?>> _call(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    final id = '${++_id}';
    final done = Completer<Map<String, Object?>>();
    _pending[id] = done;
    _socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return done.future;
  }

  Future<List<Span>> take() async {
    final answer = await _call('getVMTimeline');
    await _call('clearVMTimeline');
    final result = answer['result'] as Map<String, Object?>? ?? const {};
    final events = (result['traceEvents'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    return spans(events);
  }

  /// The UI isolate's CPU samples since the last call: each its time and
  /// its stack, innermost function first, as `Class.method` names.
  Future<List<(int, List<String>)>> cpuSamples() async {
    final isolateId = developer.Service.getIsolateId(Isolate.current);
    final answer = await _call('getCpuSamples', {
      'isolateId': isolateId,
      'timeOriginMicros': _sampledUntil,
      'timeExtentMicros': 1 << 50,
    });
    await _call('clearCpuSamples', {'isolateId': isolateId});
    final result = answer['result'] as Map<String, Object?>? ?? const {};
    if (answer['error'] case final error?) {
      throw StateError('getCpuSamples: $error');
    }
    final functions = [
      for (final f
          in (result['functions'] as List<Object?>? ?? const [])
              .cast<Map<String, Object?>>())
        _functionName(f['function']),
    ];
    final out = <(int, List<String>)>[];
    for (final sample
        in (result['samples'] as List<Object?>? ?? const [])
            .cast<Map<String, Object?>>()) {
      final at = (sample['timestamp'] as num?)?.toInt() ?? 0;
      if (at > _sampledUntil) {
        _sampledUntil = at;
      }
      out.add((
        at,
        [
          for (final i in (sample['stack'] as List<Object?>? ?? const []))
            if (i is int && i < functions.length) functions[i],
        ],
      ));
    }
    return out;
  }

  var _sampledUntil = 0;

  static String _functionName(Object? function) {
    if (function is! Map<String, Object?>) {
      return '?';
    }
    final name = function['name'] as String? ?? '?';
    final owner = function['owner'];
    if (owner is Map<String, Object?> && owner['type'] == '@Function') {
      return '${_functionName(owner)}.$name';
    }
    if (owner is Map<String, Object?> && owner['type'] == '@Class') {
      return '${owner['name']}.$name';
    }
    return name;
  }

  Future<void> setFlag(String name, String value) async {
    final answer = await _call('setFlag', {'name': name, 'value': value});
    if (answer['error'] case final error?) {
      throw StateError('setFlag $name: $error');
    }
  }

  Future<void> close() async {
    await _call('setVMTimelineFlags', {'recordedStreams': <String>[]});
    await _socket.close();
  }
}

/// A complete event with its own time: its duration minus its direct
/// children's on the same thread.
final class Span(
  final String name,
  final Object? tid,
  final int start,
  final int end,
) {
  var self = 0;

  /// How many spans on the same thread enclose this one.
  var depth = 0;
}

List<Span> spans(List<Map<String, Object?>> events) {
  final out = <Span>[];
  final open = <(Object?, String), List<int>>{};
  for (final e in events) {
    final name = e['name'] as String? ?? '';
    final ts = (e['ts'] as num?)?.toInt();
    final tid = e['tid'];
    if (ts == null) {
      continue;
    }
    switch (e['ph']) {
      case 'X':
        out.add(Span(name, tid, ts, ts + ((e['dur'] as num?)?.toInt() ?? 0)));
      case 'B':
        open.putIfAbsent((tid, name), () => []).add(ts);
      case 'E':
        final starts = open[(tid, name)];
        if (starts != null && starts.isNotEmpty) {
          out.add(Span(name, tid, starts.removeLast(), ts));
        }
    }
  }
  out.sort(
    (a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : b.end.compareTo(a.end),
  );
  final stacks = <Object?, List<Span>>{};
  for (final s in out) {
    s.self = s.end - s.start;
    final stack = stacks.putIfAbsent(s.tid, () => []);
    while (stack.isNotEmpty && stack.last.end <= s.start) {
      stack.removeLast();
    }
    if (stack.isNotEmpty && s.end <= stack.last.end) {
      stack.last.self -= s.end - s.start;
      s.depth = stack.length;
    }
    stack.add(s);
  }
  return out;
}
