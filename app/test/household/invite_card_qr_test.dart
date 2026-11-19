// A one-person invite's QR code with JH2 (job 271, JH-Q7), and its
// goldens. After a deliberate look change:
//   flutter test --update-goldens test/household/invite_card_qr_test.dart
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invite_sheet.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import 'harness.dart' show FakeSharer;

final _invite = Invite(
  id: 'i1',
  code: 'ABCD2345',
  // Local, so the card prints 9:30 in any time zone (CI runs in UTC).
  expiresAt: DateTime(2026, 11, 22, 9, 30).toUtc(),
);

const _home = Household(id: 'home', name: 'Zuhause', isDefault: true);

/// The card as the onboarding invite step lays it out, the tightest of its
/// pages (24 px a side), [width] wide.
Future<void> _pump(
  WidgetTester tester, {
  required bool jh2,
  double width = 390,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('de'),
  String? joinedBy,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepositoryProvider<InviteSharer>.value(
      value: FakeSharer(),
      child: BlocProvider(
        create: (_) => Flags(forced: {if (jh2) joinHouseholdJh2Flag}),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                InviteCard(
                  invite: _invite,
                  household: _home,
                  origin: InviteContext.onboarding,
                  joinedBy: joinedBy,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('with JH2 the card shows the invite link as a QR code', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, jh2: true);
    final qr = tester.widget<InviteQr>(find.byType(InviteQr));
    // A test build has no APP_URL: the code stands in, as on the group card.
    expect(qr.data, inviteLink(_invite.code) ?? _invite.code);
    expect(find.bySemanticsLabel('QR-Code dieser Einladung'), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-copy-code')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('without JH2 the card has no QR code', (tester) async {
    await _pump(tester, jh2: false);
    expect(find.byType(InviteQr), findsNothing);
    expect(find.byKey(const ValueKey('invite-copy-code')), findsOneWidget);
  });

  testWidgets('once someone joined the QR code goes', (tester) async {
    await _pump(tester, jh2: true, joinedBy: 'Lea');
    expect(find.byType(InviteQr), findsNothing);
  });

  testWidgets('the English label', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, jh2: true, locale: const Locale('en'));
    expect(find.bySemanticsLabel('QR code for this invite'), findsOneWidget);
    semantics.dispose();
  });

  for (final locale in const [Locale('de'), Locale('en')]) {
    testWidgets('358 px at 160 % text, ${locale.languageCode}: it fits', (
      tester,
    ) async {
      await _pump(
        tester,
        jh2: true,
        width: 358,
        textScale: 1.6,
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(InviteCard));
      final qr = tester.getRect(find.byType(InviteQr));
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(358));
      expect(qr.left, greaterThan(card.left));
      expect(qr.right, lessThan(card.right));
    });
  }

  group('goldens', () {
    setUpAll(loadAppFonts);

    for (final (locale, brightness) in const [
      (Locale('de'), Brightness.light),
      (Locale('en'), Brightness.dark),
    ]) {
      final name = 'invite-card-qr-${locale.languageCode}-${brightness.name}';
      testWidgets(name, (tester) async {
        await _pump(
          tester,
          jh2: true,
          width: 358,
          brightness: brightness,
          locale: locale,
        );
        await expectLater(
          find.byType(InviteCard),
          matchesGoldenFile('goldens/$name.png'),
        );
      });
    }
  });
}
