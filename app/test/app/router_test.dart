import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  const household = InHousehold('u', Household(id: 'h', name: 'H'), [
    Household(id: 'h', name: 'H'),
  ]);
  const consent = '/oauth/consent?authorization_id=abc';
  const next = 'next=%2Foauth%2Fconsent%3Fauthorization_id%3Dabc';
  const cases = <(Session, String, String?)>[
    (SessionLoading(), '/', null),
    (SignedOut(), '/', '/login'),
    (SignedOut(), '/login', null),
    (SignedOut(), '/join/ABCD2345', '/login?invite=ABCD2345'),
    // Job 22: an invite skips Step 1 and opens the join screen.
    (NeedsHousehold('u'), '/login?invite=ABCD2345', '/join/ABCD2345'),
    (NeedsHousehold('u'), '/', '/welcome'),
    (NeedsHousehold('u'), '/join/ABCD2345', null),
    (NeedsHousehold('u'), '/welcome?invite=ABCD2345', '/join/ABCD2345'),
    (NeedsHousehold('u'), '/welcome', null),
    (NeedsHousehold('u'), '/welcome/create', null),
    (NeedsHousehold('u'), '/join', null),
    (NeedsHousehold('u'), '/welcome/invite', '/welcome'),
    (NeedsHousehold('u'), '/more/invites', '/welcome?next=%2Fmore%2Finvites'),
    (household, '/welcome/create', '/welcome/invite'),
    (household, '/welcome/invite', null),
    (household, '/join', null),
    (household, '/more/invites', null),
    // Job 169b: one more household and the household page, in one only.
    (household, '/households/new', null),
    (household, '/more/household', null),
    (NeedsHousehold('u'), '/households/new', '/welcome'),
    (SignedOut(), '/households/new', '/login'),
    (SignedOut(), '/welcome/invite', '/login'),
    (SignedOut(), '/join', '/login'),
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
    (NeedsHousehold('u'), '/edit/lidl', '/welcome'),
    (SignedOut(), '/edit', '/login'),
    (household, '/more/access', null),
    (household, '/more/account', null),
    (household, '/more/account?invite=ABCD2345', '/join/ABCD2345'),
    (SignedOut(), '/more/account', '/login?next=%2Fmore%2Faccount'),
    (household, '/more/settings', null),
    // Hummlist Lifetime is for a household: never signed out or before one
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
    (SignedOut(), '/settings', '/login'),
    (SignedOut(), consent, '/login?$next'),
    (SignedOut(), '/login?$next', null),
    (NeedsHousehold('u'), '/login?$next', '/welcome?$next'),
    (NeedsHousehold('u'), consent, '/welcome?$next'),
    (NeedsHousehold('u'), '/welcome?$next', null),
    (NeedsHousehold('u'), '/welcome/create?$next', null),
    (NeedsHousehold('u'), '/join?$next', null),
    (NeedsHousehold('u'), '/join/ABCD2345?$next', null),
    (household, '/welcome/create?$next', consent),
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
  // returns through com.hummlist.app://login-callback, and a cold start
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
  // (the path of https://app.hummlist.com/join/<code>) and the auth
  // callback, whose path is empty.
  test('a universal link names its invite', () {
    expect(
      inviteIn(Uri.parse('https://app.hummlist.com/join/ABCD2345')),
      'ABCD2345',
    );
    expect(
      authRedirect(
        const SignedOut(),
        Uri.parse('https://app.hummlist.com/join/ABCD2345'),
      ),
      '/login?invite=ABCD2345',
    );
  });

  test(
    'the custom-scheme callback has no invite; the pending one leads on',
    () {
      final callback = Uri.parse('com.hummlist.app://login-callback?code=abc');
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
    (SignedOut(), '/', '/login'),
    (SignedOut(), ask, '/login'),
    (SignedOut(), '/login', null),
    (SignedOut(), '/join/ABCD2345', '/login?invite=ABCD2345'),
    (NeedsHousehold('u'), '/login', ask),
    (NeedsHousehold('u'), '/', ask),
    (NeedsHousehold('u'), '/welcome', ask),
    (NeedsHousehold('u'), '/welcome/create', ask),
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
    (SignedOut(), ask, '/login'),
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
    (SignedOut(), '/nope', '/login'),
    // A More page that isn't one: no `next` to nowhere.
    (SignedOut(), '/more/nothing-here', '/login'),
    (household, '/login?next=%2Fmore%2Fnothing-here', '/'),
    (household, 'https://app.hummlist.com/add', '/'),
    // Signed out, sign-in continues there.
    (SignedOut(), '/more/invites', '/login?next=%2Fmore%2Finvites'),
    (SignedOut(), '/more/settings', '/login?next=%2Fmore%2Fsettings'),
    (SignedOut(), '/add', '/login?next=%2Fadd'),
    (SignedOut(), '/stores/s1', '/login?next=%2Fstores%2Fs1'),
    (SignedOut(), '/list', '/login?next=%2Flist'),
    (SignedOut(), 'https://app.hummlist.com/add', '/login?next=%2Fadd'),
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
    (NeedsHousehold('u'), '/welcome/create?next=%2Fadd', null),
    (household, '/welcome/create?next=%2Fadd', '/add'),
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
  ];
  for (final (session, from, to) in links) {
    test('link: ${session.runtimeType} at $from goes to ${to ?? 'stays'}', () {
      expect(authRedirect(session, Uri.parse(from)), to);
    });
  }

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

  test('a sign-out carries no link to the next sign-in', () {
    expect(
      authRedirect(
        const SignedOut(),
        Uri.parse('/more/account'),
        justSignedOut: true,
      ),
      '/login',
    );
  });

  // The redirect's memory (buildRouter): a sign-in that leaves the app
  // comes back at `/` and the link leads on from memory; a sign-out
  // forgets it.
  group('RedirectMemory', () {
    test('a link survives the sign-in callback at /, once', () {
      final memory = RedirectMemory();
      final callback = Uri.parse('com.hummlist.app://login-callback?code=a');
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
        '/login',
      );
      expect(memory.redirect(const SignedOut(), Uri.parse('/')), '/login');
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

    test('a sign-out before the link was used drops it', () {
      final memory = RedirectMemory()
        ..redirect(const SignedOut(), Uri.parse('/add'))
        ..redirect(const NeedsHousehold('u'), Uri.parse('/'));
      expect(memory.redirect(const SignedOut(), Uri.parse('/')), '/login');
      expect(memory.redirect(const SignedOut(), Uri.parse('/')), '/login');
    });
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
    expect(more, containsAll([usageDataPath, moreLegalPath]));
    for (final path in more) {
      expect(authRedirect(household, Uri.parse(path)), isNull, reason: path);
    }
  });
}
