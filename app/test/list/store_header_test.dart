import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/dividers.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:family_groceries/list/store_app.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

const _lidl = Retailer(
  chain: 'lidl',
  country: 'DE',
  name: 'Lidl',
  apps: [
    RetailerApp(
      name: 'Lidl Plus',
      android: 'com.lidl.eci.lidlplus',
      ios: '1238611143',
    ),
  ],
);

final class _Opener() implements StoreAppOpener {
  final opened = <String>[];

  @override
  Future<bool> launchPackage(String package) async {
    opened.add(package);
    return true;
  }

  @override
  Future<bool> openLink(Uri url, {required bool appOnly}) async {
    opened.add('$url');
    return true;
  }
}

/// Job 313: the store header (plain caret, like „Zuletzt verwendet“) and,
/// with `open-store-app`, its app key and the one-time tip.
void main() {
  late FakeRepository repo;
  late MemoryListCache cache;
  late _Opener opener;

  Future<void> pumpList(
    WidgetTester tester, {
    bool flag = true,
    String lidlName = 'Lidl',
    Locale locale = const Locale('de'),
    ListPrefs prefs = const ListPrefs(hintDismissed: true),
  }) async {
    repo = FakeRepository()
      ..retailers = const [_lidl]
      ..stores = [
        const Store(id: 'dm', name: 'dm', sortOrder: 10, seedKey: 'dm'),
        Store(
          id: 'lidl',
          name: lidlName,
          sortOrder: 20,
          seedKey: 'lidl',
          retailer: _lidl,
          retailerAnswered: true,
        ),
      ]
      ..remoteAdd('Milch', storeId: 'lidl')
      ..remoteAdd('Butter', storeId: 'lidl')
      ..remoteAdd('Zahnpasta', storeId: 'dm');
    cache = MemoryListCache()..prefs = prefs;
    opener = _Opener();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => Flags(forced: {if (flag) openStoreAppFlag}),
            ),
            BlocProvider(
              create: (_) => ListCubit(repo, cache, userId: 'peter')..start(),
            ),
          ],
          child: RepositoryProvider<StoreAppOpener>.value(
            value: opener,
            child: const ShoppingList(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder header(String store) => find.byKey(ValueKey('store-$store'));
  Finder appKey(String store) => find.byKey(ValueKey('store-app-$store'));
  Finder tip() => find.byKey(const ValueKey('store-app-tip'));

  testWidgets('the header is name, rule, count and a plain caret; a tap '
      'anywhere on it folds', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester, flag: false);
    final lidl = header('lidl');
    expect(
      find.descendant(of: lidl, matching: find.byType(TactileFace)),
      findsNothing,
      reason: 'the caret has no key chrome any more',
    );
    final name = tester.widget<Text>(
      find.descendant(of: lidl, matching: find.text('Lidl')),
    );
    final listTitle = Theme.of(tester.element(lidl)).textTheme.bodyLarge;
    expect(
      (name.style?.fontSize, name.style?.fontWeight),
      (listTitle?.fontSize, listTitle?.fontWeight),
      reason: "the name is plain text in „Zuletzt verwendet“'s title style",
    );
    expect(
      find.descendant(of: lidl, matching: find.byType(StoreBadge)),
      findsNothing,
      reason: 'no hex badge (Peter, pick 2)',
    );
    expect(
      find.descendant(of: lidl, matching: find.byIcon(Icons.expand_more)),
      findsOneWidget,
    );
    expect(appKey('lidl'), findsNothing, reason: 'flag off: no app key');
    expect(find.byIcon(Icons.open_in_new), findsNothing);
    expect(tip(), findsNothing);
    expect(
      tester.getSemantics(find.byType(StoreDivider).last),
      matchesSemantics(
        label: 'Lidl, 2 Artikel',
        hint: 'Zuklappen',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.descendant(of: lidl, matching: find.text('Lidl')));
    await tester.pumpAndSettle();
    expect(find.text('Milch'), findsNothing, reason: 'the name folds too');
    await tester.tap(
      find.descendant(of: lidl, matching: find.byIcon(Icons.expand_more)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Milch'), findsOneWidget, reason: 'the caret unfolds');
    semantics.dispose();
  });

  testWidgets('flag on: a linked store gets an open key after the caret, '
      'its own 48 px target that never folds', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester);
    expect(appKey('dm'), findsNothing, reason: 'dm has no chain');
    expect(appKey('lidl'), findsOneWidget);
    expect(tester.getSize(appKey('lidl')), const Size(48, 48));
    final caret = find.descendant(
      of: header('lidl'),
      matching: find.byIcon(Icons.expand_more),
    );
    expect(
      tester.getTopLeft(appKey('lidl')).dx - tester.getTopRight(caret).dx,
      10,
      reason: 'the key follows the caret, 10 px apart',
    );
    expect(
      tester.getSemantics(appKey('lidl')),
      matchesSemantics(
        label: 'Lidl Plus öffnen',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      find.bySemanticsLabel('Lidl, 2 Artikel'),
      findsOneWidget,
      reason: 'the fold keeps its own node, without the key',
    );

    await tester.tap(appKey('lidl'));
    await tester.pumpAndSettle();
    expect(opener.opened, ['com.lidl.eci.lidlplus']);
    expect(find.text('Milch'), findsOneWidget, reason: 'no fold');

    await tester.longPress(appKey('lidl'));
    await tester.pumpAndSettle();
    expect(opener.opened, hasLength(1), reason: 'a hold does nothing');
    expect(find.text('Milch'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the tip shows once under the first key and goes for good '
      'with its X', (tester) async {
    await pumpList(tester);
    expect(tip(), findsOneWidget);
    expect(find.text('Öffnet die App des Ladens.'), findsOneWidget);
    expect(
      tester.getTopLeft(tip()).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(header('lidl')).dy),
      reason: 'under the Lidl header, outside it',
    );
    expect(find.descendant(of: header('lidl'), matching: tip()), findsNothing);

    await tester.tap(find.byKey(const ValueKey('store-app-tip-close')));
    await tester.pumpAndSettle();
    expect(tip(), findsNothing);
    expect(cache.prefs?.storeAppTipClosed, isTrue, reason: 'on the device');
    expect(ListPrefs.fromJson(cache.prefs!.toJson()).storeAppTipClosed, isTrue);
  });

  testWidgets('the first tap on a key retires the tip', (tester) async {
    await pumpList(tester);
    await tester.tap(appKey('lidl'));
    await tester.pumpAndSettle();
    expect(tip(), findsNothing);
    expect(cache.prefs?.storeAppTipClosed, isTrue);
  });

  testWidgets('a closed tip stays closed', (tester) async {
    await pumpList(
      tester,
      prefs: const ListPrefs(hintDismissed: true, storeAppTipClosed: true),
    );
    expect(appKey('lidl'), findsOneWidget);
    expect(tip(), findsNothing);
  });

  group('large text', () {
    const long = 'ALDI SÜD am Hauptbahnhof (Ostausgang)';
    for (final scale in [1.0, 2.0, 3.1]) {
      for (final locale in const [Locale('de'), Locale('en')]) {
        for (final flag in [true, false]) {
          testWidgets('at ${(scale * 100).round()} % in ${locale.languageCode}'
              '${flag ? ' with' : ' without'} the key: no overflow', (
            tester,
          ) async {
            tester.view
              ..devicePixelRatio = 3
              ..physicalSize = const Size(360, 640) * 3;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await pumpList(tester, flag: flag, lidlName: long, locale: locale);
            await tester.scrollUntilVisible(
              header('lidl'),
              100,
              scrollable: find
                  .descendant(
                    of: find.byType(CustomScrollView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            final semantics = tester.ensureSemantics();
            await tester.pump();
            final word = locale.languageCode == 'de' ? 'Artikel' : 'items';
            expect(
              find.descendant(
                of: header('lidl'),
                matching: find.textContaining(word, findRichText: true),
              ),
              scale >= 2 ? findsNothing : findsOneWidget,
              reason: 'from 200 % the count is a number only',
            );
            expect(
              find.bySemanticsLabel(RegExp('$word\$')),
              findsWidgets,
              reason: 'the screen reader label keeps the word',
            );
            if (flag) {
              expect(tester.getSize(appKey('lidl')), const Size(48, 48));
            }
            semantics.dispose();
          });
        }
      }
    }
  });
}
