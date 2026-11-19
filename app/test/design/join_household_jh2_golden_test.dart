// Goldens of JH2 (job 271): the household-name step with „Bestehendem
// Haushalt beitreten“, the code step with a household and with a dead code,
// the invite sheet over the sign-in, and the approval wait. German light
// and English dark at 130 % text on a phone; every screen also at 160 % on
// the 358 px compact width, where nothing may overflow. After a deliberate
// look change:
//   flutter test --update-goldens test/design/join_household_jh2_golden_test.dart
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/join_request_waiting.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/onboarding/steps.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../household/harness.dart';
import '../session/fake_auth.dart';
import 'fonts.dart';

const _phone = Size(390, 844);
const _compact = Size(358, 780);

/// One look: language, brightness, text scale and size.
typedef _Look = ({String lang, Brightness brightness, double scale, Size size});

const _looks = <_Look>[
  (lang: 'de', brightness: Brightness.light, scale: 1.3, size: _phone),
  (lang: 'en', brightness: Brightness.dark, scale: 1.3, size: _phone),
];

const _compactLooks = <_Look>[
  (lang: 'de', brightness: Brightness.light, scale: 1.6, size: _compact),
  (lang: 'en', brightness: Brightness.light, scale: 1.6, size: _compact),
];

const _waiting = NeedsHousehold(
  'peter',
  requests: [
    JoinRequest(id: 'r1', householdId: 'club', householdName: 'Sommerfest'),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  _Look look, {
  required Widget home,
  Session session = const SignedOut(),
  OnboardingDraft? draft,
  FakeInvites? invites,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = look.size;
  addTearDown(tester.view.reset);
  final testSession = TestSession(session);
  addTearDown(testSession.close);
  final onboarding = OnboardingCubit(MemoryOnboardingStore(), initial: draft);
  addTearDown(onboarding.close);
  final flags = Flags(forced: {joinHouseholdJh2Flag});
  addTearDown(flags.close);
  final auth = FakeAuth();
  addTearDown(auth.close);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<InviteRepository>.value(
          value: invites ?? FakeInvites(),
        ),
        RepositoryProvider.value(value: PendingInvite(MemoryPendingStore())),
        RepositoryProvider.value(
          value: SocialSignIn(
            auth,
            flows: const {
              SocialProvider.google: SignInFlow.native,
              SocialProvider.apple: SignInFlow.native,
            },
            native: FakeNativeSignIn(),
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>.value(value: testSession),
          BlocProvider.value(value: onboarding),
          BlocProvider.value(value: flags),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(look.brightness),
          locale: Locale(look.lang),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(look.scale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    ),
  );
  final context = tester.element(find.byWidget(home));
  await tester.runAsync(
    () => Future.wait([
      precacheImage(
        AssetImage('assets/brand/mark-${look.brightness.name}.png'),
        context,
      ),
      precacheImage(const AssetImage('assets/google_g.png'), context),
    ]),
  );
  await tester.pumpAndSettle();
}

Future<void> _code(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const ValueKey('join-code-field')), code);
  await tester.pumpAndSettle();
}

/// The screens, each with how it is reached.
final _screens = <String, Future<void> Function(WidgetTester, _Look)>{
  'name-step': (tester, look) => _pump(
    tester,
    look,
    home: onboardingStepScreen(OnboardingStep.name),
    draft: const OnboardingDraft(step: OnboardingStep.name),
  ),
  'code-preview': (tester, look) async {
    final invites = FakeInvites()
      ..publicAnswers['ABCD2345'] = const PublicInviteOpen(
        household: 'Familie Trost',
        inviter: 'Peter',
        members: 3,
        openItems: 12,
        premium: true,
      );
    await _pump(
      tester,
      look,
      home: onboardingStepScreen(OnboardingStep.join),
      draft: const OnboardingDraft(step: OnboardingStep.join),
      invites: invites,
    );
    await _code(tester, 'ABCD2345');
  },
  'code-invalid': (tester, look) async {
    await _pump(
      tester,
      look,
      home: onboardingStepScreen(OnboardingStep.join),
      draft: const OnboardingDraft(step: OnboardingStep.join),
    );
    await _code(tester, 'WXYZ6789');
  },
  'invite-sheet': (tester, look) =>
      _pump(tester, look, home: const LoginScreen(invite: 'ABCD2345')),
  'approval-wait': (tester, look) =>
      _pump(tester, look, home: const PendingJoinScreen(), session: _waiting),
};

void main() {
  setUpAll(loadAppFonts);

  for (final MapEntry(key: name, value: reach) in _screens.entries) {
    for (final look in _looks) {
      final id = '${look.lang}-${look.brightness.name}';
      testWidgets('$name, $id, 130 %', (tester) async {
        await reach(tester, look);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/jh2-$name-$id.png'),
        );
      });
    }
    for (final look in _compactLooks) {
      testWidgets('$name fits 358 px at 160 %, ${look.lang}', (tester) async {
        await reach(tester, look);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
