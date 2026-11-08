// Job 51: PR screenshots of the Siri section on Mehr > Zugänge. Real theme,
// Roboto and the Material icons from the Flutter SDK. Skipped unless
// SCREENSHOT_DIR is set:
//   SCREENSHOT_DIR=/tmp/shots flutter test --update-goldens \
//     test/settings/siri_screenshots_test.dart
import 'dart:io';

import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/settings/access_repository.dart';
import 'package:family_groceries/settings/access_screen.dart';
import 'package:family_groceries/siri/siri_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../siri/fake_siri_channel.dart';
import 'access_screen_test.dart' show FakeAccessRepository;

final _dir = Platform.environment['SCREENSHOT_DIR'];

Future<void> _loadFonts() async {
  // flutter_tester lives in <sdk>/bin/cache/artifacts/engine/<platform>/.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final fonts = Directory('${artifacts.path}/material_fonts');
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('${fonts.path}/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await family('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

AccessToken _token(String id, String name, AccessKind kind) => AccessToken(
  id: id,
  name: name,
  kind: kind,
  hint: id.substring(0, 4),
  createdAt: DateTime(2026, 10, 31),
);

typedef Scene = ({String name, bool legacy, bool phrases});

const _scenes = <Scene>[
  (name: 'card', legacy: false, phrases: false),
  (name: 'legacy-hint', legacy: true, phrases: false),
  (name: 'phrases', legacy: false, phrases: true),
];

void main() {
  setUpAll(() async {
    if (_dir != null) {
      await _loadFonts();
      WidgetsApp.debugAllowBannerOverride = false;
    }
  });

  for (final scene in _scenes) {
    for (final lang in ['de', 'en']) {
      final name = 'zugaenge-${scene.name}-$lang';
      testWidgets(name, skip: _dir == null, (tester) async {
        tester.view.physicalSize = const Size(390, 844) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final repo = FakeAccessRepository()
          ..tokens.add(_token('here-id', 'Siri', AccessKind.siri));
        if (scene.legacy) {
          repo.tokens.add(_token('pat1', 'Siri', AccessKind.pat));
        }
        final siri = FakeSiriChannel()
          ..entry = const SiriKeychainEntry(
            id: 'here-id',
            userId: 'u1',
            sessionId: 's1',
          );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale(lang),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  title: Text(AppLocalizations.of(context).accessTitle),
                ),
                body: AccessScreen(repositories: (_) => repo, siri: siri),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (scene.phrases) {
          await tester.tap(find.byKey(const ValueKey('siri-phrases')));
          await tester.pumpAndSettle();
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(Uri.file('$_dir/$name.png')),
        );
      });
    }
  }
}
