import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design/fonts.dart';
import 'fake_repository.dart';
import 'memory_cache.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final (locale, name) in [
    (const Locale('de'), 'Ohne Laden'),
    (const Locale('en'), 'No store'),
  ]) {
    testWidgets('$locale: at 150 % on a 375 px phone the header shows '
        '„$name“ in full beside 15 items and the fold key', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(375, 667);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = FakeRepository();
      for (var i = 0; i < 15; i++) {
        repo.remoteAdd('Artikel $i');
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: BlocProvider(
            create: (_) => ListCubit(
              repo,
              MemoryListCache()..prefs = const ListPrefs(hintDismissed: true),
              userId: 'peter',
            )..start(),
            child: const ShoppingList(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badge = tester.renderObject<RenderParagraph>(find.text(name));
      expect(badge.didExceedMaxLines, isFalse, reason: '„$name“ is cut');
    });
  }
}
