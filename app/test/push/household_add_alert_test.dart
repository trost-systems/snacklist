import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:family_groceries/push/household_add_settings.dart';
import 'package:family_groceries/push/push_plugin.dart';
import 'package:family_groceries/push/push_registration.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'push_registration_test.dart'
    show FakePushPlugin, FakePushTokens, MemoryPushStore, Sessions;

class FakePrefs() implements HouseholdAddPrefs {
  ({bool on, String language})? row;
  var offline = false;
  final saves = <String>[];

  @override
  Future<({bool on, String language})?> load() async {
    if (offline) {
      throw Exception('offline');
    }
    return row;
  }

  @override
  Future<void> save({required bool on, required String language}) async {
    if (offline) {
      throw Exception('offline');
    }
    saves.add('$on $language');
    row = (on: on, language: language);
  }
}

/// Job 377: the household-add alert's switch is off until the user turns it
/// on; turning it on is what asks the OS, and a refusal leaves it off.
void main() {
  late FakePushPlugin plugin;
  late FakePrefs prefs;
  late Sessions session;
  late PushRegistration push;
  late HouseholdAddAlert alert;

  setUp(() {
    plugin = FakePushPlugin();
    prefs = FakePrefs();
    session = Sessions();
    push = PushRegistration(plugin, MemoryPushStore(), FakePushTokens(session));
    alert = HouseholdAddAlert(push, prefs);
  });

  tearDown(() async {
    await alert.close();
    await push.close();
    await session.close();
    await plugin.close();
  });

  test('nothing saved reads as off, and asks nobody', () async {
    await alert.refresh('de');
    expect(alert.state, isFalse);
    expect(plugin.prompts, 0);
    expect(prefs.saves, isEmpty);
  });

  test('turning it on prompts, then saves the app language', () async {
    final result = await alert.set(on: true, language: 'en');
    expect(result, HouseholdAddResult.done);
    expect(plugin.prompts, 1);
    expect(prefs.saves, ['true en']);
    expect(alert.state, isTrue);
  });

  test('a refused OS prompt saves nothing and stays off', () async {
    plugin.answer = PushPermission.denied;
    final result = await alert.set(on: true, language: 'de');
    expect(result, HouseholdAddResult.blocked);
    expect(prefs.saves, isEmpty);
    expect(alert.state, isNot(isTrue));
  });

  test('turning it off never prompts', () async {
    await alert.set(on: true, language: 'de');
    final prompts = plugin.prompts;
    expect(await alert.set(on: false, language: 'de'), HouseholdAddResult.done);
    expect(plugin.prompts, prompts);
    expect(prefs.saves.last, 'false de');
    expect(alert.state, isFalse);
  });

  test('offline: the switch stays as it was', () async {
    await alert.refresh('de');
    prefs.offline = true;
    expect(
      await alert.set(on: true, language: 'de'),
      HouseholdAddResult.failed,
    );
    expect(alert.state, isFalse);
  });

  test('a changed app language is written again while it is on', () async {
    prefs.row = (on: true, language: 'de');
    await alert.refresh('en');
    expect(alert.state, isTrue);
    expect(prefs.saves, ['true en']);
  });

  Future<void> pump(WidgetTester tester, {required Set<String> flags}) async {
    // Built here, in the test's fake-async zone: a cubit made in setUp
    // would queue its work outside it.
    push = PushRegistration(plugin, MemoryPushStore(), FakePushTokens(session));
    alert = HouseholdAddAlert(push, prefs);
    final popups = Popups();
    addTearDown(popups.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => Flags(forced: flags)),
          BlocProvider.value(value: alert),
        ],
        child: MaterialApp(
          navigatorObservers: [popups],
          builder: (_, child) => NoticesHost(popups: popups, child: child!),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const Scaffold(body: HouseholdAddSettings()),
        ),
      ),
    );
  }

  final tile = find.byKey(const ValueKey('settings-push-household-add'));

  testWidgets('flag off: no switch', (tester) async {
    await pump(tester, flags: const {});
    await tester.pumpAndSettle();
    expect(tile, findsNothing);
    expect(prefs.saves, isEmpty);
  });

  testWidgets('flag on: an off switch with the example text; a tap asks the '
      'OS and turns it on', (tester) async {
    await pump(tester, flags: const {pushHouseholdAddFlag});
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
    expect(find.text('Wenn jemand etwas hinzufügt'), findsOneWidget);
    expect(find.textContaining('Lea hat Milch hinzugefügt'), findsOneWidget);
    expect(alert.state, isFalse);
    await tester.tap(find.byType(HexSwitch));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(plugin.prompts, 1);
    expect(alert.state, isTrue);
    expect(prefs.saves, ['true de']);
  });
}
