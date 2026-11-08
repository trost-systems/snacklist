import 'dart:async';

import 'package:family_groceries/household/welcome_screen.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:family_groceries/settings/account_screen.dart';
import 'package:family_groceries/settings/delete_account_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../household/harness.dart' show TestSession;
import '../purchases/fakes.dart';
import '../session/fake_auth.dart';
import 'fake_account.dart';

typedef SavedExport = ({String fileName, String json, Rect? origin});

void main() {
  late FakeAuth auth;
  late MemorySessionCache cache;
  late SessionCubit session;
  late FakeAccountRepository account;
  late List<SavedExport> saved;
  String? savedPath;

  const user = User(
    id: 'peter',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-10-22T12:00:00Z',
  );

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    FakePremiumServer? premium,
    FakeEntitlementsSource? rows,
    Locale locale = const Locale('de'),
  }) async {
    auth = FakeAuth()..user = user;
    addTearDown(auth.close);
    cache = MemorySessionCache()
      ..only('peter', const Household(id: 'home', name: 'Zuhause'));
    session = SessionCubit(FakeClient(auth), cache);
    addTearDown(session.close);
    // The account page's own session is still loading here; the household's
    // rows follow one that is in the household.
    final inHousehold = TestSession(
      const InHousehold('peter', Household(id: 'home', name: 'Zuhause'), [
        Household(id: 'home', name: 'Zuhause'),
      ]),
    );
    addTearDown(inHousehold.close);
    final entitlements = Entitlements(
      rows ?? FakeEntitlementsSource(),
      inHousehold,
    );
    addTearDown(entitlements.close);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AccountRepository>.value(value: account),
          RepositoryProvider<PremiumServer>.value(
            value: premium ?? FakePremiumServer(),
          ),
          RepositoryProvider<StorePriceReader>.value(
            value: FakeStorePrices(fakeStorePrices),
          ),
          RepositoryProvider.value(
            value: SocialSignIn(
              auth,
              flows: const {},
              native: FakeNativeSignIn(),
            ),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: session),
            BlocProvider.value(value: entitlements),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The account page as More frames it.
  Widget settings() => Scaffold(
    body: AccountScreen(
      saveExport: (fileName, json, {origin}) async {
        saved.add((fileName: fileName, json: json, origin: origin));
        return savedPath;
      },
    ),
  );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    // The scroll lands with the next frame.
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await pump(tester, settings());
    await tapKey(tester, 'account-delete');
    expect(find.byKey(const ValueKey('account-delete-dialog')), findsOneWidget);
  }

  Future<void> confirm(WidgetTester tester, [String word = 'LÖSCHEN']) async {
    await tester.enterText(
      find.byKey(const ValueKey('account-delete-confirm-field')),
      word,
    );
    await tester.pump();
  }

  bool confirmEnabled(WidgetTester tester) => tester
      .widget<FilledButton>(
        find.byKey(const ValueKey('account-delete-confirm')),
      )
      .enabled;

  setUp(() {
    account = FakeAccountRepository();
    saved = [];
    savedPath = null;
  });

  testWidgets('deleting stays disabled until LÖSCHEN is typed', (tester) async {
    await openDialog(tester);
    expect(confirmEnabled(tester), isFalse);
    await confirm(tester, 'LÖSCH');
    expect(confirmEnabled(tester), isFalse);
    await confirm(tester, ' löschen ');
    expect(confirmEnabled(tester), isTrue);
    await confirm(tester, 'Loeschen');
    expect(confirmEnabled(tester), isTrue);

    await tapKey(tester, 'account-delete-cancel');
    expect(find.byKey(const ValueKey('account-delete-dialog')), findsNothing);
    expect(account.deleteCalls, 0);
  });

  group('says what happens to the household', () {
    for (final (fate, text) in [
      (
        const FateKept('Zuhause', ['Lea']),
        'Der Haushalt „Zuhause“ bleibt für Lea mit der ganzen Liste erhalten. '
            'Deine Einträge bleiben dort, aber ohne deinen Namen.',
      ),
      (
        const FateKept('WG', ['Anna', 'Lea', 'Max']),
        'Der Haushalt „WG“ bleibt für Anna, Lea und Max mit der ganzen Liste '
            'erhalten. Deine Einträge bleiben dort, aber ohne deinen Namen.',
      ),
      (
        const FateDeleted('Zuhause'),
        'Du bist das letzte Mitglied. Deshalb wird der Haushalt „Zuhause“ mit '
            'Liste, Verlauf, Kategorien und Geschäften gelöscht.',
      ),
      (null, 'Du bist in keinem Haushalt, geteilte Daten gibt es nicht.'),
    ]) {
      testWidgets('${fate.runtimeType}: $text', (tester) async {
        account.fateResult = [?fate];
        await openDialog(tester);
        expect(find.text(text), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('account-delete-dialog')),
            matching: find.textContaining('Meine Daten exportieren'),
          ),
          fate == null ? findsNothing : findsOneWidget,
        );
      });
    }
  });

  testWidgets('a deleted account signs out locally with a notice', (
    tester,
  ) async {
    account.deleteResult = const AccountDeleted(AppleUnlink.manual);
    await openDialog(tester);
    await confirm(tester);
    await tapKey(tester, 'account-delete-confirm');

    expect(find.byKey(const ValueKey('account-delete-dialog')), findsNothing);
    expect(account.deleteCalls, 1);
    expect(auth.signOutScopes, [SignOutScope.local]);
    expect(cache.households, isEmpty);
    expect(cache.forgotten, greaterThan(0));
    expect(
      session.state,
      isA<SignedOut>().having(
        (s) => s.deleted?.removeAppleManually,
        'apple hint',
        isTrue,
      ),
    );
  });

  testWidgets('offline deletes nothing and stays signed in', (tester) async {
    account.deleteError = const AccountOffline();
    await openDialog(tester);
    await confirm(tester);
    await tapKey(tester, 'account-delete-confirm');

    expect(
      find.text(
        'Keine Internetverbindung. Dein Konto wurde nicht gelöscht. '
        'Versuche es erneut, sobald du online bist.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('account-delete-dialog')), findsOneWidget);
    expect(account.deleteCalls, 1);
    expect(auth.signOutScopes, isEmpty);
    expect(session.state, isNot(isA<SignedOut>()));
    expect(confirmEnabled(tester), isTrue, reason: 'retry is possible');
  });

  testWidgets('a server failure names its code', (tester) async {
    account.deleteError = const AccountFailed('delete_failed');
    await openDialog(tester);
    await confirm(tester);
    await tapKey(tester, 'account-delete-confirm');
    expect(
      find.text(
        'Löschen fehlgeschlagen (delete_failed). Dein Konto wurde nicht '
        'gelöscht.',
      ),
      findsOneWidget,
    );
    expect(auth.signOutScopes, isEmpty);
  });

  testWidgets('closing Apple’s sheet cancels the deletion', (tester) async {
    account.deleteError = const AppleReauthCanceled();
    await openDialog(tester);
    await confirm(tester);
    await tapKey(tester, 'account-delete-confirm');
    expect(
      find.text('Abgebrochen. Dein Konto wurde nicht gelöscht.'),
      findsOneWidget,
    );
    expect(auth.signOutScopes, isEmpty);
  });

  testWidgets('while deleting nothing can be pressed or dismissed', (
    tester,
  ) async {
    final gate = account.deleteGate = Completer<void>();
    await openDialog(tester);
    await confirm(tester);
    await tester.tap(find.byKey(const ValueKey('account-delete-confirm')));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(confirmEnabled(tester), isFalse);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('account-delete-cancel')),
          )
          .enabled,
      isFalse,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.byKey(const ValueKey('account-delete-dialog')), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(session.state, isA<SignedOut>());
    expect(account.deleteCalls, 1);
  });

  testWidgets('the start screen confirms the deletion', (tester) async {
    await pump(tester, const LoginScreen());
    expect(find.byKey(const ValueKey('account-deleted-notice')), findsNothing);

    await session.accountDeleted(
      const AccountDeletedNotice(removeAppleManually: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dein Konto wurde gelöscht.'), findsOneWidget);
    expect(find.textContaining('Entferne „Hummlist“'), findsOneWidget);
    expect(find.textContaining('Mit Apple anmelden'), findsOneWidget);
  });

  testWidgets('without the Apple hint when Apple was revoked', (tester) async {
    await pump(tester, const LoginScreen());
    await session.accountDeleted(
      const AccountDeletedNotice(removeAppleManually: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dein Konto wurde gelöscht.'), findsOneWidget);
    expect(find.textContaining('Mit Apple anmelden'), findsNothing);
  });

  testWidgets('the welcome screen offers deletion too', (tester) async {
    account.fateResult = const [];
    await pump(tester, const WelcomeScreen());
    // Below the brand and Step 1's two choices, past the bottom of the test
    // window and the list's build-ahead.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('account-delete')),
      200,
    );
    await tapKey(tester, 'account-delete');
    expect(
      find.text('Du bist in keinem Haushalt, geteilte Daten gibt es nicht.'),
      findsOneWidget,
    );
    await confirm(tester);
    await tapKey(tester, 'account-delete-confirm');
    expect(session.state, isA<SignedOut>());
  });

  testWidgets('a household that cannot be loaded blocks deletion', (
    tester,
  ) async {
    account.fateError = const AccountOffline();
    await openDialog(tester);
    expect(
      find.text(
        'Keine Internetverbindung. Was mit deinem Haushalt passiert, konnte '
        'nicht geladen werden.',
      ),
      findsOneWidget,
    );
    expect(confirmEnabled(tester), isFalse);
  });

  testWidgets('exporting saves the JSON under a dated name', (tester) async {
    await pump(tester, settings());
    await tapKey(tester, 'account-export');
    expect(account.exportCalls, 1);
    expect(saved, hasLength(1));
    expect(
      saved.single.fileName,
      matches(RegExp(r'^einkauf-daten-\d{4}-\d{2}-\d{2}\.json$')),
    );
    expect(saved.single.json, account.exportResult);
    expect(saved.single.origin, isNotNull);
    expect(find.text('Daten exportiert'), findsOneWidget);
  });

  testWidgets('a desktop export shows where the file went', (tester) async {
    savedPath = '/home/peter/Downloads/einkauf-daten-2026-10-24.json';
    await pump(tester, settings());
    await tapKey(tester, 'account-export');
    expect(find.text('Daten exportiert: $savedPath'), findsOneWidget);
  });

  testWidgets('an offline export says so and saves nothing', (tester) async {
    account.exportError = const AccountOffline();
    await pump(tester, settings());
    await tapKey(tester, 'account-export');
    expect(saved, isEmpty);
    expect(
      find.text(
        'Keine Internetverbindung. Deine Daten wurden nicht exportiert.',
      ),
      findsOneWidget,
    );
  });

  group('the account page (More: Konto)', () {
    testWidgets('shows who is signed in, export and deletion only', (
      tester,
    ) async {
      await pump(tester, settings());
      expect(find.text('peter@fg.test'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-export')), findsOneWidget);
      expect(find.byKey(const ValueKey('account-delete')), findsOneWidget);
      expect(find.text('MCP-SERVER'), findsNothing);
      expect(find.text('Zugriffstoken'), findsNothing);
    });

    testWidgets('the address is copied with its button, not selected', (
      tester,
    ) async {
      final copied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map<Object?, Object?>)['text']);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester, settings());
      final email = find.text('peter@fg.test');
      expect(
        find.ancestor(of: email, matching: find.byType(SelectableRegion)),
        findsNothing,
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('account-email-copy'))),
        isSemantics(
          isButton: true,
          tooltip: 'E-Mail-Adresse kopieren',
          hasTapAction: true,
        ),
        reason: 'screen readers announce the button by its purpose',
      );
      await tester.tap(find.byTooltip('E-Mail-Adresse kopieren'));
      await tester.pump();
      expect(copied, ['peter@fg.test']);
      expect(find.text('Kopiert'), findsOneWidget);
    });

    testWidgets('a sign-in without an email shows no address row', (
      tester,
    ) async {
      account.email = null;
      await pump(tester, settings());
      expect(find.byKey(const ValueKey('account-email')), findsNothing);
      expect(find.byKey(const ValueKey('account-delete')), findsOneWidget);
    });
  });

  group('a yearly plan keeps being billed (H-85)', () {
    Future<void> tapDelete(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('account-delete')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('account-delete')));
      await tester.pumpAndSettle();
    }

    testWidgets('the subscriber hears so first, with the store link', (
      tester,
    ) async {
      await pump(
        tester,
        settings(),
        premium: FakePremiumServer(
          mine: const MyYearlyPlan(subscriber: true, renewing: true),
        ),
      );
      await tapDelete(tester);
      expect(
        find.text(
          'Dein Jahresabo für Hummlist Premium läuft weiter und wird über dein '
          'Apple- bzw. Google-Konto abgerechnet, bis du es kündigst. Löschen '
          'oder Verlassen kündigt es nicht.',
        ),
        findsOneWidget,
      );
      expect(find.text('Abo verwalten'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-delete-dialog')), findsNothing);
      await tester.tap(find.text('Trotzdem fortfahren'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('account-delete-dialog')),
        findsOneWidget,
      );
    });

    testWidgets('also for a plan they pay for another household', (
      tester,
    ) async {
      await pump(
        tester,
        settings(),
        premium: FakePremiumServer(mine: const MyYearlyPlan(elsewhere: true)),
      );
      await tapDelete(tester);
      expect(
        find.byKey(const ValueKey('premium-billing-continues')),
        findsOneWidget,
      );
      // Abo verwalten leaves the deletion for later.
      await tester.tap(find.byKey(const ValueKey('premium-billing-manage')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-delete-dialog')), findsNothing);
    });

    testWidgets('another member of a billed household gets the short line', (
      tester,
    ) async {
      await pump(
        tester,
        settings(),
        premium: FakePremiumServer(
          mine: const MyYearlyPlan(householdBilled: true),
        ),
      );
      await tapDelete(tester);
      expect(
        find.text(
          'Ein Jahresabo für diesen Haushalt läuft weiter, bis es gekündigt '
          'wird.',
        ),
        findsOneWidget,
      );
      expect(find.text('Abo verwalten'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('premium-billing-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-delete-dialog')), findsNothing);
    });

    testWidgets('no plan, or the server unreachable: straight to deletion', (
      tester,
    ) async {
      await pump(
        tester,
        settings(),
        premium: FakePremiumServer()..mineFails = true,
      );
      await tapDelete(tester);
      expect(
        find.byKey(const ValueKey('account-delete-dialog')),
        findsOneWidget,
      );
    });
  });

  group('Hummlist Premium that ends with the account (job 68)', () {
    /// The dialog alone, with the archive UI's flag as [archiveTexts].
    Future<void> openWith(
      WidgetTester tester, {
      required bool archiveTexts,
      Locale locale = const Locale('de'),
    }) async {
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () => unawaited(
                showDialog<AccountDeleted>(
                  context: context,
                  builder: (_) => DeleteAccountDialog(
                    repository: account,
                    archiveTexts: archiveTexts,
                  ),
                ),
              ),
              child: const SizedBox.square(dimension: 40),
            ),
          ),
        ),
        locale: locale,
      );
      await tapKey(tester, 'open');
    }

    const premiumText =
        '„Zuhause“ hat Hummlist Premium. Es gehört zum Haushalt und endet mit '
        'ihm. Archivieren geht hier nicht, denn ein archivierter Haushalt wird '
        'mit deinem Konto gelöscht. Soll der Haushalt mit Premium bleiben, '
        'lade vorher jemanden ein und lösche dein Konto erst, wenn die Person '
        'beigetreten ist.';
    const releaseText =
        '„Zuhause“ hat Hummlist Premium. Das gehört zum Haushalt. Löschst du '
        'dein Konto, endet es. Soll es bleiben? Dann lad erst jemand ein. '
        'Warte, bis die Person beigetreten ist. Lösch dann dein Konto.';
    final ack = find.byKey(const ValueKey('account-delete-premium-ack'));

    testWidgets('the last member of an unlocked household confirms that '
        'Premium is not refunded before Delete works', (tester) async {
      account.fateResult = const [FateDeleted('Zuhause', unlocked: true)];
      await openWith(tester, archiveTexts: true);

      expect(find.text(premiumText), findsOneWidget);
      expect(
        find.text(
          'Ich weiß: Premium endet. Ich bekomme mein Geld nicht von selbst '
          'zurück.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('account-delete-refund-help')),
        findsOneWidget,
      );
      await confirm(tester);
      expect(confirmEnabled(tester), isFalse, reason: 'not acknowledged yet');

      await tapKey(tester, 'account-delete-premium-ack');
      expect(confirmEnabled(tester), isTrue);
      await tapKey(tester, 'account-delete-confirm');
      expect(account.deleteCalls, 1);
    });

    testWidgets('the refund help opens from the warning', (tester) async {
      account.fateResult = const [FateDeleted('Zuhause', unlocked: true)];
      await openWith(tester, archiveTexts: true);
      await tapKey(tester, 'account-delete-refund-help');
      expect(find.textContaining('reportaproblem.apple.com'), findsWidgets);
    });

    testWidgets('unticking the box disables Delete again', (tester) async {
      account.fateResult = const [FateDeleted('Zuhause', unlocked: true)];
      await openWith(tester, archiveTexts: true);
      await confirm(tester);
      await tapKey(tester, 'account-delete-premium-ack');
      await tapKey(tester, 'account-delete-premium-ack');
      expect(confirmEnabled(tester), isFalse);
    });

    testWidgets('a household without premium asks nothing more', (
      tester,
    ) async {
      account.fateResult = const [FateDeleted('Zuhause')];
      await openWith(tester, archiveTexts: true);
      expect(find.text(premiumText), findsNothing);
      expect(ack, findsNothing);
      await confirm(tester);
      expect(confirmEnabled(tester), isTrue);
    });

    testWidgets('with the archive UI off the last member is still warned, '
        'without archived households or the archive sentence (job 104)', (
      tester,
    ) async {
      account
        ..fateResult = const [FateDeleted('Zuhause', unlocked: true)]
        ..archived = [const ArchivedFate('Ferien', unlocked: true)];
      await openWith(tester, archiveTexts: false);
      expect(find.text(premiumText), findsNothing);
      expect(find.text(releaseText), findsOneWidget);
      expect(ack, findsOneWidget);
      expect(
        find.byKey(const ValueKey('account-delete-archived')),
        findsNothing,
      );
      await confirm(tester);
      expect(confirmEnabled(tester), isFalse);
      await tapKey(tester, 'account-delete-premium-ack');
      expect(confirmEnabled(tester), isTrue);
    });

    testWidgets('with the archive UI off an archived household with premium '
        'asks nothing', (tester) async {
      account
        ..fateResult = const [
          FateKept('Zuhause', ['Lea']),
        ]
        ..archived = [const ArchivedFate('Ferien', unlocked: true)];
      await openWith(tester, archiveTexts: false);
      expect(ack, findsNothing);
      await confirm(tester);
      expect(confirmEnabled(tester), isTrue);
    });

    testWidgets('an unlocked archived household goes too, and asks the same', (
      tester,
    ) async {
      account
        ..fateResult = const [
          FateKept('Zuhause', ['Lea']),
        ]
        ..archived = [const ArchivedFate('Ferien', unlocked: true)];
      await openWith(tester, archiveTexts: true);
      expect(
        find.text(
          'Dein archivierter Haushalt „Ferien“ wird mit deinem Konto '
          'gelöscht, und mit ihm sein Hummlist Premium.',
        ),
        findsOneWidget,
      );
      expect(find.text(premiumText), findsNothing, reason: 'Lea keeps it');
      await confirm(tester);
      expect(confirmEnabled(tester), isFalse);
      await tapKey(tester, 'account-delete-premium-ack');
      expect(confirmEnabled(tester), isTrue);
    });

    testWidgets('archived households without premium are named, nothing '
        'more is asked', (tester) async {
      account
        ..fateResult = const []
        ..archived = [const ArchivedFate('Ferien'), const ArchivedFate('Büro')];
      await openWith(tester, archiveTexts: true);
      expect(
        find.text(
          'Deine archivierten Haushalte „Ferien“ und „Büro“ werden mit deinem '
          'Konto gelöscht.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Meine Daten exportieren'), findsOneWidget);
      expect(ack, findsNothing);
      await confirm(tester);
      expect(confirmEnabled(tester), isTrue);
    });

    for (final (offer, text) in [(true, premiumText), (false, releaseText)]) {
      testWidgets('from the account page with the Premium sale '
          '${offer ? 'open' : 'closed'} and the archive UI off, the warning '
          'is shown${offer ? '' : ' without the archive sentence'}', (
        tester,
      ) async {
        account.fateResult = const [FateDeleted('Zuhause', unlocked: true)];
        await pump(
          tester,
          settings(),
          premium: FakePremiumServer(offer: offer),
        );
        await tapKey(tester, 'account-delete');
        expect(find.text(text), findsOneWidget);
        await confirm(tester);
        expect(confirmEnabled(tester), isFalse);
      });
    }

    // Job 104: release builds (archive UI and Premium sale off) warn whenever
    // the household has premium now. The dialog only gets leaves_unlocked()'s
    // answer; that gifted, Lifetime and yearly all count is proven in
    // supabase/tests/leaves_unlocked.test.sql.
    for (final (premium, fate, warned) in [
      (
        'premium of any kind',
        const FateDeleted('Zuhause', unlocked: true),
        true,
      ),
      ('no premium', const FateDeleted('Zuhause'), false),
      ('premium, but Lea stays', const FateKept('Zuhause', ['Lea']), false),
    ]) {
      testWidgets('in a release build, deleting with $premium '
          '${warned ? 'warns' : 'does not warn'}', (tester) async {
        account.fateResult = [fate];
        await pump(
          tester,
          settings(),
          premium: FakePremiumServer(offer: false),
        );
        await tapKey(tester, 'account-delete');
        expect(find.text(releaseText), warned ? findsOneWidget : findsNothing);
        expect(ack, warned ? findsOneWidget : findsNothing);
        expect(
          find.byKey(const ValueKey('account-delete-refund-help')),
          warned ? findsOneWidget : findsNothing,
        );
        await confirm(tester);
        expect(confirmEnabled(tester), !warned);
        if (warned) {
          await tapKey(tester, 'account-delete-premium-ack');
          await tapKey(tester, 'account-delete-confirm');
          expect(account.deleteCalls, 1);
        }
      });
    }

    testWidgets('in English, without the archive texts (job 104)', (
      tester,
    ) async {
      account.fateResult = const [FateDeleted('Home', unlocked: true)];
      await openWith(tester, archiveTexts: false, locale: const Locale('en'));
      expect(
        find.text(
          '“Home” has Hummlist Premium. It belongs to the household. If you '
          'delete your account, it ends. Do you want to keep it? Then ask '
          'someone to join first. Wait until they have joined. Then delete '
          'your account.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'I know: Premium ends. I will not get my money back on its own.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('in English', (tester) async {
      account.fateResult = const [FateDeleted('Home', unlocked: true)];
      await openWith(tester, archiveTexts: true, locale: const Locale('en'));
      expect(
        find.text(
          '“Home” has Hummlist Premium. It belongs to the household and ends '
          "with it. Archiving isn't possible here, because an archived "
          'household is deleted with your account. To keep the household '
          'with Premium, invite someone first and delete your account only '
          'after they have joined.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'I know: Premium ends. I will not get my money back on its own.',
        ),
        findsOneWidget,
      );
    });
  });
}
