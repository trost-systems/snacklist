import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    as auth_types
    show Session;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../core/fake_launcher.dart';
import 'fake_auth.dart';
import 'fake_households.dart';

void main() {
  late FakeAuth auth;
  late FakeNativeSignIn native;
  late SessionCubit session;

  const both = {
    SocialProvider.google: SignInFlow.native,
    SocialProvider.apple: SignInFlow.native,
  };

  Future<void> pumpLogin(
    WidgetTester tester, {
    Map<SocialProvider, SignInFlow> flows = both,
    Exception? returnError,
    Locale locale = const Locale('de'),
    Size size = const Size(390, 844),
    SupabaseClient Function(FakeAuth auth)? client,
    String? invite,
    Flags? flags,
    GoRouter? router,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    auth = FakeAuth();
    addTearDown(auth.close);
    native = FakeNativeSignIn();
    session = SessionCubit(
      client?.call(auth) ?? FakeClient(auth),
      MemorySessionCache(),
    );
    addTearDown(session.close);
    auth.states.add(const AuthState(AuthChangeEvent.initialSession, null));
    if (returnError != null) {
      auth.states.addError(returnError);
    }
    await tester.pump();
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: SocialSignIn(auth, flows: flows, native: native),
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: session),
            BlocProvider.value(value: flags ?? Flags()),
          ],
          child: router == null
              ? MaterialApp(
                  localizationsDelegates: appLocalizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  locale: locale,
                  home: LoginScreen(invite: invite),
                )
              : MaterialApp.router(
                  localizationsDelegates: appLocalizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  locale: locale,
                  routerConfig: router,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Job 486: one sign-in, „Neu bei Snacklist?“ on it but for an invite,
  // whose sheet asks instead; a link goes along into the guided start.
  group('„Neu bei Snacklist?“', () {
    GoRouter routerAt(String location) {
      final router = GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(
            path: '/login',
            builder: (_, state) => LoginScreen(
              invite: state.uri.queryParameters['invite'],
              next: state.uri.queryParameters['next'],
            ),
          ),
          GoRoute(path: '/start', builder: (_, _) => const SizedBox()),
        ],
      );
      addTearDown(router.dispose);
      return router;
    }

    String location(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.toString();

    for (final (from, to) in [
      ('/login', '/start'),
      ('/login?next=%2Fadd', '/start?next=%2Fadd'),
      (
        '/login?next=%2Foauth%2Fconsent%3Fauthorization_id%3Dabc',
        '/start?next=%2Foauth%2Fconsent%3Fauthorization_id%3Dabc',
      ),
    ]) {
      testWidgets('at $from it shows and opens $to', (tester) async {
        final router = routerAt(from);
        await pumpLogin(tester, router: router);
        expect(find.text("Neu bei Snacklist? Los geht's"), findsOneWidget);
        expect(find.byKey(const ValueKey('legal-imprint')), findsOneWidget);
        expect(find.byKey(const ValueKey('legal-privacy')), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('login-new')));
        await tester.tap(find.byKey(const ValueKey('login-new')));
        await tester.pumpAndSettle();
        expect(location(router), to);
      });
    }

    testWidgets('not for an invite', (tester) async {
      await pumpLogin(tester, router: routerAt('/login?invite=ABCD2345'));
      expect(find.byKey(const ValueKey('login-new')), findsNothing);
    });
  });

  Finder google() => find.bySemanticsLabel('Mit Google anmelden');
  Finder apple() => find.bySemanticsLabel('Mit Apple anmelden');

  for (final (locale, labels, urls) in [
    (
      const Locale('de'),
      ['Impressum', 'Datenschutz'],
      ['https://snacklist.app/impressum', 'https://snacklist.app/datenschutz'],
    ),
    (
      const Locale('en'),
      ['Imprint', 'Privacy'],
      ['https://snacklist.app/en/imprint', 'https://snacklist.app/en/privacy'],
    ),
  ]) {
    for (final size in [const Size(320, 568), const Size(1280, 720)]) {
      testWidgets('$locale ${size.width}: the legal links show and open the '
          'site in the browser', (tester) async {
        final launcher = fakeLauncher();
        await pumpLogin(tester, locale: locale, size: size);
        for (final label in labels) {
          final link = find.text(label);
          expect(link, findsOneWidget);
          final box = tester.getRect(link);
          expect(
            box.bottom <= size.height && box.top >= 0,
            isTrue,
            reason: '$label on screen without scrolling: $box',
          );
          await tester.tap(link);
          await tester.pumpAndSettle();
        }
        expect(launcher.opened, [
          for (final url in urls)
            (url, PreferredLaunchMode.externalApplication),
        ]);
      });
    }
  }

  Finder emailField() => find.widgetWithText(LabeledField, 'E-Mail');
  Finder continueWithEmail() => find.text('Weiter mit E-Mail');
  bool fieldFocused() => find
      .byType(EditableText)
      .evaluate()
      .any((e) => (e.widget as EditableText).focusNode.hasFocus);

  testWidgets('offers the providers first and email as one more button', (
    tester,
  ) async {
    await pumpLogin(tester);
    expect(google(), findsOneWidget);
    expect(apple(), findsOneWidget);
    expect(continueWithEmail(), findsOneWidget);
    expect(
      tester.getTopLeft(continueWithEmail()).dy,
      greaterThan(tester.getTopLeft(apple()).dy),
    );
    expect(emailField(), findsNothing);
    expect(find.text('Registrieren'), findsNothing);
  });

  testWidgets('Weiter mit E-Mail shows every email method, unfocused', (
    tester,
  ) async {
    await pumpLogin(tester);
    await tester.tap(continueWithEmail());
    await tester.pumpAndSettle();
    expect(continueWithEmail(), findsNothing);
    expect(find.text('oder mit E-Mail'), findsOneWidget);
    expect(emailField(), findsOneWidget);
    expect(find.widgetWithText(LabeledField, 'Passwort'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Anmelden'), findsOneWidget);
    expect(find.text('Registrieren'), findsOneWidget);
    expect(find.text('Anmeldelink per E-Mail senden'), findsOneWidget);
    expect(fieldFocused(), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('turning the phone keeps the open email form and its text', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 47);
    await pumpLogin(tester);
    await tester.tap(continueWithEmail());
    await tester.pumpAndSettle();
    await tester.enterText(emailField(), 'lea@example.com');
    await tester.pump();

    tester.view
      ..physicalSize = const Size(844, 390)
      ..padding = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(continueWithEmail(), findsNothing);
    expect(find.text('lea@example.com'), findsOneWidget);
  });

  testWidgets('field errors show an icon beside the text and are read with '
      'their field', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLogin(tester);
    await tester.tap(continueWithEmail());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('login-email')), 'lea');
    await tester.enterText(find.byKey(const ValueKey('login-password')), '12');
    await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
    await tester.pumpAndSettle();

    for (final (key, message) in [
      ('login-email', 'Bitte eine gültige E-Mail-Adresse eingeben'),
      ('login-password', 'Mindestens 6 Zeichen'),
    ]) {
      final field = find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(EditableText),
      );
      expect(tester.getSemantics(field).hint, message, reason: key);
      final text = find.text(message);
      expect(text, findsOneWidget);
      final icon = find.descendant(
        of: find.ancestor(of: text, matching: find.byType(Row)).first,
        matching: find.byIcon(Icons.error_outline),
      );
      expect(icon, findsOneWidget, reason: message);
      final iconBox = tester.getRect(icon);
      final textBox = tester.getRect(text);
      expect(iconBox.right, lessThanOrEqualTo(textBox.left), reason: message);
      expect(
        iconBox.center.dy,
        inInclusiveRange(textBox.top, textBox.top + iconBox.height + 4),
        reason: '$message: icon beside the first line',
      );
      expect(find.bySemanticsLabel(message), findsOneWidget, reason: message);
      expect(
        tester.getSemantics(text).label,
        message,
        reason: '$key: the icon adds nothing to the message',
      );
    }
    semantics.dispose();
  });

  for (final (name, flows) in [
    ('with providers', both),
    ('email only', const <SocialProvider, SignInFlow>{}),
  ]) {
    testWidgets('$name: opens with no field focused and no keyboard', (
      tester,
    ) async {
      await pumpLogin(tester, flows: flows);
      if (flows.isNotEmpty) {
        await tester.tap(continueWithEmail());
        await tester.pumpAndSettle();
      }
      expect(fieldFocused(), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(emailField());
      await tester.pump();
      expect(fieldFocused(), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });
  }

  for (final (name, provider) in [('Google', google), ('Apple', apple)]) {
    testWidgets('$name closes the keyboard; a cancel does not reopen it', (
      tester,
    ) async {
      await pumpLogin(tester);
      await tester.tap(continueWithEmail());
      await tester.pumpAndSettle();
      await tester.tap(emailField());
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      native.error = const SocialSignInCanceled();
      await tester.tap(provider());
      await tester.pump();
      expect(fieldFocused(), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      // The provider's sheet backgrounds the app; returning resumes it.
      [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pumpAndSettle();
      expect(find.text('Anmeldung abgebrochen'), findsOneWidget);
      expect(fieldFocused(), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });
  }

  testWidgets('opens on the brand; both providers are 48 px tall', (
    tester,
  ) async {
    await pumpLogin(tester, size: const Size(360, 780));
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Snacklist'), findsOneWidget);
    final mark = tester.getSize(find.byType(Image).first);
    expect(mark, const Size(56, 56));
    final applePill = find.descendant(
      of: apple(),
      matching: find.byType(FilledButton),
    );
    expect(tester.getSize(applePill).height, 48);
    expect(tester.getSize(find.byType(OutlinedButton).first).height, 48);
  });

  testWidgets('hides providers the build has not configured', (tester) async {
    await pumpLogin(tester, flows: const {});
    expect(google(), findsNothing);
    expect(apple(), findsNothing);
    expect(find.text('oder mit E-Mail'), findsNothing);
    expect(continueWithEmail(), findsNothing);
    expect(emailField(), findsOneWidget);
  });

  testWidgets('shows only Google when Apple is not configured', (tester) async {
    await pumpLogin(
      tester,
      flows: const {SocialProvider.google: SignInFlow.native},
    );
    expect(google(), findsOneWidget);
    expect(apple(), findsNothing);
  });

  testWidgets('Google signs in with an ID token', (tester) async {
    await pumpLogin(tester);
    await tester.tap(google());
    await tester.pumpAndSettle();
    expect(auth.idTokenCalls.single.provider, OAuthProvider.google);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Apple signs in with an ID token', (tester) async {
    await pumpLogin(tester);
    await tester.tap(apple());
    await tester.pumpAndSettle();
    expect(auth.idTokenCalls.single.provider, OAuthProvider.apple);
  });

  testWidgets('cancel says so in German and re-enables the buttons', (
    tester,
  ) async {
    await pumpLogin(tester);
    native.error = const SocialSignInCanceled();
    await tester.tap(apple());
    await tester.pumpAndSettle();
    expect(find.text('Anmeldung abgebrochen'), findsOneWidget);
    expect(auth.idTokenCalls, isEmpty);

    native.error = null;
    await tester.tap(google());
    await tester.pumpAndSettle();
    expect(auth.idTokenCalls, hasLength(1));
  });

  testWidgets('a provider error is shown in German', (tester) async {
    await pumpLogin(tester);
    native.error = const AuthException('Unacceptable audience');
    await tester.tap(google());
    await tester.pumpAndSettle();
    expect(
      find.text('Anmeldung fehlgeschlagen: Unacceptable audience'),
      findsOneWidget,
    );
  });

  testWidgets('a failed browser sign-in is reported on return', (tester) async {
    await pumpLogin(
      tester,
      returnError: const AuthException('Error getting user email'),
    );
    expect(
      find.text('Anmeldung fehlgeschlagen: Error getting user email'),
      findsOneWidget,
    );
  });

  testWidgets('a canceled browser sign-in is reported on return', (
    tester,
  ) async {
    await pumpLogin(
      tester,
      returnError: const AuthException(
        'The user denied the request',
        code: 'access_denied',
      ),
    );
    expect(find.text('Anmeldung abgebrochen'), findsOneWidget);
  });

  group('the sign-in ends its autofill context (job 226)', () {
    // On the web an open context keeps the fields, email and password
    // included, in hidden forms that screen readers find on every later
    // screen.
    const user = User(
      id: 'peter',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-10-22T12:00:00Z',
    );

    Future<void> fillIn(WidgetTester tester) async {
      await tester.tap(continueWithEmail());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        'a@b.c',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'secret-123',
      );
      await tester.pump();
    }

    List<Object?> finishes(WidgetTester tester) => [
      for (final call in tester.testTextInput.log)
        if (call.method == 'TextInput.finishAutofillContext') call.arguments,
    ];

    Future<void> signedIn(WidgetTester tester) async {
      auth
        ..user = user
        ..states.add(
          AuthState(
            AuthChangeEvent.signedIn,
            auth_types.Session(
              accessToken: 'jwt',
              tokenType: 'bearer',
              user: user,
            ),
          ),
        );
      await tester.runAsync(
        () => session.stream.firstWhere((state) => state is InHousehold),
      );
      await tester.pump();
    }

    SupabaseClient server(FakeAuth auth) =>
        FakeHouseholds(auth)..member('peter', 'home', 'Zuhause');

    testWidgets('a password sign-in ends it at once and offers to save the '
        'login', (tester) async {
      await pumpLogin(tester, client: server);
      await fillIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
      await tester.pump();
      expect(auth.passwordSignIns, ['a@b.c']);
      await signedIn(tester);
      expect(finishes(tester), [
        true,
      ], reason: 'at the sign-in, while a login field still owns the input');
      await tester.pumpWidget(const SizedBox());
      expect(finishes(tester), [
        true,
      ], reason: "not again: by then the next screen's field owns it");
    });

    testWidgets('a Google sign-in after a failed password ends it at once '
        'without saving', (tester) async {
      await pumpLogin(tester, client: server);
      await fillIn(tester);
      auth.passwordError = const AuthException('Invalid login credentials');
      await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
      await tester.pumpAndSettle();
      expect(auth.passwordSignIns, hasLength(1));
      await tester.tap(google());
      await tester.pump();
      expect(auth.idTokenCalls, hasLength(1));
      await signedIn(tester);
      expect(finishes(tester), [false]);
      await tester.pumpWidget(const SizedBox());
      expect(finishes(tester), [false]);
    });

    testWidgets('left signed out: it ends without saving them', (tester) async {
      await pumpLogin(tester);
      await fillIn(tester);
      await tester.pumpWidget(const SizedBox());
      expect(finishes(tester), [false]);
    });
  });

  group('JH2 invite sheet (job 271)', () {
    Flags jh2() => Flags(forced: {joinHouseholdJh2Flag});
    Finder sheet() => find.byKey(const ValueKey('invite-sign-in-sheet'));

    testWidgets('asks first whether the invited person has an account', (
      tester,
    ) async {
      await pumpLogin(tester, invite: 'ABCD2345', flags: jh2());
      expect(sheet(), findsOneWidget);
      expect(find.text('Du bist in einen Haushalt eingeladen'), findsOneWidget);
      expect(find.text('Hast du schon ein Snacklist-Konto?'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Konto erstellen'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Anmelden'), findsOneWidget);
    });

    testWidgets('Konto erstellen opens the email form with sign-up first', (
      tester,
    ) async {
      await pumpLogin(tester, invite: 'ABCD2345', flags: jh2());
      await tester.tap(find.byKey(const ValueKey('invite-sheet-create')));
      await tester.pumpAndSettle();
      expect(sheet(), findsNothing);
      expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
      final signUp = find.widgetWithText(FilledButton, 'Registrieren');
      final signIn = find.widgetWithText(OutlinedButton, 'Anmelden');
      expect(signUp, findsOneWidget);
      expect(signIn, findsOneWidget);
      expect(
        tester.getTopLeft(signUp).dy,
        lessThan(tester.getTopLeft(signIn).dy),
      );
      expect(google(), findsOneWidget);
      expect(apple(), findsOneWidget);
      // Once per visit.
      await tester.pumpAndSettle();
      expect(sheet(), findsNothing);
    });

    for (final (how, act) in [
      (
        'Anmelden',
        (WidgetTester tester) =>
            tester.tap(find.byKey(const ValueKey('invite-sheet-sign-in'))),
      ),
      (
        'a dismissal',
        (WidgetTester tester) => tester.tapAt(const Offset(195, 40)),
      ),
    ]) {
      testWidgets('$how leaves the sign-in as it is', (tester) async {
        await pumpLogin(tester, invite: 'ABCD2345', flags: jh2());
        await act(tester);
        await tester.pumpAndSettle();
        expect(sheet(), findsNothing);
        expect(find.byKey(const ValueKey('login-email')), findsNothing);
        expect(find.byKey(const ValueKey('sign-in-email')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('invite-paste-waiting')),
          findsOneWidget,
        );
      });
    }

    testWidgets('shows when the flag arrives after the first frame', (
      tester,
    ) async {
      final flags = Flags();
      addTearDown(flags.close);
      await pumpLogin(tester, invite: 'ABCD2345', flags: flags);
      expect(sheet(), findsNothing);
      flags.replace({joinHouseholdJh2Flag: true});
      await tester.pumpAndSettle();
      expect(sheet(), findsOneWidget);
    });

    testWidgets('no sheet without an invite, and no paste button', (
      tester,
    ) async {
      await pumpLogin(tester, flags: jh2());
      expect(sheet(), findsNothing);
      expect(find.byKey(const ValueKey('invite-paste')), findsNothing);
      expect(find.byKey(const ValueKey('login-new')), findsOneWidget);
    });

    testWidgets('with the flag off: no sheet, the paste button stays', (
      tester,
    ) async {
      await pumpLogin(tester, invite: 'ABCD2345');
      expect(sheet(), findsNothing);
      await pumpLogin(tester);
      expect(find.byKey(const ValueKey('invite-paste')), findsOneWidget);
    });
  });

  group('why a joiner needs an account (job 356)', () {
    const whyDe =
        'Ein Konto brauchst du, damit die gemeinsame Liste mit dem Haushalt '
        'synchron bleibt, zu dem du eingeladen wurdest.';
    const whyEn =
        'You need an account so the shared list stays in sync with the '
        'household you were invited to.';
    Flags joinerDirect() => Flags(forced: {joinerDirectListFlag});

    for (final (locale, line) in [
      (const Locale('de'), whyDe),
      (const Locale('en'), whyEn),
    ]) {
      testWidgets('$locale: the sign-in for an invite says it under the logo', (
        tester,
      ) async {
        await pumpLogin(
          tester,
          invite: 'ABCD2345',
          locale: locale,
          flags: joinerDirect(),
        );
        expect(find.text(line), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(line)).dy,
          lessThan(
            tester.getTopLeft(find.byKey(const ValueKey('sign-in-google'))).dy,
          ),
        );
      });
    }

    testWidgets('it shows with JH2 too, behind its sheet', (tester) async {
      await pumpLogin(
        tester,
        invite: 'ABCD2345',
        flags: Flags(forced: {joinerDirectListFlag, joinHouseholdJh2Flag}),
      );
      expect(find.text(whyDe), findsOneWidget);
    });

    testWidgets('not without an invite', (tester) async {
      await pumpLogin(tester, flags: joinerDirect());
      expect(find.text(whyDe), findsNothing);
    });

    testWidgets('not with the flag off', (tester) async {
      await pumpLogin(tester, invite: 'ABCD2345');
      expect(find.text(whyDe), findsNothing);
    });
  });
}
