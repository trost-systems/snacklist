import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/tips/hint_host.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/tips/tips_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget app(Widget child, {HintHost? host, Set<String> flags = const {}}) =>
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BlocProvider(
          create: (_) => Flags(forced: flags),
          child: RepositoryProvider.value(
            value: host ?? const HintHost(),
            child: Scaffold(body: child),
          ),
        ),
      );

  group('More → Tipps', () {
    testWidgets('flag hide-categories: no tip about the category order', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(const TipsPage(), flags: {hideCategoriesFlag}),
      );
      expect(
        find.byKey(const ValueKey('tips-store-order'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('tips-add-store'), skipOffstage: false),
        findsOneWidget,
      );
    });

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
