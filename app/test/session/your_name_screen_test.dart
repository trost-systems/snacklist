import 'dart:async';

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/your_name.dart';
import 'package:family_groceries/session/your_name_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../household/harness.dart' show TestSession;
import 'fake_your_name.dart';

/// Job 297, DN3: „Wie sollen wir dich nennen?“ after the sign-in.
void main() {
  const home = Household(id: 'home', name: 'Zuhause');
  const member = InHousehold('lea', home, [home]);
  const newcomer = NeedsHousehold('lea');

  late StreamController<AuthState> auth;
  late FakeNameRepository server;
  late MemoryPostponements device;
  late YourNameCubit names;
  late TestSession sessions;

  Future<void> pump(
    WidgetTester tester, {
    Session session = newcomer,
    NameRow? row = (name: 'Lea Brandt', chosen: false, fromEmail: false),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    auth = StreamController<AuthState>.broadcast();
    addTearDown(auth.close);
    server = FakeNameRepository(row: row);
    device = MemoryPostponements();
    names = YourNameCubit(server, device, auth.stream);
    addTearDown(names.close);
    sessions = TestSession(session);
    addTearDown(sessions.close);
    auth.add(signedInAs('lea'));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>.value(value: sessions),
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
          home: const YourNameScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final field = find.byKey(const ValueKey('your-name-field'));
  final primary = find.byKey(const ValueKey('your-name-save'));
  final notNow = find.byKey(const ValueKey('your-name-not-now'));

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(field).controller!.text;

  bool enabled(WidgetTester tester) =>
      tester.widget<FilledButton>(primary).onPressed != null;

  testWidgets("a Google name: one tap on Yes, that's me saves it", (
    tester,
  ) async {
    await pump(tester);
    expect(fieldText(tester), 'Lea Brandt');
    expect(
      find.descendant(of: primary, matching: find.text("Yes, that's me")),
      findsOneWidget,
    );
    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(server.saved, ['Lea Brandt']);
    expect(asksName(newcomer, names.state), isFalse);
  });

  testWidgets('a changed name reads Continue and saves what was typed', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(field, 'Lea');
    await tester.pump();
    expect(
      find.descendant(of: primary, matching: find.text('Continue')),
      findsOneWidget,
    );
    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(server.saved, ['Lea']);
  });

  testWidgets('from the e-mail: empty and required; a name with an emoji '
      'saves normalized', (tester) async {
    await pump(
      tester,
      row: (name: 'lea.brandt87', chosen: false, fromEmail: true),
    );
    expect(fieldText(tester), isEmpty);
    expect(find.text('e.g. Lea'), findsOneWidget);
    expect(enabled(tester), isFalse);
    await tester.enterText(field, '   ');
    await tester.pump();
    expect(enabled(tester), isFalse);
    await tester.enterText(field, '  Lea   🌻 ');
    await tester.pump();
    expect(enabled(tester), isTrue);
    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(server.saved, ['Lea 🌻']);
  });

  testWidgets('no Not now without a household: the name is required', (
    tester,
  ) async {
    await pump(
      tester,
      row: (name: 'lea.brandt87', chosen: false, fromEmail: true),
    );
    expect(field, findsOneWidget);
    expect(notNow, findsNothing);
  });

  testWidgets('Not now for members; it postpones on this device', (
    tester,
  ) async {
    await pump(
      tester,
      session: member,
      row: (name: 'lea.brandt87', chosen: false, fromEmail: true),
    );
    expect(asksName(member, names.state), isTrue);
    await tester.tap(notNow);
    await tester.pumpAndSettle();
    expect(server.saved, isEmpty);
    expect(device.postponed, {'lea'});
    expect(asksName(member, names.state), isFalse);
  });

  testWidgets("Apple's late name fills the field, unless the user typed", (
    tester,
  ) async {
    await pump(
      tester,
      row: (name: 'x7k2pq9mzd', chosen: false, fromEmail: true),
    );
    expect(fieldText(tester), isEmpty);
    server.row = (name: 'Lea Brandt', chosen: false, fromEmail: false);
    auth.add(signedInAs('lea', event: AuthChangeEvent.userUpdated));
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'Lea Brandt');

    await tester.enterText(field, 'Lea');
    server.row = (name: 'Lea B.', chosen: false, fromEmail: false);
    auth.add(signedInAs('lea', event: AuthChangeEvent.userUpdated));
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'Lea');
  });

  testWidgets('saving: a second tap sends nothing; offline it stays with '
      'the error', (tester) async {
    await pump(tester);
    server
      ..holdSave = Completer<void>()
      ..saveError = const NameOffline();
    await tester.tap(primary);
    await tester.pump();
    await tester.tap(primary, warnIfMissed: false);
    await tester.pump();
    expect(server.saved, hasLength(1));
    server.holdSave!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('No internet connection. Your name was not saved.'),
      findsOneWidget,
    );
    expect(fieldText(tester), 'Lea Brandt');
    expect(asksName(newcomer, names.state), isTrue);
  });

  testWidgets('a failed read offers a retry', (tester) async {
    await pump(tester, row: null);
    expect(find.byKey(const ValueKey('your-name-load-failed')), findsOneWidget);
    server.row = (name: 'Lea Brandt', chosen: false, fromEmail: false);
    await tester.tap(find.byKey(const ValueKey('your-name-retry')));
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'Lea Brandt');
  });

  for (final brightness in Brightness.values) {
    for (final row in <NameRow>[
      (name: 'lea.brandt87', chosen: false, fromEmail: true),
      (
        name: 'Maximiliane Theodora von Hohenzollern-Sigmaringen',
        chosen: false,
        fromEmail: false,
      ),
    ]) {
      testWidgets('at 200 % in ${brightness.name}, '
          '${row.fromEmail ? 'empty' : 'a long name'}: nothing overflows', (
        tester,
      ) async {
        await pump(
          tester,
          session: member,
          row: row,
          brightness: brightness,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        if (row.fromEmail) {
          await tester.enterText(field, 'Lea 🌻');
          await tester.pump();
        }
        // The page's list builds lazily: at 200 % the button is below it.
        await tester.scrollUntilVisible(
          primary,
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(primary.hitTestable(), findsOneWidget);
        await tester.tap(primary);
        await tester.pumpAndSettle();
        expect(server.saved, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final session in [newcomer, member]) {
    testWidgets('sign-out leaves the step '
        '(${session is InHousehold ? 'a member' : 'without a household'})', (
      tester,
    ) async {
      await pump(tester, session: session);
      final signOut = find.byKey(const ValueKey('your-name-sign-out'));
      expect(find.byTooltip('Sign out'), findsOneWidget);
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      expect(sessions.state, isA<SignedOut>());
      expect(server.saved, isEmpty, reason: 'nothing stamped as chosen');
    });
  }

  testWidgets('a name of only zero-width characters stays off', (tester) async {
    await pump(
      tester,
      row: (name: 'lea.brandt87', chosen: false, fromEmail: true),
    );
    await tester.enterText(field, '\u200B\u200D\uFEFF');
    await tester.pump();
    expect(enabled(tester), isFalse);
    await tester.enterText(field, '👨‍👩‍👧');
    await tester.pump();
    expect(enabled(tester), isTrue, reason: 'joiners inside an emoji count');
  });

  testWidgets('the field stops at 80 code points, as the server counts', (
    tester,
  ) async {
    await pump(
      tester,
      row: (name: 'lea.brandt87', chosen: false, fromEmail: true),
    );
    await tester.enterText(field, 'a' * 78);
    await tester.pump();
    // The family emoji is one letter on the counter but five code points.
    await tester.enterText(field, '${'a' * 78}👨‍👩‍👧');
    await tester.pump();
    expect(fieldText(tester), 'a' * 78);
    expect(enabled(tester), isTrue);
    await tester.enterText(field, '${'a' * 75}👨‍👩‍👧');
    await tester.pump();
    expect(fieldText(tester), '${'a' * 75}👨‍👩‍👧');
    expect(enabled(tester), isTrue);
  });
}
