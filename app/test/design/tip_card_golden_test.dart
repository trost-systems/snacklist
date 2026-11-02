// Goldens of the List tab's tip cards (job 80), light and dark, at the 358 px
// compact width, the second at text scale 1.3. After a deliberate look change:
//   flutter test --update-goldens test/design/tip_card_golden_test.dart
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/tips/tip_card.dart';
import 'package:family_groceries/tips/tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final brightness in Brightness.values) {
    testWidgets('tip cards, ${brightness.name}', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(358, 330);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(HlSpace.s3),
              child: Column(
                spacing: HlSpace.s4,
                children: [
                  TipCard(tip: tips[0], onDismiss: () {}),
                  MediaQuery.withClampedTextScaling(
                    minScaleFactor: 1.3,
                    maxScaleFactor: 1.3,
                    child: TipCard(tip: tips[1], onDismiss: () {}),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/tip_cards_${brightness.name}.png'),
      );
    });
  }
}
