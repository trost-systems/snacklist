import 'dart:async';

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/oauth/consent_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeConsentApi({required final ConsentRequest details})
    implements ConsentApi {
  final decisions = <String>[];

  /// The client and device label each approval recorded.
  final devices = <String>[];
  Exception? failure;

  /// When set, approve answers only once it completes.
  Completer<void>? hold;

  @override
  Future<ConsentRequest> getDetails(String authorizationId) async {
    if (failure case final failure?) {
      throw failure;
    }
    return details;
  }

  @override
  Future<Uri> approve(
    String authorizationId, {
    required String clientId,
    required String device,
  }) async {
    decisions.add('approve $authorizationId');
    devices.add('$clientId $device');
    await hold?.future;
    return Uri.parse('https://client.example/cb?code=granted');
  }

  @override
  Future<Uri> deny(String authorizationId) async {
    decisions.add('deny $authorizationId');
    return Uri.parse('https://client.example/cb?error=access_denied');
  }
}

void main() {
  const request = NeedsConsent(
    clientId: 'client-claude',
    clientName: 'Claude',
    clientUri: 'https://claude.ai',
    email: 'peter@example.com',
    scopes: ['openid', 'email', 'offline_access', 'custom:thing'],
    listsStores: true,
  );
  late FakeConsentApi api;
  late List<Uri> visited;

  Future<void> pumpConsent(
    WidgetTester tester, {
    ConsentRequest details = request,
    String? id = 'auth-1',
    Exception? failure,
    String language = 'de',
  }) async {
    api = FakeConsentApi(details: details)..failure = failure;
    visited = [];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(language),
        home: ConsentView(
          authorizationId: id,
          household: const Household(id: 'h', name: 'Trost'),
          api: api,
          navigate: (url) async => visited.add(url),
        ),
      ),
    );
    // Not pumpAndSettle: the redirect spinner never settles.
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<ButtonStyleButton>(),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the client, account, household and scopes', (
    tester,
  ) async {
    await pumpConsent(tester);
    expect(find.text('Zugriff erlauben?'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('https://claude.ai'), findsOneWidget);
    expect(find.text('Angemeldet als peter@example.com'), findsOneWidget);
    expect(find.text('Haushalt: Trost'), findsOneWidget);
    const listAccess =
        'Einträge deiner Einkaufsliste lesen. Kann auch Einträge hinzufügen, '
        'ändern, abhaken und löschen, Listen und Läden anlegen und '
        'umbenennen und die Reihenfolge in einem Laden festlegen. Claude und '
        'sein Anbieter erhalten dabei die Inhalte eurer Liste.';
    for (final label in [
      listAccess,
      'Deine Anmeldung bestätigen',
      'Deine E-Mail-Adresse',
      'Dauerhaft angemeldet bleiben',
      'custom:thing',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(visited, isEmpty);
  });

  const withLists = NeedsConsent(
    clientId: 'client-claude',
    clientName: 'Claude',
    scopes: [],
    listsStores: true,
  );
  const withoutLists = NeedsConsent(
    clientId: 'client-claude',
    clientName: 'Claude',
    scopes: [],
  );

  const deOff =
      'Einträge deiner Einkaufsliste lesen. Kann auch Einträge hinzufügen, '
      'ändern, abhaken und löschen. Claude und sein Anbieter erhalten '
      'dabei die Inhalte eurer Liste.';
  const deOn =
      'Einträge deiner Einkaufsliste lesen. Kann auch Einträge hinzufügen, '
      'ändern, abhaken und löschen, Listen und Läden anlegen und '
      'umbenennen und die Reihenfolge in einem Laden festlegen. Claude '
      'und sein Anbieter erhalten dabei die Inhalte eurer Liste.';
  const enOff =
      'Read your shopping list. Can also add, change, tick off and remove '
      'items. Claude and its provider will receive your list contents.';
  const enOn =
      'Read your shopping list. Can also add, change, tick off and remove '
      'items, create and rename lists and stores, and set the order in '
      'a store. Claude and its provider will receive your list contents.';

  for (final (language, details, texts) in [
    ('de', withoutLists, [deOff, 'Zugriff erlauben?', 'Erlauben', 'Ablehnen']),
    ('de', withLists, [deOn, 'Zugriff erlauben?', 'Erlauben', 'Ablehnen']),
    ('en', withoutLists, [enOff, 'Allow access?', 'Allow', 'Deny']),
    ('en', withLists, [enOn, 'Allow access?', 'Allow', 'Deny']),
  ]) {
    testWidgets(
      'the page in $language names list and store tools only with the switch '
      '(${details.listsStores ? 'on' : 'off'})',
      (tester) async {
        await pumpConsent(tester, details: details, language: language);
        for (final text in texts) {
          expect(find.text(text), findsOneWidget);
        }
      },
    );
  }

  testWidgets('allow approves and follows the redirect', (tester) async {
    await pumpConsent(tester);
    await tapButton(tester, 'Erlauben');
    expect(api.decisions, ['approve auth-1']);
    expect(api.devices, [
      'client-claude Android',
    ], reason: 'the approval names the device it was given on');
    expect(visited, [Uri.parse('https://client.example/cb?code=granted')]);
    expect(find.text('Verbunden'), findsOneWidget);
    expect(
      find.text('Fertig, du kannst zu Claude zurückkehren.'),
      findsOneWidget,
    );
    expect(find.text('Erlauben'), findsNothing);
  });

  testWidgets('while the server records the approval, nothing is done yet', (
    tester,
  ) async {
    await pumpConsent(tester);
    api.hold = Completer();
    await tapButton(tester, 'Erlauben');
    final allow = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Erlauben'),
    );
    expect(allow.onPressed, isNull, reason: 'no second tap');
    expect(find.byKey(const ValueKey('consent-done')), findsNothing);
    expect(visited, isEmpty);
    api.hold!.complete();
    await tester.pumpAndSettle();
    expect(visited, hasLength(1));
    expect(find.byKey(const ValueKey('consent-done')), findsOneWidget);
  });

  testWidgets('deny denies and follows the redirect', (tester) async {
    await pumpConsent(tester);
    await tapButton(tester, 'Ablehnen');
    expect(api.decisions, ['deny auth-1']);
    expect(visited, [
      Uri.parse('https://client.example/cb?error=access_denied'),
    ]);
    expect(find.text('Nicht verbunden'), findsOneWidget);
    expect(
      find.text('Abgelehnt, du kannst zu Claude zurückkehren.'),
      findsOneWidget,
    );
  });

  testWidgets('an earlier approval redirects without asking', (tester) async {
    await pumpConsent(
      tester,
      details: AlreadyApproved(Uri.parse('https://client.example/cb?code=x')),
    );
    expect(visited, [Uri.parse('https://client.example/cb?code=x')]);
    expect(find.text('Erlauben'), findsNothing);
    expect(
      find.text('Fertig, du kannst zu deiner App zurückkehren.'),
      findsOneWidget,
    );
    expect(api.decisions, isEmpty);
  });

  testWidgets('an expired request explains itself', (tester) async {
    await pumpConsent(
      tester,
      failure: const AuthException('authorization not found'),
    );
    expect(
      find.text(
        'Diese Anfrage ist ungültig oder abgelaufen. '
        'Starte die Verbindung in deiner App neu.',
      ),
      findsOneWidget,
    );
    expect(find.text('authorization not found'), findsNothing);
    expect(
      find.widgetWithText(AppBar, 'Verbindung abgelaufen'),
      findsOneWidget,
    );
    expect(find.text('Zugriff erlauben?'), findsNothing);
    expect(find.text('Erlauben'), findsNothing);
    expect(find.text('Zurück zur Liste'), findsOneWidget);
  });

  testWidgets('a missing authorization id explains itself', (tester) async {
    await pumpConsent(tester, id: null);
    expect(find.textContaining('ungültig oder abgelaufen'), findsOneWidget);
    expect(visited, isEmpty);
  });

  testWidgets('the failed page leads back to the list', (tester) async {
    final router = GoRouter(
      initialLocation: '/oauth',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('the list')),
        GoRoute(
          path: '/oauth',
          builder: (_, _) => ConsentView(
            authorizationId: null,
            household: const Household(id: 'h', name: 'Trost'),
            api: FakeConsentApi(details: request),
            navigate: (_) async {},
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        routerConfig: router,
      ),
    );
    await tester.tap(find.text('Zurück zur Liste'));
    await tester.pumpAndSettle();
    expect(find.text('the list'), findsOneWidget);
  });
}
