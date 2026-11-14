import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  group('resolveLocale', () {
    const cases = <(List<Locale>?, AppLanguage?, String)>[
      ([Locale('en', 'US')], null, 'en'),
      ([Locale('de', 'AT')], null, 'de'),
      ([Locale('fr')], null, 'en'),
      ([Locale('fr'), Locale('de', 'CH')], null, 'de'),
      ([Locale('fr'), Locale('en')], null, 'en'),
      ([Locale('fr'), Locale('en'), Locale('de')], null, 'en'),
      ([Locale('de'), Locale('en')], null, 'de'),
      ([], null, 'en'),
      (null, null, 'en'),
      ([Locale('en')], AppLanguage.de, 'de'),
      ([Locale('de')], AppLanguage.en, 'en'),
      ([Locale('fr')], AppLanguage.en, 'en'),
    ];
    for (final (device, picked, expected) in cases) {
      test('device $device, picked ${picked?.code} speaks $expected', () {
        expect(resolveLocale(device, picked), Locale(expected));
      });
    }
  });

  group('LanguageCubit', () {
    late DeviceCache cache;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      cache = DeviceCache(SharedPreferencesAsync());
    });

    test('a pick is kept on the device; System forgets it', () async {
      final cubit = LanguageCubit(cache, null);
      addTearDown(cubit.close);
      expect(await cache.language(), isNull);

      cubit.pick(AppLanguage.en);
      expect(cubit.state, AppLanguage.en);
      await pumpEventQueue();
      expect(AppLanguage.byCode(await cache.language()), AppLanguage.en);

      cubit.pick(null);
      expect(cubit.state, isNull);
      await pumpEventQueue();
      expect(await cache.language(), isNull);
    });

    test('an unknown stored code follows the device', () async {
      await cache.saveLanguage('fr');
      expect(AppLanguage.byCode(await cache.language()), isNull);
    });
  });
}
