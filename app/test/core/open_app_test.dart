// The web app's „Öffnen“ card in a phone's browser (job 271, JH2 decision
// 4), and its goldens. After a deliberate look change:
//   flutter test --update-goldens test/core/open_app_test.dart
import 'dart:io';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/deep_links.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/open_app.dart';
import 'package:family_groceries/core/store_listings.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';

const _iphone =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 '
    'Safari/604.1';
const _iphoneChrome =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.6778.73 '
    'Mobile/15E148 Safari/604.1';
const _ipod =
    'Mozilla/5.0 (iPod touch; CPU iPhone OS 15_8 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 '
    'Safari/604.1';
const _ipad =
    'Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';
const _ipadDesktopMode =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.1 Safari/605.1.15';
const _androidPhone =
    'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
const _androidFirefox =
    'Mozilla/5.0 (Android 15; Mobile; rv:133.0) Gecko/133.0 Firefox/133.0';
const _androidTablet =
    'Mozilla/5.0 (Linux; Android 15; SM-X910) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const _androidTabletFirefox =
    'Mozilla/5.0 (Android 15; Tablet; rv:133.0) Gecko/133.0 Firefox/133.0';
const _desktop =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class _FakeOpener(@override final PhoneOs? phone) implements AppOpener {
  final opened = <AppOpening>[];

  @override
  void open(AppOpening opening) => opened.add(opening);
}

Future<void> _pump(
  WidgetTester tester, {
  required AppOpener opener,
  bool jh2 = true,
  ValueNotifier<bool>? closed,
  double width = 390,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('de'),
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, 700);
  addTearDown(tester.view.reset);
  final shut = closed ?? ValueNotifier(false);
  if (closed == null) {
    addTearDown(shut.dispose);
  }
  await tester.pumpWidget(
    BlocProvider(
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
            children: [OpenAppSlot(opener: opener, closed: shut)],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final _card = find.byKey(const ValueKey('open-app-card'));

void main() {
  group('phoneOsOf', () {
    for (final (name, agent, os) in const [
      ('iPhone Safari', _iphone, PhoneOs.ios),
      ('iPhone Chrome', _iphoneChrome, PhoneOs.ios),
      ('iPod touch', _ipod, PhoneOs.ios),
      ('iPad', _ipad, null),
      ('iPad asking for the desktop site', _ipadDesktopMode, null),
      ('Android phone Chrome', _androidPhone, PhoneOs.android),
      ('Android phone Firefox', _androidFirefox, PhoneOs.android),
      ('Android tablet Chrome', _androidTablet, null),
      ('Android tablet Firefox', _androidTabletFirefox, null),
      ('desktop', _desktop, null),
    ]) {
      test('$name: $os', () => expect(phoneOsOf(agent), os));
    }
  });

  group('appOpening', () {
    final page = Uri.parse('https://app.snacklist.app/?x=1');
    const unlisted = (appStore: false, googlePlay: false);
    const listed = (appStore: true, googlePlay: true);

    test(
      'iOS opens the custom scheme on the list; no store while unlisted',
      () {
        expect(appOpening(PhoneOs.ios, page: page, listings: unlisted), (
          app: 'com.snacklist.app://open/list',
          store: null,
        ));
      },
    );

    test('iOS goes on to the App Store once listed', () {
      expect(appOpening(PhoneOs.ios, page: page, listings: listed), (
        app: 'com.snacklist.app://open/list',
        store: 'https://apps.apple.com/app/id6832756448',
      ));
    });

    test('Android unlisted falls back to the page, never to Play', () {
      final opening = appOpening(
        PhoneOs.android,
        page: page,
        listings: unlisted,
      );
      expect(
        opening.app,
        'intent://app.snacklist.app/list#Intent;scheme=https;'
        'package=com.snacklist.app;'
        'S.browser_fallback_url=https%3A%2F%2Fapp.snacklist.app%2F%3Fx%3D1;'
        'end',
      );
      expect(opening.app, isNot(contains('play.google.com')));
      expect(opening.store, isNull);
    });

    test('Android listed falls back to the Play listing', () {
      final opening = appOpening(PhoneOs.android, page: page, listings: listed);
      expect(
        opening.app,
        'intent://app.snacklist.app/list#Intent;scheme=https;'
        'package=com.snacklist.app;'
        'S.browser_fallback_url=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps'
        '%2Fdetails%3Fid%3Dcom.snacklist.app;end',
      );
      expect(opening.store, isNull);
    });

    test('the iOS scheme is one Info.plist registers', () {
      final scheme = Uri.parse(
        appOpening(PhoneOs.ios, page: page, listings: unlisted).app,
      ).scheme;
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final types = RegExp(
        r'<key>CFBundleURLSchemes</key>\s*<array>\s*<string>([^<]+)</string>',
      ).allMatches(plist).map((m) => m[1]);
      expect(types, contains(scheme));
    });

    test('the Android intent opens an App Link the manifest verifies', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final filter = RegExp(
        r'<intent-filter android:autoVerify="true">([\s\S]*?)</intent-filter>',
      ).firstMatch(manifest)![1]!;
      expect(filter, contains('android:host="app.snacklist.app"'));
      expect(isAppLink(Uri.parse('https://app.snacklist.app/list')), isTrue);
    });

    test('the custom-scheme link lands on the list, signed in or not', () {
      final link = Uri.parse(
        appOpening(PhoneOs.ios, page: page, listings: unlisted).app,
      );
      const home = Household(id: 'h', name: 'H');
      expect(
        authRedirect(const InHousehold('u', home, [home]), link),
        listPath,
      );
      expect(authRedirect(const SignedOut(), link), '/login?next=%2Flist');
    });
  });

  group('OpenAppSlot', () {
    testWidgets('shows in a phone browser with JH2', (tester) async {
      await _pump(tester, opener: _FakeOpener(PhoneOs.ios));
      expect(_card, findsOneWidget);
      expect(
        find.text('Snacklist funktioniert in der App besser.'),
        findsOneWidget,
      );
      expect(find.text('Öffnen'), findsOneWidget);
    });

    testWidgets('hides without JH2', (tester) async {
      await _pump(tester, opener: _FakeOpener(PhoneOs.ios), jh2: false);
      expect(_card, findsNothing);
    });

    testWidgets('hides in a desktop or tablet browser', (tester) async {
      await _pump(tester, opener: _FakeOpener(null));
      expect(_card, findsNothing);
    });

    testWidgets('hides in the apps', (tester) async {
      await _pump(tester, opener: const PlatformAppOpener());
      expect(_card, findsNothing);
    });

    testWidgets('the X hides it for the page load', (tester) async {
      final closed = ValueNotifier(false);
      addTearDown(closed.dispose);
      final opener = _FakeOpener(PhoneOs.android);
      await _pump(tester, opener: opener, closed: closed);
      await tester.tap(find.byKey(const ValueKey('open-app-close')));
      await tester.pump();
      expect(_card, findsNothing);
      // The list built again (another household, a tab back) keeps it shut.
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, opener: opener, closed: closed);
      expect(_card, findsNothing);
      expect(opener.opened, isEmpty);
    });

    for (final os in PhoneOs.values) {
      testWidgets('Öffnen hands the ${os.name} opening to the opener', (
        tester,
      ) async {
        final opener = _FakeOpener(os);
        await _pump(tester, opener: opener);
        await tester.tap(find.byKey(const ValueKey('open-app-open')));
        expect(opener.opened, [
          appOpening(os, page: Uri.base, listings: storeListings),
        ]);
        expect(_card, findsOneWidget);
      });
    }

    for (final locale in const [Locale('de'), Locale('en')]) {
      testWidgets('358 px at 160 % text, ${locale.languageCode}: it fits', (
        tester,
      ) async {
        await _pump(
          tester,
          opener: _FakeOpener(PhoneOs.ios),
          width: 358,
          textScale: 1.6,
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        final card = tester.getRect(_card);
        expect(card.right, lessThanOrEqualTo(358));
        for (final key in ['open-app-open', 'open-app-close']) {
          final button = tester.getRect(find.byKey(ValueKey(key)));
          expect(button.right, lessThanOrEqualTo(card.right), reason: key);
          expect(button.height, greaterThanOrEqualTo(48), reason: key);
        }
      });
    }
  });

  group('goldens', () {
    setUpAll(loadAppFonts);

    for (final (locale, brightness) in const [
      (Locale('de'), Brightness.light),
      (Locale('en'), Brightness.dark),
    ]) {
      final name = 'open-app-card-${locale.languageCode}-${brightness.name}';
      testWidgets(name, (tester) async {
        await _pump(
          tester,
          opener: _FakeOpener(PhoneOs.ios),
          width: 358,
          textScale: 1.3,
          brightness: brightness,
          locale: locale,
        );
        await expectLater(_card, matchesGoldenFile('goldens/$name.png'));
      });
    }
  });
}
