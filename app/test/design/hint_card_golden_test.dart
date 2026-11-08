// Goldens of the List tab's hints (job 168b), light and dark, at the 358 px
// compact width: a flat card with its button, the callout under Anpassen,
// the „Erste Schritte“ card of a club. After a deliberate look change:
//   flutter test --update-goldens test/design/hint_card_golden_test.dart
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/tips/checklist.dart';
import 'package:family_groceries/tips/hint_views.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/tips/usage_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  Hint hint(HintId id) => hints.firstWhere((h) => h.id == id);

  for (final brightness in Brightness.values) {
    testWidgets('hint cards, ${brightness.name}', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(358, 640);
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
                  HintCard(
                    hint: hint(HintId.invitePartner),
                    onAct: () {},
                    onDismiss: () {},
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: HintCallout(
                      hint: hint(HintId.storeOrder),
                      pointing: AxisDirection.up,
                      onAct: () {},
                      onDismiss: () {},
                    ),
                  ),
                  ChecklistCard(
                    checklist: Checklist.of(
                      UsageLog(since: DateTime(2026)),
                      kind: HouseholdKind.club,
                      owner: true,
                    ),
                    onDismiss: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/hint_cards_${brightness.name}.png'),
      );
    });
  }
}
