import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  group('ThemeCubit', () {
    late DeviceCache cache;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      cache = DeviceCache(SharedPreferencesAsync());
    });

    test(
      'a pick is kept on the device; the device setting forgets it',
      () async {
        final cubit = ThemeCubit(cache, themeModeOf(await cache.theme()));
        addTearDown(cubit.close);
        expect(cubit.state, ThemeMode.system, reason: 'the default');

        cubit.pick(ThemeMode.dark);
        await pumpEventQueue();
        expect(await cache.theme(), 'dark');
        expect(themeModeOf(await cache.theme()), ThemeMode.dark);

        cubit.pick(ThemeMode.light);
        await pumpEventQueue();
        expect(themeModeOf(await cache.theme()), ThemeMode.light);

        cubit.pick(ThemeMode.system);
        await pumpEventQueue();
        expect(await cache.theme(), isNull);
      },
    );

    test('an unknown stored value follows the device', () async {
      await cache.saveTheme('sepia');
      expect(themeModeOf(await cache.theme()), ThemeMode.system);
    });

    // Job 57: the theme is one segmented control (System, Hell, Dunkel)
    // over the same key and values; what was stored reads 1:1.
    for (final (stored, selected) in const [
      (null, ThemeMode.system),
      ('light', ThemeMode.light),
      ('dark', ThemeMode.dark),
    ]) {
      test('a stored $stored selects ${selected.name} and is written back '
          'unchanged', () async {
        await cache.saveTheme(stored);
        final mode = themeModeOf(await cache.theme());
        expect(mode, selected);
        final cubit = ThemeCubit(cache, mode)..pick(mode);
        addTearDown(cubit.close);
        await pumpEventQueue();
        expect(await cache.theme(), stored, reason: 'written back unchanged');
      });
    }

    test('a sign-out keeps the pick: it belongs to the device', () async {
      await cache.saveTheme('dark');
      await cache.forget();
      expect(await cache.theme(), 'dark');
    });
  });

  for (final brightness in Brightness.values) {
    group('the ${brightness.name} theme meets WCAG AA', () {
      final theme = appTheme(brightness);
      final scheme = theme.colorScheme;

      test('is ${brightness.name}', () {
        expect(scheme.brightness, brightness);
        expect(theme.brightness, brightness);
      });

      // Text on the surfaces the app puts it on: screens, sheets and
      // dialogs (surfaceContainer*), snackbars (inverseSurface), filled
      // buttons, chips and the selected add-sheet suggestion.
      final text = <String, (Color, Color)>{
        'onSurface on surface': (scheme.onSurface, scheme.surface),
        'onSurfaceVariant on surface': (
          scheme.onSurfaceVariant,
          scheme.surface,
        ),
        'onSurfaceVariant on surfaceContainerLow (sheets)': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerLow,
        ),
        'onSurface on surfaceContainerHigh (dialogs)': (
          scheme.onSurface,
          scheme.surfaceContainerHigh,
        ),
        'onSurfaceVariant on surfaceContainerHighest': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest,
        ),
        'primary on surface (headers, section titles)': (
          scheme.primary,
          scheme.surface,
        ),
        'onPrimary on primary': (scheme.onPrimary, scheme.primary),
        'onPrimaryContainer on primaryContainer': (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        'onSecondaryContainer on secondaryContainer': (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
        ),
        'onTertiaryContainer on tertiaryContainer': (
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
        ),
        'onInverseSurface on inverseSurface (snackbars)': (
          scheme.onInverseSurface,
          scheme.inverseSurface,
        ),
        'inversePrimary on inverseSurface (snackbar actions)': (
          scheme.inversePrimary,
          scheme.inverseSurface,
        ),
        'error on surface': (scheme.error, scheme.surface),
        'onErrorContainer on errorContainer': (
          scheme.onErrorContainer,
          scheme.errorContainer,
        ),
      };
      for (final MapEntry(key: name, value: (fg, bg)) in text.entries) {
        test('text: $name ≥ 4.5', () {
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
        });
      }

      test('outline (field borders) on surface ≥ 3', () {
        expect(contrastRatio(scheme.outline, scheme.surface), greaterThan(3));
      });

      // The store divider's rule is the store's only line between sections.
      test('store rule (brand) on surface ≥ 3', () {
        expect(
          contrastRatio(SnacklistColors.of(brightness).brand, scheme.surface),
          greaterThanOrEqualTo(3),
        );
      });
    });
  }
}
