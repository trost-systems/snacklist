import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:family_groceries/app/network.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('down only when no interface is up', () {
    expect(networkOf([ConnectivityResult.none]), Network.down);
    expect(networkOf([]), Network.down);
    expect(networkOf([ConnectivityResult.wifi]), Network.up);
    expect(
      networkOf([ConnectivityResult.vpn, ConnectivityResult.mobile]),
      Network.up,
    );
  });

  test('watched on the web, Android and iOS only', () {
    expect(
      networkWatchFor(web: true, platform: TargetPlatform.linux),
      isNotNull,
    );
    expect(
      networkWatchFor(web: false, platform: TargetPlatform.android),
      isNotNull,
    );
    expect(
      networkWatchFor(web: false, platform: TargetPlatform.iOS),
      isNotNull,
    );
    expect(networkWatchFor(web: false, platform: TargetPlatform.linux), isNull);
  });

  group('the platform watch', () {
    const methods = MethodChannel('dev.fluttercommunity.plus/connectivity');
    const events = EventChannel(
      'dev.fluttercommunity.plus/connectivity_status',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late MockStreamHandlerEventSink sink;
    late Object? Function() check;

    setUp(() {
      check = () => ['wifi'];
      messenger
        ..setMockMethodCallHandler(
          methods,
          (call) async => call.method == 'check' ? check() : null,
        )
        ..setMockStreamHandler(
          events,
          MockStreamHandler.inline(onListen: (_, events) => sink = events),
        );
    });

    tearDown(() {
      messenger
        ..setMockMethodCallHandler(methods, null)
        ..setMockStreamHandler(events, null);
    });

    test('tells the current state, then each change once', () async {
      final seen = <Network>[];
      final sub = const PlatformNetworkWatch().watch().listen(seen.add);
      await pumpEventQueue();
      expect(seen, [Network.up], reason: 'the check, with no event yet');
      sink
        ..success(['wifi'])
        ..success(['none'])
        ..success(['none'])
        ..success(['mobile']);
      await pumpEventQueue();
      expect(seen, [Network.up, Network.down, Network.up]);
      await sub.cancel();
    });

    test('a start with no network says down before any change', () async {
      check = () => ['none'];
      final seen = <Network>[];
      final sub = const PlatformNetworkWatch().watch().listen(seen.add);
      await pumpEventQueue();
      expect(seen, [Network.down]);
      await sub.cancel();
    });

    test('a failing plugin says nothing and keeps the stream open', () async {
      check = () => throw PlatformException(code: 'nope');
      final seen = <Network>[];
      final errors = <Object>[];
      final sub = const PlatformNetworkWatch().watch().listen(
        seen.add,
        onError: errors.add,
      );
      await pumpEventQueue();
      sink
        ..error(code: 'nope')
        ..success(['none']);
      await pumpEventQueue();
      expect(seen, [Network.down]);
      expect(errors, isEmpty);
      await sub.cancel();
    });
  });
}
