import 'package:family_groceries/core/screen_names.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  const household = InHousehold('u', Household(id: 'h', name: 'H'), [
    Household(id: 'h', name: 'H'),
  ]);
  const waiting = NeedsHousehold(
    'u',
    requests: [JoinRequest(id: 'r', householdId: 'c', householdName: 'C')],
  );
  const consent = '/oauth/consent?authorization_id=abc';
  const next = 'next=%2Foauth%2Fconsent%3Fauthorization_id%3Dabc';
  const cases = <(Session, String, String?)>[
    (SessionLoading(), '/', null),
    // Job 168b: signed out, the guided start's first screen.
    (SignedOut(), '/', '/start'),
    (SignedOut(), '/start', null),
    (SignedOut(), '/start/who', '/start'),
    (SignedOut(), '/login', null),
    (SignedOut(), '/join/ABCD2345', '/login?invite=ABCD2345'),
    (NeedsHousehold('u'), '/start', '/welcome'),
    (NeedsHousehold('u'), '/start/who', '/welcome'),
    (household, '/start', '/'),
    (household, '/start/invite', '/'),
    // Job 22: an invite skips Step 1 and opens the join screen.
    (NeedsHousehold('u'), '/login?invite=ABCD2345', '/join/ABCD2345'),
    (NeedsHousehold('u'), '/', '/welcome'),
    (NeedsHousehold('u'), '/join/ABCD2345', null),
    (NeedsHousehold('u'), '/welcome?invite=ABCD2345', '/join/ABCD2345'),
    (NeedsHousehold('u'), '/welcome', null),
    (NeedsHousehold('u'), '/join', null),
    (NeedsHousehold('u'), '/welcome/invite', '/welcome'),
    (NeedsHousehold('u'), '/more/invites', '/welcome?next=%2Fmore%2Finvites'),
    // Job 169b W3 M: a join request waits instead of Willkommen; the
    // guided start (a draft) leads it (job 168c).
    (waiting, '/', '/welcome/waiting'),
    (waiting, '/welcome', '/welcome/waiting'),
    (waiting, '/welcome/waiting', null),
    (waiting, '/join/ABCD2345', null),
    (NeedsHousehold('u'), '/welcome/waiting', '/welcome'),
    (household, '/welcome/waiting', '/'),
    (household, '/join', null),
    (household, '/more/invites', null),
    // Job 169b: one more household, its invite step and the household
    // page, in one only.
    (household, '/households/new', null),
    (household, '/households/new/invite', null),
    (household, '/more/household', null),
    (NeedsHousehold('u'), '/households/new', '/welcome'),
    (SignedOut(), '/households/new', '/start'),
    (SignedOut(), '/welcome', '/start'),
    // Job 462: an app link to the code entry, after sign-in.
    (SignedOut(), '/join', '/login?next=%2Fjoin'),
    (household, '/login', '/'),
    (household, '/welcome', '/'),
    // An invite in any location opens the join screen.
    (household, '/welcome?invite=ABCD2345', '/join/ABCD2345'),
    (household, '/login?invite=ABCD2345', '/join/ABCD2345'),
    (household, '/join/ABCD2345', null),
    (household, '/?code=pkce', '/'),
    (household, '/', null),
    (household, '/settings', null),
    (household, '/settings?section=account', null),
    // An invite link opens the join page wherever it points.
    (household, '/settings?invite=ABCD2345', '/join/ABCD2345'),
    (household, '/more', null),
    // Job 85: Nutzungsdaten is a page of More; the old Rechtliches link
    // stays in the tab for the router to send to More.
    (household, '/more/usage-data', null),
    (household, '/more/legal', null),
    (SignedOut(), '/more/usage-data', '/login?next=%2Fmore%2Fusage-data'),
    // Job 78: the List tab's Anpassen pages.
    (household, '/edit', null),
    (household, '/edit/lidl', null),
    (household, '/edit/none', null),
    (household, '/edit/lidl/more', '/'),
    (NeedsHousehold('u'), '/edit/lidl', '/welcome?next=%2Fedit%2Flidl'),
    (SignedOut(), '/edit', '/login?next=%2Fedit'),
    (household, '/more/access', null),
    (household, '/more/account', null),
    (household, '/more/account?invite=ABCD2345', '/join/ABCD2345'),
    (SignedOut(), '/more/account', '/login?next=%2Fmore%2Faccount'),
    (household, '/more/settings', null),
    // Snacklist Lifetime is for a household: never signed out or before one
    // (job 66: there after sign-in and onboarding).
    (household, '/more/lifetime', null),
    (SignedOut(), '/more/lifetime', '/login?next=%2Fmore%2Flifetime'),
    (NeedsHousehold('u'), '/more/lifetime', '/welcome?next=%2Fmore%2Flifetime'),
    (household, '/more/settings/language', null),
    (
      SignedOut(),
      '/more/settings/language',
      '/login?next=%2Fmore%2Fsettings%2Flanguage',
    ),
    (NeedsHousehold('u'), '/more/access', '/welcome?next=%2Fmore%2Faccess'),
    (household, '/more/nothing-here', '/'),
    (SignedOut(), '/more', '/login?next=%2Fmore'),
    (SignedOut(), '/settings', '/start'),
    (SignedOut(), consent, '/login?$next'),
    (SignedOut(), '/login?$next', null),
    (NeedsHousehold('u'), '/login?$next', '/welcome?$next'),
    (NeedsHousehold('u'), consent, '/welcome?$next'),
    (NeedsHousehold('u'), '/welcome?$next', null),
    (NeedsHousehold('u'), '/start/who?$next', '/welcome?$next'),
    (NeedsHousehold('u'), '/join?$next', null),
    (NeedsHousehold('u'), '/join/ABCD2345?$next', null),
    (household, '/start/who?$next', consent),
    (household, '/join?$next', consent),
    (household, '/login?$next', consent),
    (household, '/welcome?$next', consent),
    (household, consent, null),
    (household, '/oauth/consent', null),
    (household, '$consent&code=pkce', null),
    (SignedOut(), '/login?next=https%3A%2F%2Fevil.example', '/login'),
    (SignedOut(), '/login?next=%2F%2Fevil.example%2Foauth%2Fconsent', '/login'),
    (household, '/login?next=https%3A%2F%2Fevil.example', '/'),
    (household, '/welcome?next=%2Fsettings', '/'),
    (NeedsHousehold('u'), '/welcome?next=%2Fsettings', '/welcome'),
  ];
  for (final (session, from, to) in cases) {
    test('${session.runtimeType} at $from goes to ${to ?? 'stays'}', () {
      expect(authRedirect(session, Uri.parse(from)), to);
    });
  }

  // Job 22: the invite kept on the device stands in for one in the
  // location, which the mobile apps lose: a magic link or Apple on Android
  // returns through com.snacklist.app://login-callback, and a cold start
  // opens at `/`.
  const pending = <(Session, String, String?)>[
    (SignedOut(), '/', '/login?invite=ABCD2345'),
    (SignedOut(), '/login', '/login?invite=ABCD2345'),
    (SignedOut(), '/login?invite=ABCD2345', null),
    (NeedsHousehold('u'), '/', '/join/ABCD2345'),
    (NeedsHousehold('u'), '/?code=pkce', '/join/ABCD2345'),
    (NeedsHousehold('u'), '/welcome', '/join/ABCD2345'),
    (NeedsHousehold('u'), '/join/ABCD2345', null),
    (household, '/', '/join/ABCD2345'),
    (household, '/more', '/join/ABCD2345'),
    (household, '/join/ABCD2345', null),
    // A link in the location wins over an older pending one.
    (NeedsHousehold('u'), '/join/WXYZ6789', null),
    (household, '/login?invite=WXYZ6789', '/join/WXYZ6789'),
  ];
  for (final (session, from, to) in pending) {
    test('pending invite: ${session.runtimeType} at $from goes to '
        '${to ?? 'stays'}', () {
      expect(
        authRedirect(session, Uri.parse(from), pendingInvite: 'ABCD2345'),
        to,
      );
    });
  }

  test('pending invite: asked for consent first, carried along', () {
    expect(
      authRedirect(
        const NeedsHousehold('u'),
        Uri.parse('/'),
        askConsent: true,
        pendingInvite: 'ABCD2345',
      ),
      '/analytics-consent?invite=ABCD2345',
    );
  });

  // The URIs the platforms hand go_router: a universal link / App Link
  // (the path of https://app.snacklist.app/join/<code>) and the auth
  // callback, whose path is empty.
  test('a universal link names its invite', () {
    expect(
      inviteIn(Uri.parse('https://app.snacklist.app/join/ABCD2345')),
      'ABCD2345',
    );
    expect(
      authRedirect(
        const SignedOut(),
        Uri.parse('https://app.snacklist.app/join/ABCD2345'),
      ),
      '/login?invite=ABCD2345',
    );
  });

  test(
    'the custom-scheme callback has no invite; the pending one leads on',
    () {
      final callback = Uri.parse('com.snacklist.app://login-callback?code=abc');
      expect(inviteIn(callback), isNull);
      expect(
        authRedirect(
          const NeedsHousehold('u'),
          callback,
          pendingInvite: 'ABCD2345',
        ),
        '/join/ABCD2345',
      );
      expect(authRedirect(const NeedsHousehold('u'), callback), '/welcome');
    },
  );

  // Job 29d: Zugänge and Konto are two pages; the links of the one page
  // they were before go to the right one.
  for (final (from, to) in const [
    ('/settings', '/more/access'),
    ('/settings?section=account', '/more/account'),
    ('/settings?section=access', '/more/access'),
    ('/settings?section=', '/more/access'),
  ]) {
    test('the old link $from goes to $to', () {
      expect(legacySettingsRedirect(Uri.parse(from)), to);
    });
  }

  // Job 19: an install that has not decided on analytics is asked right
  // after sign-in, before onboarding and before the list; an invite rides
  // along every hop, and MCP's OAuth tab is not interrupted.
  const ask = '/analytics-consent';
  const asking = <(Session, String, String?)>[
    (SessionLoading(), '/', null),
    (SignedOut(), '/', '/start'),
    (SignedOut(), ask, '/start'),
    (SignedOut(), '/login', null),
    (SignedOut(), '/join/ABCD2345', '/login?invite=ABCD2345'),
    (NeedsHousehold('u'), '/login', ask),
    (NeedsHousehold('u'), '/', ask),
    (NeedsHousehold('u'), '/welcome', ask),
    (NeedsHousehold('u'), '/start/who', ask),
    (NeedsHousehold('u'), ask, null),
    (NeedsHousehold('u'), '/login?invite=ABCD2345', '$ask?invite=ABCD2345'),
    (NeedsHousehold('u'), '/join/ABCD2345', '$ask?invite=ABCD2345'),
    (NeedsHousehold('u'), '$ask?invite=ABCD2345', null),
    (household, '/login', ask),
    (household, '/', ask),
    (household, '/more', ask),
    (household, ask, null),
    (household, '/login?invite=ABCD2345', '$ask?invite=ABCD2345'),
    (household, '/join/ABCD2345', '$ask?invite=ABCD2345'),
    (household, '$ask?invite=ABCD2345', null),
    // MCP's OAuth consent keeps its `next` and is not interrupted.
    (SignedOut(), consent, '/login?$next'),
    (NeedsHousehold('u'), '/login?$next', '/welcome?$next'),
    (NeedsHousehold('u'), consent, '/welcome?$next'),
    (household, '/login?$next', consent),
    (household, consent, null),
  ];
  for (final (session, from, to) in asking) {
    test('asking consent: ${session.runtimeType} at $from goes to '
        '${to ?? 'stays'}', () {
      expect(authRedirect(session, Uri.parse(from), askConsent: true), to);
    });
  }

  // Once decided, the consent page hands over: onboarding, the join page
  // of the invite, or the list.
  const decided = <(Session, String, String?)>[
    (NeedsHousehold('u'), ask, '/welcome'),
    (NeedsHousehold('u'), '$ask?invite=ABCD2345', '/join/ABCD2345'),
    (household, ask, '/'),
    (household, '$ask?invite=ABCD2345', '/join/ABCD2345'),
    (SignedOut(), ask, '/start'),
  ];
  for (final (session, from, to) in decided) {
    test('decided: ${session.runtimeType} at $from goes to $to', () {
      expect(authRedirect(session, Uri.parse(from)), to);
    });
  }

  // Job 66: the app links (deep_links.dart). Signed in they open their
  // screen; `/list`, `/add` and `/stores/<id>` are the list (which then
  // opens the sheet or shows the store, list_link.dart).
  const links = <(Session, String, String?)>[
    (household, '/list', '/'),
    (household, '/add', '/'),
    (household, '/stores/s1', '/'),
    (household, '/more', null),
    (household, '/more/invites', null),
    (household, '/more/settings', null),
    (household, '/join/ABCD2345', null),
    (household, '/nope', '/'),
    (SignedOut(), '/nope', '/start'),
    // A More page that isn't one: no `next` to nowhere.
    (SignedOut(), '/more/nothing-here', '/start'),
    (household, '/login?next=%2Fmore%2Fnothing-here', '/'),
    (household, 'https://app.snacklist.app/add', '/'),
    // Signed out, sign-in continues there.
    (SignedOut(), '/more/invites', '/login?next=%2Fmore%2Finvites'),
    (SignedOut(), '/more/settings', '/login?next=%2Fmore%2Fsettings'),
    (SignedOut(), '/add', '/login?next=%2Fadd'),
    (SignedOut(), '/stores/s1', '/login?next=%2Fstores%2Fs1'),
    (SignedOut(), '/list', '/login?next=%2Flist'),
    (SignedOut(), 'https://app.snacklist.app/add', '/login?next=%2Fadd'),
    (
      SignedOut(),
      '/more/lifetime?from=x',
      '/login?next=%2Fmore%2Flifetime%3Ffrom%3Dx',
    ),
    (SignedOut(), '/login?next=%2Fadd', null),
    (household, '/login?next=%2Fadd', '/add'),
    (household, '/login?next=%2Fmore%2Finvites', '/more/invites'),
    (
      household,
      '/login?next=%2Fmore%2Flifetime%3Ffrom%3Dx',
      '/more/lifetime?from=x',
    ),
    // Without a household: through onboarding, then there.
    (NeedsHousehold('u'), '/login?next=%2Fadd', '/welcome?next=%2Fadd'),
    (NeedsHousehold('u'), '/add', '/welcome?next=%2Fadd'),
    (NeedsHousehold('u'), '/welcome?next=%2Fadd', null),
    (household, '/start/who?next=%2Fadd', '/add'),
    (household, '/welcome?next=%2Fmore%2Finvites', '/more/invites'),
    // An invite link keeps to its own way, `next` never carries one.
    (SignedOut(), '/login?next=%2Fjoin%2FABCD2345', '/login'),
    (household, '/login?next=%2Fjoin%2FABCD2345', '/'),
    // No open redirect: only a same-origin app link.
    (SignedOut(), '/login?next=https%3A%2F%2Fevil.example', '/login'),
    (SignedOut(), '/login?next=%2F%2Fevil.example%2Fmore', '/login'),
    (SignedOut(), '/login?next=%2Fnope', '/login'),
    (household, '/login?next=https%3A%2F%2Fevil.example', '/'),
    (household, '/login?next=%2F%2Fevil.example%2Fmore', '/'),
    (household, '/login?next=%2Fnope', '/'),
    (
      NeedsHousehold('u'),
      '/welcome?next=%2F%2Fevil.example%2Fmore',
      '/welcome',
    ),
    // Job 462: the screens the app host claims since, signed out after
    // sign-in, and without a household after setting one up.
    (SignedOut(), '/edit/lidl', '/login?next=%2Fedit%2Flidl'),
    (SignedOut(), '/edit/lidl/more', '/start'),
    (SignedOut(), '/history', '/login?next=%2Fhistory'),
    (SignedOut(), '/history/trip/t1', '/login?next=%2Fhistory%2Ftrip%2Ft1'),
    (SignedOut(), '/trip/t1', '/login?next=%2Ftrip%2Ft1'),
    (household, '/login?next=%2Fedit%2Flidl', '/edit/lidl'),
    (household, '/login?next=%2Fhistory', '/history'),
    (household, '/login?next=%2Fhistory%2Ftrip%2Ft1', '/history/trip/t1'),
    (household, '/login?next=%2Ftrip%2Ft1', '/trip/t1'),
    (household, '/history', null),
    (household, '/history/trip/t1', null),
    (household, '/trip/t1', null),
    (NeedsHousehold('u'), '/history', '/welcome?next=%2Fhistory'),
    (household, '/welcome?next=%2Ftrip%2Ft1', '/trip/t1'),
    // The code entry is a step before a household: straight there.
    (household, '/login?next=%2Fjoin', '/join'),
    (NeedsHousehold('u'), '/login?next=%2Fjoin', '/join'),
    (NeedsHousehold('u'), '/analytics-consent?next=%2Fjoin', '/join'),
    // One more household is none to continue to: without one the guided
    // start sets up the first.
    (SignedOut(), '/households/new/invite', '/start'),
    (SignedOut(), '/login?next=%2Fhouseholds%2Fnew', '/login'),
    (household, '/login?next=%2Fhouseholds%2Fnew', '/'),
  ];
  for (final (session, from, to) in links) {
    test('link: ${session.runtimeType} at $from goes to ${to ?? 'stays'}', () {
      expect(authRedirect(session, Uri.parse(from)), to);
    });
  }

  // Job 462: the guides of snacklist.app open in the app; public, they
  // show as they are, before any gate.
  const guides = [
    '/de/anleitungen',
    '/de/anleitungen/siri-kurzbefehl',
    '/en/guides',
    '/en/guides/siri-shortcut',
    'https://snacklist.app/de/anleitungen/alexa',
    'com.snacklist.app://open/en/guides/widget',
  ];
  for (final session in const <Session>[
    SessionLoading(),
    SignedOut(),
    NeedsHousehold('u'),
    waiting,
    household,
  ]) {
    test('a guide shows ${session.runtimeType}, before any gate', () {
      for (final path in guides) {
        expect(authRedirect(session, Uri.parse(path)), isNull, reason: path);
        expect(
          authRedirect(
            session,
            Uri.parse(path),
            askConsent: true,
            askName: true,
            pendingInvite: 'ABCD2345',
          ),
          isNull,
          reason: path,
        );
      }
    });
  }

  test('only the guides paths are guides', () {
    for (final path in ['/de/guides', '/fr/guides', '/en/anleitungen', '/de']) {
      expect(authRedirect(const SignedOut(), Uri.parse(path)), '/start');
    }
  });

  test("the join page hands a bare /join to the web app's code entry", () {
    final handed = Uri.parse('/?next=%2Fjoin');
    expect(authRedirect(const SignedOut(), handed), '/login?next=%2Fjoin');
    expect(authRedirect(const NeedsHousehold('u'), handed), '/join');
    expect(authRedirect(household, handed), '/join');
  });

  test('a Markdown twin opens its guide, a deeper path the index', () {
    for (final session in const [SignedOut(), household]) {
      expect(
        authRedirect(session, Uri.parse('/de/anleitungen/alexa.md')),
        '/de/anleitungen/alexa',
      );
      expect(authRedirect(session, Uri.parse('/en/guides/a/b')), '/en/guides');
      expect(
        authRedirect(session, Uri.parse('/de/anleitungen/alexa.html#setup')),
        '/de/anleitungen/alexa#setup',
      );
    }
  });

  test('a guide is never a link sign-in continues to', () {
    expect(
      authRedirect(const SignedOut(), Uri.parse('/login?next=%2Fen%2Fguides')),
      '/login',
    );
  });

  // Decision C: the browser's "Open in the app" on iOS uses the sign-in
  // scheme with the host `open`; it routes like the https link.
  test('com.snacklist.app://open/join/<code> routes like the invite link', () {
    for (final session in const <Session>[
      SignedOut(),
      NeedsHousehold('u'),
      waiting,
      household,
    ]) {
      final https = authRedirect(
        session,
        Uri.parse('https://app.snacklist.app/join/ABCD2345'),
      );
      expect(
        authRedirect(
          session,
          Uri.parse('com.snacklist.app://open/join/ABCD2345'),
        ),
        https,
        reason: '${session.runtimeType}',
      );
      expect(https, switch (session) {
        SignedOut() => '/login?invite=ABCD2345',
        _ => '/join/ABCD2345',
      });
    }
    expect(
      inviteIn(Uri.parse('com.snacklist.app://open/join/ABCD2345')),
      'ABCD2345',
    );
  });

  test('the sign-in callback is no link and no invite', () {
    final callback = Uri.parse('com.snacklist.app://login-callback?code=abc');
    expect(inviteIn(callback), isNull);
    expect(authRedirect(const SignedOut(), callback), '/start');
    expect(authRedirect(const NeedsHousehold('u'), callback), '/welcome');
    expect(authRedirect(household, callback), '/');
  });

  test('a link next is asked for consent first, and carried', () {
    expect(
      authRedirect(
        household,
        Uri.parse('/login?next=%2Fadd'),
        askConsent: true,
      ),
      '/analytics-consent?next=%2Fadd',
    );
    expect(
      authRedirect(
        const NeedsHousehold('u'),
        Uri.parse('/more/invites'),
        askConsent: true,
      ),
      '/analytics-consent?next=%2Fmore%2Finvites',
    );
    expect(
      authRedirect(household, Uri.parse('/analytics-consent?next=%2Fadd')),
      '/add',
    );
    expect(
      authRedirect(
        const NeedsHousehold('u'),
        Uri.parse('/analytics-consent?next=%2Fadd'),
      ),
      '/welcome?next=%2Fadd',
    );
  });

  // Job 486: a sign-out opens the start screen, „Ich habe schon ein Konto“
  // the sign-in with „Neu bei Snacklist?“.
  test('a sign-out opens the start screen and carries no link', () {
    expect(
      authRedirect(
        const SignedOut(),
        Uri.parse('/more/account'),
        justSignedOut: true,
      ),
      '/start',
    );
    expect(
      authRedirect(
        const SignedOut(),
        Uri.parse('/welcome?next=%2Fmore%2Finvites'),
        justSignedOut: true,
        pendingNext: '/more/invites',
      ),
      '/start',
    );
  });

  test('a sign-out keeps an invite and an account deletion its notice on '
      'the sign-in', () {
    expect(
      authRedirect(
        const SignedOut(),
        Uri.parse('/your-name?invite=ABCD2345'),
        justSignedOut: true,
      ),
      '/login?invite=ABCD2345',
    );
    expect(
      authRedirect(
        const SignedOut(
          deleted: AccountDeletedNotice(removeAppleManually: false),
        ),
        Uri.parse('/more/account'),
        justSignedOut: true,
      ),
      '/login',
    );
    // Its „Neu bei Snacklist?“ opens the start screen, not the sign-in again.
    expect(
      authRedirect(
        const SignedOut(
          deleted: AccountDeletedNotice(removeAppleManually: false),
        ),
        Uri.parse('/start'),
      ),
      isNull,
    );
  });

  test('„Neu bei Snacklist?“ from the sign-in for a link: the guided start '
      'carries the link', () {
    expect(
      authRedirect(const SignedOut(), Uri.parse('/start?next=%2Fadd')),
      isNull,
    );
    expect(
      authRedirect(const SignedOut(), Uri.parse('/start'), pendingNext: '/add'),
      '/start?next=%2Fadd',
    );
    expect(
      authRedirect(
        const SignedOut(),
        Uri.parse('/start?next=%2Fadd'),
        draft: const OnboardingDraft(step: OnboardingStep.who),
      ),
      '/start/who?next=%2Fadd',
    );
    // Not going to the guided start, a link still asks for the sign-in.
    expect(
      authRedirect(const SignedOut(), Uri.parse('/'), pendingNext: '/add'),
      '/login?next=%2Fadd',
    );
    expect(
      authRedirect(const SignedOut(), Uri.parse('/login?next=%2Fadd')),
      isNull,
    );
  });

  // The redirect's memory (buildRouter): a sign-in that leaves the app
  // comes back at `/` and the link leads on from memory; a sign-out
  // forgets it.
  group('RedirectMemory', () {
    test('a link survives the sign-in callback at /, once', () {
      final memory = RedirectMemory();
      final callback = Uri.parse('com.snacklist.app://login-callback?code=a');
      expect(
        memory.redirect(const SignedOut(), Uri.parse('/add')),
        '/login?next=%2Fadd',
      );
      expect(
        memory.redirect(const SignedOut(), callback),
        '/login?next=%2Fadd',
      );
      expect(memory.redirect(household, callback), '/add');
      expect(memory.redirect(household, Uri.parse('/')), isNull);
    });

    test('without a household it rides along onboarding', () {
      final memory = RedirectMemory();
      expect(
        memory.redirect(const SignedOut(), Uri.parse('/more/invites')),
        '/login?next=%2Fmore%2Finvites',
      );
      expect(
        memory.redirect(const NeedsHousehold('u'), Uri.parse('/')),
        '/welcome?next=%2Fmore%2Finvites',
      );
    });

    test('a sign-out at a link forgets it and carries none', () {
      final memory = RedirectMemory();
      expect(memory.redirect(household, Uri.parse('/more/account')), isNull);
      expect(
        memory.redirect(const SignedOut(), Uri.parse('/more/account')),
        '/start',
      );
      // Job 486: read again at the sign-out's location before the start
      // screen shows, it is still no link (it hid „Neu bei Snacklist?“).
      expect(
        memory.redirect(const SignedOut(), Uri.parse('/more/account')),
        '/start',
      );
      expect(memory.redirect(const SignedOut(), Uri.parse('/start')), isNull);
      expect(memory.redirect(const SignedOut(), Uri.parse('/login')), isNull);
      expect(memory.redirect(const SignedOut(), Uri.parse('/')), '/start');
    });

    test("a sign-out at the start screen itself lets „Los geht's“ go on", () {
      const draft = OnboardingDraft(step: OnboardingStep.who);
      final memory = RedirectMemory()
        ..redirect(const NeedsHousehold('u'), Uri.parse('/start'));
      expect(memory.redirect(const SignedOut(), Uri.parse('/start')), isNull);
      expect(
        memory.redirect(const SignedOut(), Uri.parse('/start'), draft: draft),
        '/start/who',
      );
    });

    test('after the start screen showed, a link opened there asks for the '
        'sign-in again', () {
      final memory = RedirectMemory()
        ..redirect(household, Uri.parse('/more/account'))
        ..redirect(const SignedOut(), Uri.parse('/more/account'))
        ..redirect(const SignedOut(), Uri.parse('/start'));
      expect(
        memory.redirect(const SignedOut(), Uri.parse('/more/account')),
        '/login?next=%2Fmore%2Faccount',
      );
    });

    test('signed out, a link opened later still continues', () {
      final memory = RedirectMemory()
        ..redirect(household, Uri.parse('/'))
        ..redirect(const SignedOut(), Uri.parse('/'));
      expect(
        memory.redirect(const SignedOut(), Uri.parse('/stores/s1')),
        '/login?next=%2Fstores%2Fs1',
      );
    });

    test('a /join link without a household opens the code entry once', () {
      final memory = RedirectMemory();
      expect(
        memory.redirect(const SignedOut(), Uri.parse('/join')),
        '/login?next=%2Fjoin',
      );
      expect(
        memory.redirect(const NeedsHousehold('u'), Uri.parse('/')),
        '/join',
      );
      expect(
        memory.redirect(const NeedsHousehold('u'), Uri.parse('/join')),
        isNull,
      );
      // Back from the code entry goes to `/`: the welcome screen, not a trap.
      expect(
        memory.redirect(const NeedsHousehold('u'), Uri.parse('/')),
        '/welcome',
      );
      // Joined, the list opens, not the code entry again.
      expect(memory.redirect(household, Uri.parse('/')), isNull);
    });

    test('a sign-out before the link was used drops it', () {
      final memory = RedirectMemory()
        ..redirect(const SignedOut(), Uri.parse('/add'))
        ..redirect(const NeedsHousehold('u'), Uri.parse('/'));
      expect(memory.redirect(const SignedOut(), Uri.parse('/')), '/start');
      expect(memory.redirect(const SignedOut(), Uri.parse('/start')), isNull);
    });
  });

  // Job 168b: a guided start under way. The screens move on by changing the
  // draft; the router shows its step, signed out up to the account, signed
  // in without a household up to the setup, and in the household the setup
  // and the invite step until it is left.
  const stores = OnboardingDraft(step: OnboardingStep.stores);
  const created = OnboardingDraft(
    step: OnboardingStep.invite,
    userId: 'u',
    householdId: 'h',
  );
  final drafts = <(Session, String, OnboardingDraft, bool, String?)>[
    (const SignedOut(), '/', stores, false, '/start/stores'),
    (const SignedOut(), '/start', stores, false, '/start/stores'),
    (const SignedOut(), '/start/who', stores, false, '/start/stores'),
    (const SignedOut(), '/start/stores', stores, false, null),
    // „Stattdessen anmelden“: the draft waits.
    (const SignedOut(), '/login', stores, false, null),
    (
      const SignedOut(),
      '/join/ABCD2345',
      stores,
      false,
      '/login?invite=ABCD2345',
    ),
    (
      const SignedOut(),
      '/start',
      const OnboardingDraft(),
      true,
      '/start/usage',
    ),
    (const SignedOut(), '/start', const OnboardingDraft(), false, '/start/who'),
    (
      const SignedOut(),
      '/',
      const OnboardingDraft(step: OnboardingStep.setup),
      false,
      '/start/account',
    ),
    (const NeedsHousehold('u'), '/', stores, false, '/start/stores'),
    (const NeedsHousehold('u'), '/welcome', stores, false, '/start/stores'),
    (
      const NeedsHousehold('u'),
      '/start/account',
      const OnboardingDraft(step: OnboardingStep.account),
      false,
      '/start/setup',
    ),
    (
      const NeedsHousehold('u'),
      '/welcome?$next',
      stores,
      false,
      '/start/stores?$next',
    ),
    (const NeedsHousehold('u'), '/join/ABCD2345', stores, false, null),
    (household, '/', stores, false, '/start/setup'),
    (household, '/', created, false, '/start/invite'),
    (household, '/start/invite', created, false, null),
    // A link the setup went on to stays; the list brings the step back.
    (household, '/more/settings', created, false, null),
    (household, '/edit', created, false, null),
    (
      household,
      '/',
      const OnboardingDraft(
        step: OnboardingStep.setup,
        userId: 'u',
        householdId: 'h',
      ),
      false,
      '/start/setup',
    ),
    // The setup finishes before an MCP authorization opens.
    (household, '/start/setup?$next', stores, false, null),
    (household, '/start/invite?$next', created, false, consent),
    // A draft of another household is not this one's.
    (
      const InHousehold('u', Household(id: 'other', name: 'O'), [
        Household(id: 'other', name: 'O'),
      ]),
      '/',
      created,
      false,
      null,
    ),
  ];
  for (final (session, from, draft, ask, to) in drafts) {
    test('draft at ${draft.step.name}${draft.created ? ' (created)' : ''}: '
        '${session.runtimeType} at $from goes to ${to ?? 'stays'}', () {
      expect(
        authRedirect(session, Uri.parse(from), draft: draft, askConsent: ask),
        to,
      );
    });
  }

  test('a link the setup went on to stays; the list brings the invite step '
      'back', () {
    final memory = RedirectMemory();
    expect(
      memory.redirect(
        household,
        Uri.parse('/start/invite?next=%2Fmore%2Fsettings'),
        draft: created,
      ),
      '/more/settings',
    );
    expect(
      memory.redirect(household, Uri.parse('/more/settings'), draft: created),
      isNull,
    );
    expect(
      memory.redirect(household, Uri.parse('/'), draft: created),
      '/start/invite',
    );
  });

  test('every guided start step has its screen name', () {
    for (final step in OnboardingStep.values) {
      final name = screenNameOf(Uri.parse(onboardingPath(step)));
      expect(name, 'onboarding_${step.name}');
      expect(screenNames, contains(name));
    }
    expect(screenNameOf(Uri.parse(startPath)), 'start');
  });

  // A page added below `/more` but missing from inMoreTab was sent to the
  // list by authRedirect (job 85).
  test('every page of the More tab stays put for a member', () {
    Iterable<String> paths(RouteBase route, String base) sync* {
      if (route is GoRoute) {
        final path = route.path.startsWith('/')
            ? route.path
            : '$base/${route.path}';
        yield path;
        for (final child in route.routes) {
          yield* paths(child, path);
        }
      }
    }

    final more = [for (final route in moreTabRoutes()) ...paths(route, '')]
        .where((p) => p.startsWith(morePath));
    expect(more, containsAll([usageDataPath, tipsPath, moreLegalPath]));
    for (final path in more) {
      expect(authRedirect(household, Uri.parse(path)), isNull, reason: path);
    }
  });

  group('JH2 (job 271)', () {
    const atJoin = OnboardingDraft(step: OnboardingStep.join);
    const code = 'ABCD2345';

    test('the join step is a step before the account', () {
      expect(OnboardingStep.join.beforeAccount, isTrue);
      expect(
        authRedirect(const SignedOut(), Uri.parse('/'), draft: atJoin),
        '/start/join',
      );
      expect(
        authRedirect(const NeedsHousehold('u'), Uri.parse('/'), draft: atJoin),
        '/start/join',
      );
      expect(screenNameOf(Uri.parse('/start/join')), 'onboarding_join');
    });

    test('Join on the step: the code kept and the draft gone, signed out '
        'signs in first, signed in joins', () {
      expect(
        authRedirect(
          const SignedOut(),
          Uri.parse('/start/join'),
          pendingInvite: code,
        ),
        '/login?invite=$code',
      );
      expect(
        authRedirect(
          const NeedsHousehold('u'),
          Uri.parse('/start/join'),
          pendingInvite: code,
        ),
        '/join/$code',
      );
    });

    test('a new account from a link: the full-screen consent, then the '
        'join', () {
      expect(
        authRedirect(const SignedOut(), Uri.parse('/join/$code')),
        '/login?invite=$code',
      );
      final consent = authRedirect(
        const NeedsHousehold('u'),
        Uri.parse('/?invite=$code'),
        askConsent: true,
        pendingInvite: code,
      );
      expect(consent, '/analytics-consent?invite=$code');
      expect(
        authRedirect(
          const NeedsHousehold('u'),
          Uri.parse(consent!),
          pendingInvite: code,
        ),
        '/join/$code',
      );
    });

    test('an existing account from a link joins, never the guided start', () {
      for (final from in ['/?invite=$code', '/', '/login?invite=$code']) {
        expect(
          authRedirect(household, Uri.parse(from), pendingInvite: code),
          '/join/$code',
        );
      }
    });
  });

  // Job 297 (DN-Q6): the name step after the account and the analytics
  // consent, before a household is set up or joined, and in one before the
  // list. Once the name is chosen (askName false) the steps go on.
  const nameStep = '/your-name';
  const account = OnboardingDraft(step: OnboardingStep.account);
  final naming = <(Session, String, OnboardingDraft?, bool, String?)>[
    (const NeedsHousehold('u'), '/', null, true, nameStep),
    (const NeedsHousehold('u'), '/welcome', null, true, nameStep),
    (const NeedsHousehold('u'), nameStep, null, true, null),
    (const NeedsHousehold('u'), nameStep, null, false, '/welcome'),
    (
      const NeedsHousehold('u'),
      '/join/ABCD2345',
      null,
      true,
      '$nameStep?invite=ABCD2345',
    ),
    (
      const NeedsHousehold('u'),
      '$nameStep?invite=ABCD2345',
      null,
      false,
      '/join/ABCD2345',
    ),
    (const NeedsHousehold('u'), '/start/account', account, true, nameStep),
    (const NeedsHousehold('u'), nameStep, account, false, '/start/setup'),
    // A link rides along.
    (
      const NeedsHousehold('u'),
      '/more/invites',
      null,
      true,
      '$nameStep?next=%2Fmore%2Finvites',
    ),
    (
      const NeedsHousehold('u'),
      '$nameStep?next=%2Fmore%2Finvites',
      null,
      false,
      '/welcome?next=%2Fmore%2Finvites',
    ),
    // An MCP authorization is not interrupted.
    (const NeedsHousehold('u'), '/login?$next', null, true, '/welcome?$next'),
    (household, '/', null, true, nameStep),
    (household, '/more/account', null, true, nameStep),
    (household, nameStep, null, true, null),
    (household, nameStep, null, false, '/'),
    (household, consent, null, true, null),
    (const SignedOut(), nameStep, null, true, '/start'),
  ];
  for (final (session, from, draft, askName, to) in naming) {
    test('asking the name ($askName): ${session.runtimeType} at $from '
        '${draft == null ? '' : 'with a draft '}goes to ${to ?? 'stays'}', () {
      expect(
        authRedirect(session, Uri.parse(from), draft: draft, askName: askName),
        to,
      );
    });
  }

  test('the analytics consent comes before the name', () {
    for (final session in [const NeedsHousehold('u'), household]) {
      expect(
        authRedirect(session, Uri.parse('/'), askConsent: true, askName: true),
        '/analytics-consent',
      );
      expect(
        RedirectMemory().redirect(
          session,
          Uri.parse('/analytics-consent'),
          askName: true,
        ),
        nameStep,
      );
    }
  });
}
