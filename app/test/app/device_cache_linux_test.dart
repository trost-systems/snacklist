import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _SupportDir() extends PathProviderLinux {
  @override
  Future<String?> getApplicationSupportPath() async => '/support';
}

void main() {
  const home = Household(id: 'home', name: 'Zuhause');
  final disk = MemoryFileSystem();

  /// A fresh process: both shared_preferences plugins start from the files.
  Future<(SharedPreferencesLocalStorage, DeviceCache)> launch() async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = SharedPreferencesLinux()
      ..fs = disk
      ..pathProvider = _SupportDir();
    SharedPreferencesAsyncPlatform.instance = SharedPreferencesAsyncLinux()
      ..fs = disk
      ..pathProvider = _SupportDir();
    final session = SharedPreferencesLocalStorage(persistSessionKey: 'sb');
    await session.initialize();
    return (session, DeviceCache.onDevice());
  }

  test('on Linux the session and the cache survive a relaunch', () async {
    final (session, cache) = await launch();
    await cache.remember('peter', households: const []);
    await session.persistSession('{"access_token":"t"}');
    await cache.remember('peter', households: [home], shown: home.id);

    final (relaunchedSession, relaunchedCache) = await launch();
    expect(await relaunchedSession.accessToken(), '{"access_token":"t"}');
    expect(
      (await relaunchedCache.householdsOf('peter'))?.households.single.name,
      'Zuhause',
    );
  });
}
