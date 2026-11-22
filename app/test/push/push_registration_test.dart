import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/push/push_plugin.dart';
import 'package:family_groceries/push/push_registration.dart';
import 'package:family_groceries/push/push_target.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/PUSH.md, "The app": the prompt comes only from an opt-in, the
/// token follows the session, and a sign-out leaves the device without push.
void main() {
  const home = Household(id: '00000000-0000-4000-8000-000000000001', name: 'A');
  const peter = InHousehold('00000000-0000-4000-8000-000000000011', home, [
    home,
  ]);
  const lea = InHousehold('00000000-0000-4000-8000-000000000012', home, [home]);

  late FakePushPlugin plugin;
  late MemoryPushStore store;
  late Sessions session;
  late FakePushTokens server;
  late PushRegistration push;

  setUp(() {
    plugin = FakePushPlugin();
    store = MemoryPushStore();
    session = Sessions();
    server = FakePushTokens(session);
    push = PushRegistration(plugin, store, server);
  });

  tearDown(() async {
    await push.close();
    await session.close();
    await plugin.close();
  });

  test(
    'a start never prompts, and registers nothing before an opt-in',
    () async {
      push.follow(session);
      session.emit(peter);
      await pumpEventQueue();

      expect(plugin.prompts, 0);
      expect(server.calls, isEmpty);
      expect(push.state, isA<PushOff>());
    },
  );

  test('an opt-in prompts, registers the token and is remembered', () async {
    push.follow(session);
    session.emit(peter);
    await pumpEventQueue();

    expect(await push.optIn(), isTrue);

    expect(plugin.prompts, 1);
    expect(server.calls, ['register test-token-a ios']);
    expect(store.device, PushDevice.optedIn);
    expect(push.state, isA<PushOn>());
  });

  test('a refused prompt registers nothing and remembers nothing', () async {
    plugin.answer = PushPermission.denied;
    push.follow(session);
    session.emit(peter);
    await pumpEventQueue();

    expect(await push.optIn(), isFalse);

    expect(plugin.prompts, 1);
    expect(server.calls, isEmpty);
    expect(store.device, PushDevice.off);
    expect(push.state, isA<PushBlocked>());
  });

  test('opted in, the next start registers again without a prompt', () async {
    store.device = PushDevice.optedIn;
    plugin.permissionNow = PushPermission.granted;
    push.follow(session);
    session.emit(peter);
    await pumpEventQueue();

    expect(plugin.prompts, 0);
    expect(server.calls, ['register test-token-a ios']);
    expect(push.state, isA<PushOn>());
  });

  test(
    'notifications switched off since: blocked, nothing registered',
    () async {
      store.device = PushDevice.optedIn;
      plugin.permissionNow = PushPermission.denied;
      push.follow(session);
      session.emit(peter);
      await pumpEventQueue();

      expect(plugin.prompts, 0);
      expect(server.calls, isEmpty);
      expect(push.state, isA<PushBlocked>());
    },
  );

  test('a token refresh registers the new token', () async {
    push.follow(session);
    session.emit(peter);
    await pumpEventQueue();
    await push.optIn();

    plugin.refresh('test-token-b');
    await pumpEventQueue();

    expect(server.calls, [
      'register test-token-a ios',
      'register test-token-b ios',
    ]);
  });

  test(
    'a sign-out unregisters while signed in, then deletes and forgets',
    () async {
      push.follow(session);
      session.emit(peter);
      await pumpEventQueue();
      await push.optIn();

      // SessionCubit.signOut: beforeSignOut, then the session ends.
      await push.forget();
      session.emit(const SignedOut());
      await pumpEventQueue();

      expect(server.calls, [
        'register test-token-a ios',
        'unregister test-token-a',
      ]);
      expect(server.signedInAtUnregister, isTrue);
      expect(plugin.deleted, 1);
      expect(store.device, PushDevice.off);
      expect(push.state, isA<PushOff>());

      plugin.refresh('test-token-b');
      session.emit(lea);
      await pumpEventQueue();
      expect(server.calls, hasLength(2), reason: 'the next account starts off');
      expect(plugin.prompts, 1);
    },
  );

  test(
    'the server unreachable at sign-out, the token is still deleted',
    () async {
      push.follow(session);
      session.emit(peter);
      await pumpEventQueue();
      await push.optIn();
      server.offline = true;

      await push.forget();

      expect(plugin.deleted, 1);
      expect(store.device, PushDevice.off);
    },
  );

  test('offline at sign-out, the token left is deleted at the next start, '
      'before anything else', () async {
    final first = push.follow(session);
    session.emit(peter);
    await pumpEventQueue();
    await push.optIn();
    server.offline = true;
    plugin.offline = true;

    await push.forget();
    session.emit(const SignedOut());
    await pumpEventQueue();

    expect(plugin.deleted, 0);
    expect(store.device, PushDevice.tokenLeft);
    expect(push.state, isA<PushOff>());

    // The app starts again, online, and Lea signs in on this phone.
    await first.cancel();
    await push.close();
    server.offline = false;
    plugin.offline = false;
    push = PushRegistration(plugin, store, server)..follow(session);
    session.emit(lea);
    await pumpEventQueue();

    expect(plugin.deleted, 1);
    expect(store.device, PushDevice.off);
    expect(server.calls, ['register test-token-a ios']);
    expect(plugin.prompts, 1, reason: 'no prompt for Lea');
  });

  test('a token left is deleted on a signed-out start too', () async {
    store.device = PushDevice.tokenLeft;
    session.emit(const SignedOut());
    push.follow(session);
    await pumpEventQueue();

    expect(plugin.deleted, 1);
    expect(store.device, PushDevice.off);
  });

  test('still offline, the token stays left for the next chance', () async {
    store.device = PushDevice.tokenLeft;
    plugin.offline = true;
    push.follow(session);
    session.emit(lea);
    await pumpEventQueue();

    expect(store.device, PushDevice.tokenLeft);
    expect(server.calls, isEmpty);
  });

  test('an opt-in deletes a token left first, then registers anew', () async {
    store.device = PushDevice.tokenLeft;
    push.follow(session);
    session.emit(lea);
    await pumpEventQueue();
    plugin.refresh('test-token-b');

    expect(await push.optIn(), isTrue);

    expect(plugin.deleted, 1);
    expect(store.device, PushDevice.optedIn);
    expect(server.calls.last, 'register test-token-b ios');
  });

  test('a delete that never answers holds the sign-out up 3 s at most', () {
    // Built in the fake zone: their futures then run on its clock.
    fakeAsync((async) {
      final plugin = FakePushPlugin();
      final store = MemoryPushStore();
      final session = Sessions();
      final push = PushRegistration(plugin, store, FakePushTokens(session))
        ..follow(session);
      session.emit(peter);
      async.flushMicrotasks();
      unawaited(push.optIn());
      async.flushMicrotasks();
      expect(store.device, PushDevice.optedIn);
      plugin.hang = true;

      var done = false;
      unawaited(push.forget().then((_) => done = true));
      async.elapse(const Duration(seconds: 2));
      expect(done, isFalse);
      async.elapse(const Duration(seconds: 2));

      expect(done, isTrue);
      expect(store.device, PushDevice.tokenLeft);
    });
  });

  test('a sign-out it did not start (account deleted) forgets here', () async {
    push.follow(session);
    session.emit(peter);
    await pumpEventQueue();
    await push.optIn();

    session.emit(const SignedOut());
    await pumpEventQueue();

    expect(server.calls, ['register test-token-a ios']);
    expect(plugin.deleted, 1);
    expect(store.device, PushDevice.off);
  });

  test(
    'a sign-out without an opt-in never touches the messaging SDK',
    () async {
      push.follow(session);
      session.emit(peter);
      await pumpEventQueue();

      await push.forget();
      session.emit(const SignedOut());
      await pumpEventQueue();

      expect(plugin.touched, isFalse);
      expect(server.calls, isEmpty);
    },
  );

  test(
    'taps are handed on once opted in: cold start, then later ones',
    () async {
      store.device = PushDevice.optedIn;
      plugin
        ..permissionNow = PushPermission.granted
        ..launch = {
          'kind': 'list',
          'v': '1',
          'household_id': home.id,
          'list_id': '00000000-0000-4000-8000-000000000021',
        };
      final taps = <PushTarget>[];
      push.taps.listen(taps.add);
      push.follow(session);
      session.emit(peter);
      await pumpEventQueue();

      plugin
        ..open({'kind': 'future', 'household_id': home.id, 'list_id': 'x'})
        ..open({
          'kind': 'list',
          'household_id': home.id,
          'list_id': '00000000-0000-4000-8000-000000000022',
        });
      await pumpEventQueue();

      expect(taps, [
        PushTarget(
          householdId: home.id,
          listId: '00000000-0000-4000-8000-000000000021',
        ),
        PushTarget(
          householdId: home.id,
          listId: '00000000-0000-4000-8000-000000000022',
        ),
      ]);
    },
  );
}

class Sessions() extends Cubit<Session> {
  this : super(const SessionLoading());

  @override
  void emit(Session state) => super.emit(state);
}

class MemoryPushStore() implements PushStore {
  var device = PushDevice.off;

  @override
  Future<PushDevice> pushDevice() async => device;

  @override
  Future<void> savePushDevice(PushDevice device) async => this.device = device;
}

class FakePushTokens(final Sessions _session) implements PushTokens {
  final calls = <String>[];
  bool? signedInAtUnregister;
  var offline = false;

  @override
  Future<void> register(String token, PushPlatform platform) async {
    if (offline) {
      throw Exception('offline');
    }
    calls.add('register $token ${platform.name}');
  }

  @override
  Future<void> unregister(String token) async {
    if (offline) {
      throw Exception('offline');
    }
    signedInAtUnregister = _session.state is! SignedOut;
    calls.add('unregister $token');
  }
}

class FakePushPlugin() implements PushPlugin {
  /// What the OS says without asking.
  var permissionNow = PushPermission.undetermined;

  /// What the prompt answers.
  var answer = PushPermission.granted;
  var prompts = 0;
  var deleted = 0;

  /// The messaging service out of reach: a delete fails.
  var offline = false;

  /// A delete that never answers.
  var hang = false;
  String? _token = 'test-token-a';
  Map<String, Object?>? launch;

  /// Whether anything but the platform was asked.
  var touched = false;
  final _refreshes = StreamController<String>.broadcast();
  final _opened = StreamController<Map<String, Object?>>.broadcast();

  void refresh(String token) {
    _token = token;
    _refreshes.add(token);
  }

  void open(Map<String, Object?> data) => _opened.add(data);

  Future<void> close() async {
    await _refreshes.close();
    await _opened.close();
  }

  @override
  PushPlatform get platform => PushPlatform.ios;

  @override
  Future<PushPermission> permission() async {
    touched = true;
    return permissionNow;
  }

  @override
  Future<PushPermission> requestPermission() async {
    touched = true;
    prompts++;
    return permissionNow = answer;
  }

  @override
  Future<String?> token() async {
    touched = true;
    return _token;
  }

  @override
  Stream<String> get tokenRefreshes {
    touched = true;
    return _refreshes.stream;
  }

  @override
  Future<void> deleteToken() async {
    touched = true;
    if (hang) {
      await Completer<void>().future;
    }
    if (offline) {
      throw Exception('offline');
    }
    deleted++;
    _token = null;
  }

  @override
  Future<Map<String, Object?>?> initialMessage() async {
    touched = true;
    return launch;
  }

  @override
  Stream<Map<String, Object?>> get openedMessages {
    touched = true;
    return _opened.stream;
  }
}
