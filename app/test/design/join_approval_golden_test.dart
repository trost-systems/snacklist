// Goldens of join approval (job 169b W3 M), light and dark at 390 px: the
// household page's section for an owner with two requests waiting, and the
// joiner's wait without a household. After a deliberate look change:
//   flutter test --update-goldens test/design/join_approval_golden_test.dart
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/join_approval_section.dart';
import 'package:family_groceries/household/join_request_waiting.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../household/harness.dart';
import 'fonts.dart';

const _club = Household(
  id: 'club',
  name: 'Sommerfest',
  role: HouseholdRole.owner,
  joinApproval: true,
);

Future<void> _pump(
  WidgetTester tester,
  Brightness brightness, {
  required Session session,
  required Widget child,
  required Size size,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final testSession = TestSession(session);
  addTearDown(testSession.close);
  final invites = FakeInvites()
    ..requestLists['club'] = const [
      PendingJoin(id: 'r1', userId: 'jonas', displayName: 'Jonas'),
      PendingJoin(id: 'r2', userId: 'mira', displayName: 'Mira Albers'),
    ];
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [RepositoryProvider<InviteRepository>.value(value: invites)],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>.value(value: testSession),
          BlocProvider.value(
            value: Analytics.off(DeviceCache(SharedPreferencesAsync())),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  for (final brightness in Brightness.values) {
    final mode = brightness.name;

    testWidgets('join approval section, $mode', (tester) async {
      await _pump(
        tester,
        brightness,
        session: const InHousehold('peter', _club, [_club]),
        size: const Size(390, 330),
        child: Scaffold(
          body: ListView(
            children: const [JoinApprovalSection(household: _club)],
          ),
        ),
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/join-approval-$mode.png'),
      );
    });

    testWidgets('join request waiting, $mode', (tester) async {
      await _pump(
        tester,
        brightness,
        session: const NeedsHousehold(
          'peter',
          requests: [
            JoinRequest(
              id: 'r1',
              householdId: 'club',
              householdName: 'Sommerfest',
            ),
          ],
        ),
        size: const Size(390, 640),
        child: const PendingJoinScreen(),
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/join-waiting-$mode.png'),
      );
    });
  }
}
