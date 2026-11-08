import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/tips/hint_host.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/tips/tips_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child, {HintHost? host}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('de'),
    home: RepositoryProvider.value(
      value: host ?? const HintHost(),
      child: Scaffold(body: child),
    ),
  );

  group('More → Tipps', () {
    testWidgets('lists every hint of this platform to read again', (
      tester,
    ) async {
      await tester.pumpWidget(app(const TipsPage()));
      final listed = {
        for (final hint in hints)
          if (find
              .byKey(ValueKey('tips-${hint.id.wire}'), skipOffstage: false)
              .evaluate()
              .isNotEmpty)
            hint.id,
      };
      expect(listed, {
        HintId.invitePartner,
        HintId.editLongPress,
        HintId.quickAddAmounts,
        HintId.storeOrder,
        HintId.addStore,
        HintId.dictation,
        HintId.aiAssistant,
        HintId.homeWidget,
      }, reason: 'Android: no Siri, no household button before job 169b');
      expect(find.byTooltip('Tipp ausblenden'), findsNothing);
      expect(find.text('Gemeinsam einkaufen'), findsOneWidget);
    });

    testWidgets('lists the household hints once the app can add one', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        app(const TipsPage(), host: HintHost(addHousehold: (_) => opened++)),
      );
      final button = find.byKey(
        const ValueKey('tip-action-own-household'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(button, 300);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      expect(opened, 1);
    });
  });
}
