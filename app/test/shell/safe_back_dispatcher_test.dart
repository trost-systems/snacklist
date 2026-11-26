import 'dart:async';

import 'package:family_groceries/shell/safe_back_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  GoRouter build({
    FutureOr<String?> Function(BuildContext, GoRouterState)? redirect,
  }) => GoRouter(
    redirect: redirect,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('root')),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => shell,
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tab',
                builder: (_, _) => const Text('tab'),
                routes: [
                  GoRoute(path: 'inner', builder: (_, _) => const Text('in')),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<GoRouter> pump(
    WidgetTester tester, {
    String location = '/',
    bool guarded = true,
    FutureOr<String?> Function(BuildContext, GoRouterState)? redirect,
  }) async {
    final router = build(redirect: redirect)..go(location);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: guarded ? guardedBack(router) : router),
    );
    return router;
  }

  group('a redirect still pending: the configuration is empty', () {
    testWidgets('plain go_router reports Bad state: No element', (
      tester,
    ) async {
      final held = Completer<String?>();
      final router = await pump(
        tester,
        guarded: false,
        redirect: (_, _) => held.future,
      );
      expect(router.routerDelegate.currentConfiguration.matches, isEmpty);
      await tester.binding.handlePopRoute();
      expect(tester.takeException(), isStateError);
      held.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('back goes to the list and reports the empty configuration', (
      tester,
    ) async {
      final held = Completer<String?>();
      final router = await pump(
        tester,
        location: '/tab',
        redirect: (_, _) => held.future,
      );
      expect(router.routerDelegate.currentConfiguration.matches, isEmpty);
      expect(await tester.binding.handlePopRoute(), isTrue);
      expect(
        tester.takeException(),
        isA<StateError>().having(
          (e) => e.message,
          'message',
          emptyConfigurationOnBack,
        ),
      );
      held.complete();
      await tester.pumpAndSettle();
      expect(find.text('root'), findsOneWidget);
    });
  });

  testWidgets('root: back is not handled', (tester) async {
    await pump(tester);
    expect(await tester.binding.handlePopRoute(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell: back leaves the route inside it, then the app', (
    tester,
  ) async {
    await pump(tester, location: '/tab/inner');
    expect(find.text('in'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('tab'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
