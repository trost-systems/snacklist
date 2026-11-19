import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// Its own file: the list decides once per run whether the field
/// autofocuses, so a phone test before it would fix the answer.
void main() {
  testWidgets('with a hardware keyboard the field is ready at once, the '
      'sheet still closed', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BlocProvider(
          create: (_) =>
              ListCubit(FakeRepository(), MemoryListCache(), userId: 'peter')
                ..start(),
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('add-item-field')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.byKey(const ValueKey('add-sheet')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
