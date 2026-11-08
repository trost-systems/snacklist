import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/home_widget/home_widget_sync.dart';
import 'package:family_groceries/home_widget/widget_launch.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_scope.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import '../more/more_harness.dart' show FakeSession;
import 'home_widget_sync_test.dart' show FakePublisher;

class FakeLaunches(final Future<Uri?> _initial) implements WidgetLaunches {
  final tapped = StreamController<Uri?>.broadcast();

  @override
  Future<Uri?> initial() => _initial;

  @override
  Stream<Uri?> get taps => tapped.stream;

  Future<void> close() => tapped.close();
}

void main() {
  group('widgetLaunchOf', () {
    for (final (link, launch) in [
      ('hummlist-widget://open/?homeWidget', WidgetLaunch.list),
      ('hummlist-widget://add/?homeWidget', WidgetLaunch.add),
      ('hummlist-widget://add', WidgetLaunch.add),
      ('hummlist-widget://tick/?homeWidget', null),
      ('com.hummlist.app://login-callback?code=x', null),
      ('https://app.hummlist.com/join/ABC123', null),
    ]) {
      test('$link is $launch', () {
        expect(widgetLaunchOf(Uri.parse(link)), launch);
      });
    }

    test('no link is nothing', () => expect(widgetLaunchOf(null), isNull));
  });

  test('the starting tap, then later ones; errors launch nothing', () async {
    final launches = FakeLaunches(
      Future.value(Uri.parse('hummlist-widget://add/?homeWidget')),
    );
    final seen = <WidgetLaunch>[];
    final sub = followWidgetLaunches(launches, seen.add);
    await pumpEventQueue();
    launches.tapped
      ..add(Uri.parse('hummlist-widget://open/?homeWidget'))
      ..add(null)
      ..addError(StateError('plugin'))
      ..add(Uri.parse('https://app.hummlist.com/join/ABC123'));
    await pumpEventQueue();
    expect(seen, [WidgetLaunch.add, WidgetLaunch.list]);
    await sub.cancel();
    await launches.close();

    final failing = FakeLaunches(Future.error(StateError('no plugin')));
    final none = <WidgetLaunch>[];
    final other = followWidgetLaunches(failing, none.add);
    await pumpEventQueue();
    expect(none, isEmpty);
    await other.cancel();
    await failing.close();
  });

  group('the List tab', () {
    setUp(
      () =>
          VisibilityDetectorController.instance.updateInterval = Duration.zero,
    );

    Future<AddSheetRequest> pumpList(
      WidgetTester tester, {
      bool requestFirst = false,
    }) async {
      final request = AddSheetRequest();
      if (requestFirst) {
        request.request();
      }
      await tester.pumpWidget(
        RepositoryProvider.value(
          value: request,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: BlocProvider(
              create: (_) => ListCubit(
                FakeRepository(),
                MemoryListCache(),
                userId: 'peter',
              )..start(),
              child: const ShoppingList(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return request;
    }

    bool sheetOpen(WidgetTester tester) => BlocProvider.of<AddSheetCubit>(
      tester.element(find.byKey(const ValueKey('add-item-field'))),
    ).state.open;

    testWidgets("a widget's Add that started the app opens the add sheet", (
      tester,
    ) async {
      await pumpList(tester, requestFirst: true);
      expect(sheetOpen(tester), isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('add-item-field')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
    });

    testWidgets("a widget's Add while the list shows opens the add sheet", (
      tester,
    ) async {
      final request = await pumpList(tester);
      expect(sheetOpen(tester), isFalse);
      request.request();
      await tester.pumpAndSettle();
      expect(sheetOpen(tester), isTrue);
      expect(request.take(), isFalse, reason: 'used up');
    });
  });

  testWidgets("the list scope writes the household's list for the widgets", (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final cache = DeviceCache(SharedPreferencesAsync());
    final analytics = Analytics.off(cache);
    addTearDown(analytics.close);
    final session = FakeSession();
    const inHome = InHousehold(
      'peter',
      Household(id: 'home', name: 'Zuhause'),
      [Household(id: 'home', name: 'Zuhause')],
    );
    whenListen(session, const Stream<Session>.empty(), initialState: inHome);
    final publisher = FakePublisher();
    final sync = HomeWidgetSync(publisher, debounce: Duration.zero)
      ..follow(session);
    addTearDown(sync.close);
    final repo = FakeRepository();

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: cache),
          RepositoryProvider.value(value: sync),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SessionCubit>.value(value: session),
            BlocProvider.value(value: analytics),
          ],
          child: MaterialApp(
            home: ListScope(repositories: (_) => repo, child: const SizedBox()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => sync.idle);
    expect(publisher.states, ['ready']);

    BlocProvider.of<ListCubit>(tester.element(find.byType(SizedBox)))
        .addEntry(parseEntry('Brot'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => sync.idle);
    expect(publisher.names(), ['Brot']);
  });
}
