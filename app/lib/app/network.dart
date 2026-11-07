import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the OS has a network interface up. Up says nothing of the
/// server: only an answer from it does.
enum Network() {
  up,
  down,
}

/// The OS's network: the current state, then each change.
abstract interface class NetworkWatch() {
  Stream<Network> watch();
}

/// The OS's watch on the web, Android and iOS; null on Linux, where
/// NetworkManager may be missing or may not manage the interface.
NetworkWatch? networkWatchFor({
  required bool web,
  required TargetPlatform platform,
}) =>
    web || platform == TargetPlatform.android || platform == TargetPlatform.iOS
    ? const PlatformNetworkWatch()
    : null;

class const PlatformNetworkWatch() implements NetworkWatch {
  @override
  Stream<Network> watch() {
    final connectivity = Connectivity();
    StreamSubscription<List<ConnectivityResult>>? changes;
    late final StreamController<Network> out;
    // An error says nothing; the list's own requests still tell.
    out = StreamController(
      onListen: () {
        changes = connectivity.onConnectivityChanged.listen(
          (results) => out.add(networkOf(results)),
          onError: (Object _) {},
        );
        unawaited(
          connectivity.checkConnectivity().then((results) {
            if (!out.isClosed) {
              out.add(networkOf(results));
            }
          }, onError: (Object _) {}),
        );
      },
      onCancel: () async {
        await changes?.cancel();
        await out.close();
      },
    );
    return out.stream.distinct();
  }
}

@visibleForTesting
Network networkOf(List<ConnectivityResult> results) =>
    results.every((result) => result == ConnectivityResult.none)
    ? Network.down
    : Network.up;
