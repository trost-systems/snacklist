// Goldens of the list's „… ist erledigt“ card (job 399), hex and RD1, German
// and English, light and dark, at 100 % and 310 % text on the 358 px compact
// width. After a deliberate look change:
//   flutter test --update-goldens test/design/store_done_card_golden_test.dart
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_view/store_done_card.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fonts.dart';

const _app = RetailerApp(
  name: 'Lidl Plus',
  android: 'com.lidl.eci.lidlplus',
  ios: '1238611143',
);

void main() {
  setUpAll(loadAppFonts);

  tearDown(() => appLook = Look.hex);

  for (final look in Look.values) {
    for (final lang in ['de', 'en']) {
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 3.1]) {
          final percent = (scale * 100).round();
          final name = '${look.name}_${lang}_${brightness.name}_$percent';
          testWidgets('store done card, $name', (tester) async {
            appLook = look;
            tester.view
              ..devicePixelRatio = 1
              ..physicalSize = const Size(358, 400);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: appTheme(brightness),
                locale: Locale(lang),
                localizationsDelegates: appLocalizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HlSpace.s3,
                      vertical: HlSpace.s2,
                    ),
                    child: Column(
                      children: [
                        StoreDoneView(
                          store: const Store(
                            id: 'lidl',
                            name: 'Lidl',
                            sortOrder: 10,
                          ),
                          app: _app,
                          onOpen: () {},
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
              matchesGoldenFile('goldens/store_done_card_$name.png'),
            );
          });
        }
      }
    }
  }
}
