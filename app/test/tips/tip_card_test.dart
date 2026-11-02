import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/tips/tip_card.dart';
import 'package:family_groceries/tips/tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';

class _MemoryTipStore() implements TipStore {
  final saved = <String, Set<String>>{};

  @override
  Future<Set<String>> dismissedTips(String userId) async =>
      saved[userId] ?? const {};

  @override
  Future<void> saveDismissedTips(String userId, Set<String> ids) async =>
      saved[userId] = ids;
}

void main() {
  late _MemoryTipStore store;

  setUp(() {
    store = _MemoryTipStore();
    PackageInfo.setMockInitialValues(
      appName: 'Hummlist',
      packageName: 'com.hummlist.app',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> pumpList(
    WidgetTester tester, {
    bool empty = false,
    bool hintDismissed = true,
    Locale locale = const Locale('de'),
  }) async {
    final repo = FakeRepository();
    if (!empty) {
      repo.remoteAdd('Milch');
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: RepositoryProvider<TipStore>.value(
          value: store,
          child: BlocProvider(
            key: UniqueKey(),
            create: (_) => ListCubit(
              repo,
              MemoryListCache()
                ..prefs = ListPrefs(hintDismissed: hintDismissed),
              userId: 'peter',
            )..start(),
            child: const ShoppingList(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tip(String id) => find.byKey(ValueKey('tip-$id'));
  final dismiss = find.byTooltip('Tipp ausblenden');

  testWidgets('the first tip shows above a list with items', (tester) async {
    await pumpList(tester);
    expect(tip('edit-long-press'), findsOneWidget);
    expect(find.text('Artikel bearbeiten'), findsOneWidget);
    expect(dismiss, findsOneWidget);
  });

  testWidgets('an empty list shows no tip', (tester) async {
    await pumpList(tester, empty: true);
    expect(find.byKey(const ValueKey('list-empty')), findsOneWidget);
    expect(tip('edit-long-press'), findsNothing);
  });

  testWidgets('no tip while the gesture card shows', (tester) async {
    await pumpList(tester, hintDismissed: false);
    expect(find.byKey(const ValueKey('list-hint')), findsOneWidget);
    expect(tip('edit-long-press'), findsNothing);
  });

  testWidgets('the X hides the tip for good, the next shows next time', (
    tester,
  ) async {
    await pumpList(tester);
    await tester.tap(dismiss);
    await tester.pumpAndSettle();
    expect(tip('edit-long-press'), findsNothing);
    expect(tip('quick-add-amounts'), findsNothing, reason: 'one tip per start');
    expect(store.saved['peter'], {'edit-long-press'});

    await pumpList(tester);
    expect(tip('edit-long-press'), findsNothing);
    expect(tip('quick-add-amounts'), findsOneWidget);
    expect(find.text('Menge gleich mittippen'), findsOneWidget);

    await tester.tap(dismiss);
    await tester.pumpAndSettle();
    expect(store.saved['peter'], {'edit-long-press', 'quick-add-amounts'});
    await pumpList(tester);
    expect(dismiss, findsNothing);
  });

  group('a tip for iOS only', () {
    final queue = [
      Tip(
        id: 'ios-only',
        title: (_) => 'iOS',
        body: (_) => 'iOS',
        icon: Icons.phone_iphone,
        surfaces: const {TipSurface.ios},
      ),
    ];
    Future<Tip?> shown(TipSurface surface) async {
      final cubit = TipsCubit(
        store,
        userId: 'peter',
        surface: surface,
        appVersion: () async => '0.1.0',
        queue: queue,
      );
      addTearDown(cubit.close);
      await cubit.load();
      return cubit.state;
    }

    test('shows on iOS and is dismissed for good', () async {
      final cubit = TipsCubit(
        store,
        userId: 'peter',
        surface: TipSurface.ios,
        appVersion: () async => '0.1.0',
        queue: queue,
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state?.id, 'ios-only');
      cubit.dismiss();
      expect(cubit.state, isNull);
      expect(store.saved['peter'], {'ios-only'});
      expect(await shown(TipSurface.ios), isNull);
    });

    test('does not show on Android or the web', () async {
      expect(await shown(TipSurface.android), isNull);
      expect(await shown(TipSurface.web), isNull);
    });
  });

  testWidgets('the card reads as its text and an X with a label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester, locale: const Locale('en'));
    expect(
      find.bySemanticsLabel(
        RegExp('^Edit an item\nPress and hold an item and let go'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('tip-dismiss'))),
      isSemantics(tooltip: 'Hide tip', isButton: true),
    );
    semantics.dispose();
  });

  for (final scale in [1.3, 2.0, 3.0]) {
    testWidgets('at text scale $scale the tip fits 358 px', (tester) async {
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = const Size(358 * 3, 780 * 3);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpList(tester);
      expect(tip('edit-long-press'), findsOneWidget);
      expect(tester.getSize(dismiss), const Size(48, 48));
      expect(tester.takeException(), isNull);
    });
  }
}
