import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/chain_question.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'retailer_fixtures.dart';

/// Job 313: „Ist das Lidl?“, asked after saving a store (SS2) and on the
/// list for one the household has (SS5).
void main() {
  late List<Retailer?> answers;

  Future<void> pump(
    WidgetTester tester,
    List<Retailer> chains, {
    bool existing = false,
    String store = 'Aldi',
    Locale locale = const Locale('de'),
  }) async {
    answers = [];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: ChainQuestion(
            storeName: store,
            chains: chains,
            existing: existing,
            onAnswer: answers.add,
          ),
        ),
      ),
    );
  }

  testWidgets('one chain: Ja is it, Nein, so lassen is none', (tester) async {
    await pump(tester, [lidl], store: 'Lidl');
    expect(find.text('Ist das Lidl (Deutschland)?'), findsOne);
    expect(
      find.text('Dann kannst du Lidl Plus direkt aus der Liste öffnen.'),
      findsOne,
    );
    await tester.tap(find.text('Ja'));
    await tester.tap(find.text('Nein, so lassen'));
    expect(answers, [lidl, null]);
  });

  testWidgets('an existing store is asked by its name, with a plain Nein', (
    tester,
  ) async {
    await pump(tester, [lidl], store: 'Lidl', existing: true);
    expect(
      find.text('Ist dein „Lidl“ die Kette Lidl (Deutschland)?'),
      findsOne,
    );
    await tester.tap(find.text('Nein'));
    expect(answers, [null]);
  });

  testWidgets('a chain without an app: no line about the list', (tester) async {
    await pump(tester, [const Retailer(chain: 'x', country: 'DE', name: 'X')]);
    expect(find.textContaining('direkt aus der Liste'), findsNothing);
  });

  testWidgets('several chains: one button each and Keins davon', (
    tester,
  ) async {
    await pump(tester, [aldiNord, aldiSued]);
    expect(find.text('Welches Aldi?'), findsOne);
    await tester.tap(find.text('ALDI SÜD'));
    await tester.tap(find.text('Keins davon'));
    expect(answers, [aldiSued, null]);
  });

  testWidgets('chains of several countries name their country', (tester) async {
    await pump(
      tester,
      [aldiSued, hofer],
      existing: true,
      locale: const Locale('en'),
    );
    expect(find.text('Which chain is your “Aldi”?'), findsOne);
    expect(find.text('HOFER (Austria)'), findsOne);
    expect(find.text('ALDI SÜD (Germany)'), findsOne);
  });

  testWidgets('Globus asks which one: the supermarket or the Baumarkt', (
    tester,
  ) async {
    final globus = [for (final m in matchRegistry('Globus', 'DE')) m.retailer];
    await pump(tester, globus, store: 'Globus');
    expect(find.text('Welches Globus?'), findsOne);
    expect(find.widgetWithText(OutlinedButton, 'Globus'), findsOne);
    expect(find.widgetWithText(OutlinedButton, 'Globus Baumarkt'), findsOne);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Globus Baumarkt'));
    expect(answers.single?.chain, 'globus-baumarkt');
  });
}
