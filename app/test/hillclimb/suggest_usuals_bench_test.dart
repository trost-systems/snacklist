import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../list/suggest_fixture/fixture.dart';

/// hc-suggest-cpu: times `suggestUsuals` over the frozen workload and writes
/// the samples to HC_SUGGEST_BENCH (`tool/hillclimb/hc-suggest-cpu/measure.sh`).
/// Skipped unless that variable names an output file. HC_SUGGEST_USUALS times
/// the first n usuals only (the app loads at most 200); the ranked check
/// still covers all of them.
void main() {
  final out = Platform.environment['HC_SUGGEST_BENCH'];
  final size = int.tryParse(Platform.environment['HC_SUGGEST_USUALS'] ?? '');
  const warmup = 5;
  const rounds = 30;

  test('suggest bench', skip: out == null, timeout: Timeout.none, () async {
    final fixture = SuggestFixture.load();
    final usuals = size == null
        ? fixture.usuals
        : fixture.usuals.take(size).toList();
    void round(List<int>? samples) {
      for (final query in fixture.queries) {
        final watch = Stopwatch()..start();
        suggestUsuals(usuals, fixture.onList, query);
        samples?.add(watch.elapsedMicroseconds);
      }
    }

    for (var i = 0; i < warmup; i++) {
      round(null);
    }
    final samples = <int>[];
    for (var i = 0; i < rounds; i++) {
      round(samples);
    }
    final cold = <int>[];
    for (var i = 0; i < rounds; i++) {
      final reloaded = [
        for (final u in usuals)
          Usual(
            name: u.name,
            due: u.due,
            quantity: u.quantity,
            lastUsed: u.lastUsed,
          ),
      ];
      final watch = Stopwatch()..start();
      suggestUsuals(reloaded, fixture.onList, fixture.queries[i]);
      cold.add(watch.elapsedMicroseconds);
    }
    final vm = await _Vm.connect();
    await vm?.allocated(reset: true);
    round(null);
    final bytesPerRound = await vm?.allocated(reset: false);
    await vm?.close();
    File(out!).writeAsStringSync(
      jsonEncode({
        'samples_us': samples,
        'cold_us': cold,
        'queries': fixture.queries.length,
        'usuals': usuals.length,
        'rounds': rounds,
        'warmup': warmup,
        'bytes_per_round': bytesPerRound,
        'ranked': fixture.ranked(),
      }),
    );
  });
}

/// The VM service of this test's isolate, when `flutter test` was run with
/// `--enable-vmservice`.
final class _Vm._(final WebSocket _socket, final String _isolateId) {
  this {
    _socket.listen((message) {
      final reply = jsonDecode(message as String) as Map<String, Object?>;
      _replies.remove(reply['id'])?.complete(reply);
    });
  }

  static Future<_Vm?> connect() async {
    final uri = (await Service.getInfo()).serverWebSocketUri;
    final isolateId = Service.getIsolateId(Isolate.current);
    if (uri == null || isolateId == null) {
      return null;
    }
    return _Vm._(await WebSocket.connect(uri.toString()), isolateId);
  }

  final _replies = <String, Completer<Map<String, Object?>>>{};
  var _next = 0;

  /// Bytes allocated since the last reset, summed over every class.
  Future<int> allocated({required bool reset}) async {
    final id = '${_next++}';
    final reply = Completer<Map<String, Object?>>();
    _replies[id] = reply;
    _socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': 'getAllocationProfile',
        'params': {
          'isolateId': _isolateId,
          if (reset) 'reset': true,
          if (reset) 'gc': true,
        },
      }),
    );
    final answer = await reply.future;
    if (answer['result'] case final Map<String, Object?> result) {
      return [
        for (final member in result['members']! as List<Object?>)
          (member! as Map<String, Object?>)['accumulatedSize']! as int,
      ].fold<int>(0, (a, b) => a + b);
    }
    throw StateError('getAllocationProfile: $answer');
  }

  Future<void> close() => _socket.close();
}
