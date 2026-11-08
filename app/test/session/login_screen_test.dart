import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../app/fake_launcher.dart';
import 'fake_auth.dart';

void main() {
  late FakeAuth auth;
  late FakeNativeSignIn native;

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
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    auth = FakeAuth();
    addTearDown(auth.close);
    native = FakeNativeSignIn();
    final session = SessionCubit(FakeClient(auth), MemorySessionCache());
    addTearDown(session.close);
    auth.states.add(const AuthState(AuthChangeEvent.initialSession, null));
    if (returnError != null) {
      auth.states.addError(returnError);
    }
    await tester.pump();
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: SocialSignIn(auth, flows: flows, native: native),
        child: BlocProvider.value(
          value: session,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            home: const LoginScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder google() => find.bySemanticsLabel('Mit Google anmelden');
  Finder apple() => find.bySemanticsLabel('Mit Apple anmelden');

  for (final (locale, labels, urls) in [
    (
      const Locale('de'),
      ['Impressum', 'Datenschutz'],
      ['https://hummlist.com/impressum', 'https://hummlist.com/datenschutz'],
    ),
    (
      const Locale('en'),
      ['Imprint', 'Privacy'],
      ['https://hummlist.com/en/imprint', 'https://hummlist.com/en/privacy'],
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
    expect(find.text('Hummlist'), findsOneWidget);
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
}
