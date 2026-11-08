import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/settings/access_repository.dart';
import 'package:family_groceries/settings/access_screen.dart';
import 'package:family_groceries/siri/siri_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../household/harness.dart' show TestSession;
import '../siri/fake_siri_channel.dart';

class FakeAccessRepository() implements AccessRepository {
  final tokens = <AccessToken>[];
  final revoked = <String>[];
  final apps = <ConnectedApp>[];
  final disconnected = <String>[];
  var limitReached = false;

  /// The server's refusal of the next API key, e.g. `session_required`.
  String? apiRefusal;

  /// The scopes of every API key asked for.
  final apiScopes = <ApiScopes>[];

  @override
  Future<List<AccessToken>> fetchTokens() async => [
    for (final t in tokens.reversed)
      if (!revoked.contains(t.id)) t,
  ];

  @override
  Future<NewToken> createToken(String name) async {
    if (limitReached) {
      throw const AccessError('too_many_tokens');
    }
    const token = 'fgp_secretsecretsecretsecretsecretsecret1234';
    tokens.add(
      AccessToken(
        id: 't${tokens.length}',
        name: name,
        hint: '1234',
        createdAt: DateTime(2026, 10, 22),
      ),
    );
    return NewToken(name: name, token: token);
  }

  @override
  Future<NewToken> createApiToken(String name, ApiScopes scopes) async {
    apiScopes.add(scopes);
    if (apiRefusal case final code?) {
      throw AccessError(code);
    }
    tokens.add(
      AccessToken(
        id: 'a${tokens.length}',
        name: name,
        kind: AccessKind.api,
        scopes: scopes,
        hint: '9876',
        createdAt: DateTime(2026, 11, 2),
      ),
    );
    return NewToken(name: name, token: apiSecret);
  }

  @override
  Future<void> revokeToken(String id) async => revoked.add(id);

  @override
  Future<List<ConnectedApp>> fetchApps() async => [
    for (final a in apps)
      if (!disconnected.contains(a.clientId)) a,
  ];

  @override
  Future<void> disconnect(String clientId) async => disconnected.add(clientId);
}

const apiSecret = 'fgp_apikeyapikeyapikeyapikeyapikeyapike9876';

void main() {
  late FakeAccessRepository repo;

  Future<void> pumpAccess(
    WidgetTester tester, {
    void Function(FakeAccessRepository repo)? seed,
    SiriChannel? siri,
    String language = 'de',

    /// The flags PostHog serves; none provided at all when null.
    Set<String>? flags,
  }) async {
    // Tall enough for every section without scrolling.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo = FakeAccessRepository();
    seed?.call(repo);
    final Widget screen = AccessScreen(repositories: (_) => repo, siri: siri);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(language),
        home: Scaffold(
          body: switch (flags) {
            null => screen,
            final on => BlocProvider(
              create: (_) => Flags(forced: on),
              child: screen,
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  const secret = 'fgp_secretsecretsecretsecretsecretsecret1234';

  testWidgets('shows the MCP endpoint and empty sections', (tester) async {
    await pumpAccess(tester);
    expect(find.text('MCP-SERVER'), findsOneWidget);
    // Tests build for the production project, whose MCP URL is the proxy.
    expect(find.text('https://mcp.hummlist.com'), findsOneWidget);
    expect(find.text('Kein aktiver Token.'), findsOneWidget);
    expect(find.text('Noch keine App verbunden.'), findsOneWidget);
  });

  testWidgets('a new token is shown once, then only its hint', (tester) async {
    await pumpAccess(tester);
    await tapText(tester, 'Token erstellen');
    await tester.enterText(find.widgetWithText(LabeledField, 'Name'), 'Claude');
    await tapText(tester, 'Erstellen');

    expect(find.text(secret), findsOneWidget);
    expect(
      find.text(
        'Kopiere den Token jetzt. Er wird nicht noch einmal angezeigt.',
      ),
      findsOneWidget,
    );
    await tapText(tester, 'Fertig');

    expect(find.text(secret), findsNothing);
    expect(find.text('Claude'), findsOneWidget);
    expect(
      find.text('…1234 · Erstellt am 22.10.2026 · Noch nie benutzt'),
      findsOneWidget,
    );
  });

  testWidgets('job 169b: a token made after a switch is bound to the household '
      'shown, and the page says which one', (tester) async {
    const home = Household(id: 'home', name: 'Zuhause', isDefault: true);
    const club = Household(id: 'club', name: 'Sommerfest');
    final session = TestSession(const InHousehold('peter', home, [home, club]));
    addTearDown(session.close);
    final repos = <String?, FakeAccessRepository>{
      'home': FakeAccessRepository(),
      'club': FakeAccessRepository(),
    };
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<SessionCubit>.value(
        value: session,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Scaffold(body: AccessScreen(repositories: (h) => repos[h]!)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ein neuer Token gilt für „Zuhause“, den Haushalt, der gerade offen '
        'ist.',
      ),
      findsOneWidget,
    );
    await session.switchTo('club');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ein neuer Token gilt für „Sommerfest“, den Haushalt, der gerade '
        'offen ist.',
      ),
      findsOneWidget,
    );
    await tapText(tester, 'Token erstellen');
    await tester.enterText(find.widgetWithText(LabeledField, 'Name'), 'Skript');
    await tapText(tester, 'Erstellen');
    await tapText(tester, 'Fertig');
    expect([for (final t in repos['club']!.tokens) t.name], ['Skript']);
    expect(repos['home']!.tokens, isEmpty);
  });

  testWidgets('one household: no line about which one', (tester) async {
    await pumpAccess(tester);
    expect(find.byKey(const ValueKey('access-keys-household')), findsNothing);
  });

  testWidgets('the token limit is explained', (tester) async {
    await pumpAccess(tester, seed: (r) => r.limitReached = true);
    await tapText(tester, 'Token erstellen');
    await tester.enterText(find.widgetWithText(LabeledField, 'Name'), 'Siri');
    await tapText(tester, 'Erstellen');
    expect(find.text('Höchstens 20 aktive Tokens.'), findsOneWidget);
    expect(find.textContaining('fgp_'), findsNothing);
  });

  testWidgets('revoking asks first, then removes the token', (tester) async {
    await pumpAccess(
      tester,
      seed: (r) => r.tokens.add(
        AccessToken(
          id: 'siri',
          name: 'Siri',
          hint: 'abcd',
          createdAt: DateTime(2026, 10, 2),
          lastUsedAt: DateTime(2026, 10, 20),
        ),
      ),
    );
    expect(
      find.text('…abcd · Erstellt am 2.10.2026 · Zuletzt benutzt 20.10.2026'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Siri widerrufen'));
    await tester.pumpAndSettle();
    expect(find.text('Token widerrufen?'), findsOneWidget);
    await tapText(tester, 'Abbrechen');
    expect(repo.revoked, isEmpty);

    await tester.tap(find.byTooltip('Siri widerrufen'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Widerrufen');
    expect(repo.revoked, ['siri']);
    expect(find.text('Siri'), findsNothing);
    expect(find.text('Kein aktiver Token.'), findsOneWidget);
  });

  ConnectedApp claude({String? device, DateTime? lastUsedAt}) => ConnectedApp(
    clientId: 'client-1',
    name: 'Claude',
    grantedAt: DateTime(2026, 10, 21),
    scopes: const ['openid', 'email', 'offline_access'],
    device: device,
    lastUsedAt: lastUsedAt,
  );

  testWidgets('a connected app names its device and last activity', (
    tester,
  ) async {
    await pumpAccess(
      tester,
      seed: (r) => r.apps.add(
        claude(device: 'Chrome · macOS', lastUsedAt: DateTime(2026, 11, 2)),
      ),
    );
    expect(
      find.text(
        'Chrome · macOS · Verbunden am 21.10.2026 · Zuletzt aktiv 2.11.2026',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Anmeldung bestätigen'),
      findsNothing,
      reason: 'the scopes are no longer listed as text',
    );
  });

  testWidgets('a grant from before job 80 shows its date only', (tester) async {
    await pumpAccess(tester, seed: (r) => r.apps.add(claude()));
    expect(find.text('Verbunden am 21.10.2026'), findsOneWidget);
  });

  testWidgets('a tap opens the details in plain words, in German', (
    tester,
  ) async {
    await pumpAccess(
      tester,
      seed: (r) => r.apps.add(claude(device: 'Safari · iOS')),
    );
    await tapText(tester, 'Claude');
    final details = find.byKey(const ValueKey('app-details'));
    Finder inSheet(String text) =>
        find.descendant(of: details, matching: find.text(text));
    expect(inSheet('Freigegeben auf Safari · iOS'), findsOneWidget);
    expect(inSheet('Verbunden am 21.10.2026'), findsOneWidget);
    expect(inSheet('Noch nicht aktiv'), findsOneWidget);
    expect(inSheet('WAS CLAUDE DARF'), findsOneWidget);
    expect(
      inSheet(
        'Einträge deiner Einkaufsliste lesen, hinzufügen, abhaken und '
        'verschieben. Claude und sein Anbieter erhalten dabei die Inhalte '
        'eurer Liste.',
      ),
      findsOneWidget,
    );
    expect(inSheet('Deine E-Mail-Adresse sehen.'), findsOneWidget);
    expect(
      inSheet('Verbunden bleiben, bis du die Verbindung trennst.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('app-details-disconnect')));
    await tester.pumpAndSettle();
    await tapText(tester, 'Trennen');
    expect(repo.disconnected, ['client-1']);
    expect(details, findsNothing, reason: 'the sheet closes once it is gone');
    expect(find.text('Noch keine App verbunden.'), findsOneWidget);
  });

  testWidgets('the details in English; cancelling keeps the sheet', (
    tester,
  ) async {
    await pumpAccess(
      tester,
      language: 'en',
      seed: (r) => r.apps.add(
        claude(device: 'Firefox · Linux', lastUsedAt: DateTime(2026, 11, 3)),
      ),
    );
    await tapText(tester, 'Claude');
    expect(find.text('Approved on Firefox · Linux'), findsOneWidget);
    expect(find.text('Last active 11/3/2026'), findsOneWidget);
    expect(find.text('WHAT CLAUDE CAN DO'), findsOneWidget);
    expect(find.text('See your email address.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-details-disconnect')));
    await tester.pumpAndSettle();
    await tapText(tester, 'Cancel');
    expect(repo.disconnected, isEmpty);
    expect(find.byKey(const ValueKey('app-details')), findsOneWidget);
  });

  testWidgets('connected apps can be disconnected', (tester) async {
    await pumpAccess(tester, seed: (r) => r.apps.add(claude()));
    expect(find.text('Claude'), findsOneWidget);

    await tester.tap(find.byTooltip('Claude trennen'));
    await tester.pumpAndSettle();
    expect(find.text('Claude trennen?'), findsOneWidget);
    await tapText(tester, 'Trennen');
    expect(repo.disconnected, ['client-1']);
    expect(find.text('Claude'), findsNothing);
    expect(find.text('Noch keine App verbunden.'), findsOneWidget);
  });

  group('API', () {
    Finder key(String k) => find.byKey(ValueKey(k));

    AccessToken apiKey(String name, ApiScopes scopes) => AccessToken(
      id: name,
      name: name,
      kind: AccessKind.api,
      scopes: scopes,
      hint: 'beef',
      createdAt: DateTime(2026, 10, 30),
    );

    void twoKeys(FakeAccessRepository r) => r.tokens.addAll([
      apiKey('Home Assistant', ApiScopes.readWrite),
      apiKey('Dashboard', ApiScopes.read),
    ]);

    Future<void> openCreate(WidgetTester tester) async {
      await tester.scrollUntilVisible(key('api-create'), 200);
      await tester.tap(key('api-create'));
      await tester.pumpAndSettle();
    }

    Future<void> createApiKey(
      WidgetTester tester,
      String name, {
      String? scope,
    }) async {
      await openCreate(tester);
      await tester.enterText(find.widgetWithText(LabeledField, 'Name'), name);
      if (scope != null) {
        await tester.tap(key(scope));
        await tester.pumpAndSettle();
      }
      await tapText(tester, 'Erstellen');
    }

    testWidgets('flag off and no keys: no API section', (tester) async {
      await pumpAccess(tester, flags: {});
      expect(key('api-section'), findsNothing);
      expect(key('api-create'), findsNothing);
      expect(
        find.text(
          'Mit einem Token baust du eigene Automationen, die eure Liste '
          'pflegen, etwa ein Skript oder einen Assistenten am MCP-Server.',
        ),
        findsOneWidget,
        reason: 'the token hint names no API while it is hidden',
      );
    });

    testWidgets('no Flags above the screen counts as off', (tester) async {
      await pumpAccess(tester);
      expect(key('api-section'), findsNothing);
    });

    testWidgets('flag off: existing keys stay listed to revoke, nothing new', (
      tester,
    ) async {
      await pumpAccess(tester, seed: twoKeys, flags: {});
      expect(key('api-section'), findsOneWidget);
      expect(key('api-key-tile'), findsNWidgets(2));
      expect(key('api-create'), findsNothing);
      expect(key('api-url'), findsNothing);
      expect(
        find.text(
          '…beef · Lesen und schreiben · Erstellt am 30.10.2026 · '
          'Noch nie benutzt',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '…beef · Nur lesen · Erstellt am 30.10.2026 · '
          'Noch nie benutzt',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Kein aktiver Token.'),
        findsOneWidget,
        reason: 'API keys are not MCP tokens',
      );

      await tester.tap(find.byTooltip('Dashboard widerrufen'));
      await tester.pumpAndSettle();
      expect(find.text('API-Schlüssel widerrufen?'), findsOneWidget);
      await tapText(tester, 'Widerrufen');
      expect(repo.revoked, ['Dashboard']);
      expect(key('api-key-tile'), findsOneWidget);
    });

    testWidgets('flag on: URL, docs, and an empty list', (tester) async {
      await pumpAccess(tester, flags: {'public-api'});
      expect(find.text('API'), findsOneWidget);
      expect(
        find.text(
          'https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/api/v1',
        ),
        findsOneWidget,
      );
      expect(key('api-docs'), findsOneWidget);
      expect(find.text('Kein aktiver API-Schlüssel.'), findsOneWidget);
      expect(
        find.text(
          'Mit einem Token baust du eigene Automationen am MCP-Server, die '
          'eure Liste pflegen. Für Programme ohne MCP gibt es unten die API.',
        ),
        findsOneWidget,
      );
      expect(key('api-premium'), findsNothing);
    });

    testWidgets('a read-only key by default, shown once', (tester) async {
      await pumpAccess(tester, flags: {'public-api'});
      await createApiKey(tester, 'Dashboard');

      expect(repo.apiScopes, [ApiScopes.read]);
      expect(find.text('API-Schlüssel erstellt'), findsOneWidget);
      expect(
        find.text(
          'Kopiere den Schlüssel jetzt. Er wird nicht noch einmal angezeigt.',
        ),
        findsOneWidget,
      );
      expect(find.text(apiSecret), findsOneWidget);
      await tapText(tester, 'Fertig');

      expect(find.text(apiSecret), findsNothing);
      expect(key('api-key-tile'), findsOneWidget);
      expect(
        find.text(
          '…9876 · Nur lesen · Erstellt am 2.11.2026 · '
          'Noch nie benutzt',
        ),
        findsOneWidget,
      );
      expect(find.text('Kein aktiver Token.'), findsOneWidget);
    });

    testWidgets('a read-and-write key, in English', (tester) async {
      await pumpAccess(tester, flags: {'public-api'}, language: 'en');
      await openCreate(tester);
      expect(find.text('Read only'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(LabeledField, 'Name'),
        'Home Assistant',
      );
      await tester.tap(key('api-scope-write'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Create');

      expect(repo.apiScopes, [ApiScopes.readWrite]);
      expect(find.text('API key created'), findsOneWidget);
      expect(find.text(apiSecret), findsOneWidget);
      await tapText(tester, 'Done');
      expect(find.textContaining('Read and write'), findsOneWidget);
    });

    testWidgets('the API key limit is explained', (tester) async {
      await pumpAccess(
        tester,
        flags: {'public-api'},
        seed: (r) => r.apiRefusal = 'too_many_tokens',
      );
      await createApiKey(tester, 'Eleventh', scope: 'api-scope-write');
      expect(repo.apiScopes, [ApiScopes.readWrite]);
      expect(
        find.text('Höchstens 10 aktive API-Schlüssel. Widerrufe erst einen.'),
        findsOneWidget,
      );
      expect(find.text(apiSecret), findsNothing);
    });

    testWidgets('outside the app session no key is made', (tester) async {
      await pumpAccess(
        tester,
        flags: {'public-api'},
        language: 'en',
        seed: (r) => r.apiRefusal = 'session_required',
      );
      await openCreate(tester);
      await tester.enterText(find.widgetWithText(LabeledField, 'Name'), 'x');
      await tapText(tester, 'Create');
      expect(
        find.text(
          "You can only create API keys here in the app while you're "
          'signed in.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('while the server has the API off no key is made', (
      tester,
    ) async {
      await pumpAccess(
        tester,
        flags: {'public-api'},
        seed: (r) => r.apiRefusal = 'api_disabled',
      );
      await createApiKey(tester, 'Home Assistant', scope: 'api-scope-write');
      expect(
        find.text('Die API ist noch nicht freigeschaltet.'),
        findsOneWidget,
      );
      expect(find.text(apiSecret), findsNothing);
    });
  });

  group('Siri', () {
    AccessToken token(String id, String name, {AccessKind kind = .pat}) =>
        AccessToken(
          id: id,
          name: name,
          kind: kind,
          hint: id.substring(0, 4),
          createdAt: DateTime(2026, 10, 31),
        );

    FakeSiriChannel thisIphone(String id) =>
        FakeSiriChannel()
          ..entry = SiriKeychainEntry(id: id, userId: 'u1', sessionId: 's1');

    void twoIphones(FakeAccessRepository r) => r.tokens.addAll([
      token('here-id', 'Siri', kind: .siri),
      token('else-id', 'Siri', kind: .siri),
    ]);

    testWidgets('the card and rows on this iPhone, in German', (tester) async {
      await pumpAccess(tester, siri: thisIphone('here-id'), seed: twoIphones);

      expect(
        find.text('Sag zum Beispiel: „Hey Siri, etwas auf Hummlist setzen“.'),
        findsOneWidget,
      );
      expect(find.text('Siri (dieses iPhone)'), findsOneWidget);
      expect(find.text('Siri (anderes iPhone)'), findsOneWidget);
      expect(find.text('Kein aktiver Token.'), findsOneWidget);
      expect(find.byKey(const ValueKey('siri-legacy-hint')), findsNothing);

      await tapText(tester, 'Siri-Sätze anzeigen');
      expect(find.text('„Etwas auf Hummlist setzen“'), findsOneWidget);
      expect(find.text('„Hummlist, was steht drauf?“'), findsOneWidget);
      expect(find.text('„Add to Hummlist“'), findsOneWidget);
      expect(find.text('Auf Englisch'), findsOneWidget);
      await tapText(tester, 'Schließen');
      expect(find.text('Siri-Sätze'), findsNothing);
    });

    testWidgets('the card and rows on this iPhone, in English', (tester) async {
      await pumpAccess(
        tester,
        siri: thisIphone('else-id'),
        seed: twoIphones,
        language: 'en',
      );

      expect(
        find.text('For example, say “Hey Siri, add to Hummlist”.'),
        findsOneWidget,
      );
      expect(find.text('Siri (this iPhone)'), findsOneWidget);
      expect(find.text('Siri (other iPhone)'), findsOneWidget);

      await tapText(tester, 'Show Siri phrases');
      expect(find.text('“Add something to my Hummlist”'), findsOneWidget);
      expect(find.text('“Add <item> to Hummlist”'), findsOneWidget);
      expect(find.text("“What's on my Hummlist?”"), findsOneWidget);
      expect(find.text('“Füge <Eintrag> zu Hummlist hinzu”'), findsOneWidget);
    });

    testWidgets('a Siri credential is revoked like a token', (tester) async {
      await pumpAccess(tester, siri: thisIphone('here-id'), seed: twoIphones);

      await tester.tap(find.byTooltip('Siri (anderes iPhone) widerrufen'));
      await tester.pumpAndSettle();
      expect(find.text('Siri-Zugang widerrufen?'), findsOneWidget);
      await tapText(tester, 'Widerrufen');

      expect(repo.revoked, ['else-id']);
      expect(find.text('Siri (anderes iPhone)'), findsNothing);
      expect(find.text('Siri (dieses iPhone)'), findsOneWidget);
    });

    testWidgets('elsewhere no card, but the rows to revoke', (tester) async {
      await pumpAccess(tester, seed: twoIphones);

      expect(find.byKey(const ValueKey('siri-card')), findsNothing);
      expect(find.text('Siri (anderes iPhone)'), findsNWidgets(2));
    });

    testWidgets('no Siri section elsewhere without Siri rows', (tester) async {
      await pumpAccess(
        tester,
        seed: (r) => r.tokens.add(token('pat-id', 'Siri')),
      );
      expect(find.byKey(const ValueKey('siri-card')), findsNothing);
      expect(find.byKey(const ValueKey('siri-legacy-hint')), findsNothing);
      expect(find.text('Siri'), findsOneWidget, reason: 'the token only');
    });

    testWidgets('the old shortcut token gets a hint', (tester) async {
      await pumpAccess(
        tester,
        siri: FakeSiriChannel(),
        seed: (r) => r.tokens.addAll([
          token('pat1', 'Claude'),
          token('pat2', 'Mein Kurzbefehl'),
          token('siri', 'Siri', kind: .siri),
        ]),
      );
      expect(find.byKey(const ValueKey('siri-legacy-hint')), findsOneWidget);
      expect(
        find.text(
          'Den alten Kurzbefehl brauchst du nicht mehr. '
          'Seinen Token „Mein Kurzbefehl“ kannst du unten löschen.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no hint without a shortcut token', (tester) async {
      await pumpAccess(
        tester,
        siri: FakeSiriChannel(),
        seed: (r) => r.tokens.addAll([
          token('pat1', 'Claude'),
          token('siri', 'Siri', kind: .siri),
        ]),
        language: 'en',
      );
      expect(find.byKey(const ValueKey('siri-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('siri-legacy-hint')), findsNothing);
    });

    testWidgets('a revoked shortcut token loses its hint', (tester) async {
      await pumpAccess(
        tester,
        siri: FakeSiriChannel(),
        seed: (r) => r.tokens.add(token('pat-id', 'Siri Shortcut')),
      );
      expect(find.byKey(const ValueKey('siri-legacy-hint')), findsOneWidget);
      await tester.tap(find.byTooltip('Siri Shortcut widerrufen'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Widerrufen');
      expect(find.byKey(const ValueKey('siri-legacy-hint')), findsNothing);
    });
  });

  group('name dialogs on a small phone, keyboard open, text x2', () {
    Future<void> shrink(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..viewInsets = const FakeViewPadding(bottom: 253);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
    }

    void expectFits(WidgetTester tester) {
      expect(tester.takeException(), isNull);
      final dialog = tester.getRect(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      final field = tester.getRect(find.widgetWithText(LabeledField, 'Name'));
      final buttons = tester.getRect(find.byType(OverflowBar));
      expect(dialog.bottom, lessThanOrEqualTo(568 - 253));
      expect(field.top, greaterThanOrEqualTo(dialog.top));
      expect(buttons.bottom, lessThanOrEqualTo(dialog.bottom));
    }

    testWidgets('the token name: buttons right under the field', (
      tester,
    ) async {
      await pumpAccess(tester);
      await tapText(tester, 'Token erstellen');
      await shrink(tester);
      expectFits(tester);
      final field = tester.getRect(find.widgetWithText(LabeledField, 'Name'));
      expect(
        tester.getRect(find.byType(OverflowBar)).top - field.bottom,
        lessThanOrEqualTo(32),
      );
    });

    testWidgets('the API key: scopes scroll, buttons stay', (tester) async {
      await pumpAccess(tester, flags: {'public-api'});
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('api-create')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('api-create')));
      await tester.pumpAndSettle();
      await shrink(tester);
      expectFits(tester);
    });
  });
}
