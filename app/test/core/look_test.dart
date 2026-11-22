import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late DeviceCache cache;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    cache = DeviceCache(SharedPreferencesAsync());
  });

  Flags flags({Set<String> forced = const {}}) {
    final flags = Flags(forced: forced);
    addTearDown(flags.close);
    return flags;
  }

  group('startLook', () {
    test('a fresh install starts with the hexagons', () async {
      expect(await startLook(flags(), cache), Look.hex);
    });

    test('a forced flag starts soft', () async {
      expect(
        await startLook(flags(forced: {redesignRd1Flag}), cache),
        Look.soft,
      );
    });

    test('the flag on at the last start starts soft', () async {
      await cache.saveSoftLook(on: true);
      expect(await startLook(flags(), cache), Look.soft);
      await cache.saveSoftLook(on: false);
      expect(await startLook(flags(), cache), Look.hex);
    });
  });

  group('keepLook', () {
    test('every flags change is saved for the next start', () async {
      final f = flags();
      final kept = keepLook(f, cache);
      addTearDown(kept.cancel);

      f.replace({redesignRd1Flag: true});
      await pumpEventQueue();
      expect(await cache.softLook(), isTrue);
      expect(await startLook(flags(), cache), Look.soft);

      f.replace({'other': true});
      await pumpEventQueue();
      expect(await cache.softLook(), isFalse);
    });

    test('flags known before it starts are saved at once', () async {
      final f = flags()..replace({redesignRd1Flag: true});
      final kept = keepLook(f, cache);
      addTearDown(kept.cancel);
      await pumpEventQueue();
      expect(await cache.softLook(), isTrue);
    });

    test('no flags yet keep the last value', () async {
      await cache.saveSoftLook(on: true);
      final kept = keepLook(flags(), cache);
      addTearDown(kept.cancel);
      await pumpEventQueue();
      expect(await cache.softLook(), isTrue);
    });
  });
}
