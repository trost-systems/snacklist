import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/your_name.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:family_groceries/settings/account_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../session/fake_your_name.dart';
import 'fake_account.dart';

/// Job 297, DE1: Konto › Dein Name.
void main() {
  late FakeNameRepository server;
  late YourNameCubit names;

  Future<void> pump(
    WidgetTester tester, {
    NameRow? row = (name: 'Lea Brandt', chosen: true, fromEmail: false),
    bool flag = true,
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final auth = StreamController<AuthState>.broadcast();
    addTearDown(auth.close);
    server = FakeNameRepository(row: row);
    names = YourNameCubit(server, MemoryPostponements(), auth.stream);
    addTearDown(names.close);
    final flags = Flags(forced: {if (flag) displayNameFlag});
    addTearDown(flags.close);
    auth.add(signedInAs('lea'));
    await tester.pumpWidget(
      RepositoryProvider<AccountRepository>.value(
        value: FakeAccountRepository(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: flags),
            BlocProvider.value(value: names),
          ],
          child: MaterialApp(
            theme: appTheme(brightness),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const Scaffold(body: AccountScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final row = find.byKey(const ValueKey('account-name'));
  final field = find.byKey(const ValueKey('your-name-field'));
  final save = find.byKey(const ValueKey('your-name-sheet-save'));

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(field).controller!.text;

  bool savable(WidgetTester tester) =>
      tester.widget<FilledButton>(save).onPressed != null;

  Future<void> open(WidgetTester tester) async {
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  testWidgets('the row shows the name, first on the page', (tester) async {
    await pump(tester);
    expect(
      find.descendant(of: row, matching: find.text('Lea Brandt')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(row).dy,
      lessThan(tester.getTopLeft(find.text('peter@fg.test')).dy),
    );
  });

  testWidgets('a name from the e-mail: Add your name, and the sheet opens '
      'empty', (tester) async {
    await pump(
      tester,
      row: (name: 'lea.brandt87', chosen: false, fromEmail: true),
    );
    expect(
      find.descendant(of: row, matching: find.text('Add your name')),
      findsOneWidget,
    );
    expect(find.text('lea.brandt87'), findsNothing);
    await open(tester);
    expect(fieldText(tester), isEmpty);
    expect(find.text('e.g. Lea'), findsOneWidget);
    expect(savable(tester), isFalse);
  });

  testWidgets('Save stays off for empty, blank and unchanged; an 81st '
      'character is refused', (tester) async {
    await pump(tester);
    await open(tester);
    expect(fieldText(tester), 'Lea Brandt');
    expect(savable(tester), isFalse, reason: 'unchanged');
    await tester.enterText(field, '  Lea   Brandt ');
    await tester.pump();
    expect(savable(tester), isFalse, reason: 'unchanged once normalized');
    await tester.enterText(field, '');
    await tester.pump();
    expect(savable(tester), isFalse, reason: 'empty');
    await tester.enterText(field, '   ');
    await tester.pump();
    expect(savable(tester), isFalse, reason: 'blank');
    await tester.enterText(field, 'x' * 80);
    await tester.pump();
    await tester.enterText(field, 'x' * 81);
    await tester.pump();
    expect(fieldText(tester), 'x' * 80, reason: 'the 81st is refused');
    expect(savable(tester), isTrue);
  });

  testWidgets('saving closes the sheet and the row shows the new name', (
    tester,
  ) async {
    await pump(tester);
    await open(tester);
    await tester.enterText(field, 'Lea Maria Brandt-Sommerfeld');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(server.saved, ['Lea Maria Brandt-Sommerfeld']);
    expect(field, findsNothing);
    expect(
      find.descendant(
        of: row,
        matching: find.text('Lea Maria Brandt-Sommerfeld'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed save keeps the sheet open with the error', (
    tester,
  ) async {
    await pump(tester);
    await open(tester);
    server.saveError = const NameOffline();
    await tester.enterText(field, 'Lea');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      find.text('No internet connection. Your name was not saved.'),
      findsOneWidget,
    );
    expect(fieldText(tester), 'Lea');
    expect(
      find.descendant(of: row, matching: find.text('Lea Brandt')),
      findsOneWidget,
    );
  });

  testWidgets('with the flag off there is no row', (tester) async {
    await pump(tester, flag: false);
    expect(row, findsNothing);
    expect(find.text('peter@fg.test'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('the sheet at 200 % in ${brightness.name}: nothing '
        'overflows, Save is reachable', (tester) async {
      await pump(tester, brightness: brightness, textScale: 2);
      await open(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        field,
        'Maximiliane Theodora von Hohenzollern-Sigmaringen',
      );
      await tester.pump();
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(server.saved, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a failed read shows the row with a retry, which reads again', (
    tester,
  ) async {
    await pump(tester, row: null);
    final failed = find.byKey(const ValueKey('account-name-failed'));
    expect(failed, findsOneWidget);
    expect(find.text("Couldn't load your name."), findsOneWidget);
    server.row = (name: 'Lea Brandt', chosen: true, fromEmail: false);
    await tester.tap(failed);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: row, matching: find.text('Lea Brandt')),
      findsOneWidget,
    );
  });
}
