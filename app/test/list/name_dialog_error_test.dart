import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a refused name is read with the field', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showNameDialog(
              context,
              title: 'Laden',
              confirm: 'Speichern',
              label: 'Name',
              save: (_) async => true,
              validate: (_) => 'Gibt es schon',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('name-dialog-field'));
    await tester.enterText(field, 'Aldi');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final input = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    expect(tester.getSemantics(input).label, 'Name');
    expect(tester.getSemantics(input).hint, 'Gibt es schon');
    expect(
      tester.getSemantics(find.text('Gibt es schon')).label,
      'Gibt es schon',
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await tester.enterText(field, 'Aldi Süd');
    await tester.pump();
    expect(tester.getSemantics(input).hint, isEmpty);
    semantics.dispose();
  });
}
