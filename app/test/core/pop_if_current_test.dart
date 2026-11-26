import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/name_dialog.dart';
import 'package:family_groceries/session/your_name.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:family_groceries/settings/account_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../session/fake_your_name.dart';
import '../settings/fake_account.dart';

/// Job 438, PostHog bug 2: a popup closed during its save, then popped once
/// the save answered, removed the tab shell, the root navigator's only page.
/// The app went blank (release builds skip go_router's assert) and the next
/// system back threw `Bad state: No element`. Here the popup closes while
/// the save is held, the save answers during its exit animation, and the
/// page under it must stay.
void main() {
  late FakeNameRepository server;
  late Completer<bool> renamed;

  Future<GoRouter> pump(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final auth = StreamController<AuthState>.broadcast();
    addTearDown(auth.close);
    server = FakeNameRepository(
      row: (name: 'Lea Brandt', chosen: true, fromEmail: false),
    )..holdSave = Completer<void>();
    final names = YourNameCubit(server, MemoryPostponements(), auth.stream);
    addTearDown(names.close);
    final flags = Flags(forced: {displayNameFlag});
    addTearDown(flags.close);
    auth.add(signedInAs('lea'));
    renamed = Completer<bool>();
    // Like buildRouter: the tab shell is the root navigator's only page,
    // and popups open on the root navigator above it.
    final router = GoRouter(
      initialLocation: '/account',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => Scaffold(body: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/account',
                  builder: (_, _) => const AccountScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/stores',
                  builder: (context, _) => TextButton(
                    onPressed: () => showNameDialog(
                      context,
                      title: 'title',
                      confirm: 'confirm',
                      label: 'label',
                      initial: 'dm',
                      save: (_) => renamed.future,
                    ),
                    child: const Text('rename'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepositoryProvider<AccountRepository>.value(
        value: FakeAccountRepository(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: flags),
            BlocProvider.value(value: names),
          ],
          child: MaterialApp.router(
            theme: appTheme(Brightness.light),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  final nameRow = find.byKey(const ValueKey('account-name'));

  void expectShellKept(WidgetTester tester, GoRouter router) {
    expect(tester.takeException(), isNull);
    expect(router.routerDelegate.currentConfiguration.matches, isNotEmpty);
  }

  testWidgets('Konto › Dein Name: back during the save keeps the Konto page', (
    tester,
  ) async {
    final router = await pump(tester);
    await tester.tap(nameRow);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('your-name-field')),
      'Lea Maria',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('your-name-sheet-save')));
    await tester.pump();
    expect(server.saved, ['Lea Maria']);

    expect(await tester.binding.handlePopRoute(), isTrue);
    // The sheet is on its way out, still mounted, when the save answers.
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(const ValueKey('your-name-field')), findsOneWidget);
    server.holdSave!.complete();
    await tester.pumpAndSettle();

    expectShellKept(tester, router);
    expect(find.byKey(const ValueKey('your-name-field')), findsNothing);
    expect(
      find.descendant(of: nameRow, matching: find.text('Lea Maria')),
      findsOneWidget,
    );
    // Back now answers for the Konto page: not handled, and no error.
    expect(await tester.binding.handlePopRoute(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('name dialog: a barrier tap during the save keeps the page', (
    tester,
  ) async {
    final router = await pump(tester);
    router.go('/stores');
    await tester.pumpAndSettle();
    await tester.tap(find.text('rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dm Altstadt');
    await tester.tap(find.text('confirm'));
    await tester.pump();

    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(AlertDialog), findsOneWidget);
    renamed.complete(true);
    await tester.pumpAndSettle();

    expectShellKept(tester, router);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('rename'), findsOneWidget);
  });
}
