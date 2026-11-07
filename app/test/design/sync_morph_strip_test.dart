// Job 165: a strip of frames of the sync indicator folding from the card
// into the pill, the top 200 px of a 390 px phone, for the PR. Skipped
// unless SYNC_MORPH_STRIP names the output directory:
//   SYNC_MORPH_STRIP=../docs/screenshots/165 flutter test \
//     test/design/sync_morph_strip_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/sync_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import 'fonts.dart';

final _dir = Platform.environment['SYNC_MORPH_STRIP'];

const _phone = Size(390, 844);
const _crop = Size(390, 200);
const _ratio = 2.0;
const _gap = 8.0;

/// Frames after the fold starts; the last one is the settled pill.
const _frames = [0, 16, 32, 48, 64, 96, 160, 360];

void main() {
  setUpAll(() async {
    if (_dir != null) {
      await loadAppFonts();
    }
  });

  for (final (name, locale, brightness, kind) in [
    ('de-light', const Locale('de'), Brightness.light, SyncTrouble.offline),
    ('en-dark', const Locale('en'), Brightness.dark, SyncTrouble.failing),
  ]) {
    testWidgets('morph strip $name', skip: _dir == null, (tester) async {
      tester.view
        ..devicePixelRatio = _ratio
        ..physicalSize = _phone * _ratio;
      addTearDown(tester.view.reset);
      final repo = FakeRepository();
      [
        'Äpfel',
        'Bananen',
        'Vollmilch',
        'Butter',
        'Brot',
      ].forEach(repo.remoteAdd);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(brightness),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            home: BlocProvider(
              create: (_) =>
                  ListCubit(repo, MemoryListCache(), userId: 'peter')..start(),
              child: const ShoppingList(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.emitStatus!(ConnectionStatus.online);
      await tester.pumpAndSettle();
      final cubit = tester.element(find.byType(ShoppingList)).read<ListCubit>();
      switch (kind) {
        case SyncTrouble.offline:
          repo.online = false;
          repo.emitStatus!(ConnectionStatus.offline);
        case SyncTrouble.failing:
          repo.fetchTrouble = true;
          unawaited(cubit.resync());
      }
      await tester.pump();
      for (var i = 0; i < 40 && cubit.state.trouble != kind; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(cubit.state.trouble, kind);
      await tester.pumpAndSettle();

      final shots = <ui.Image>[];
      Future<void> shoot() async => shots.add(
        (await tester.runAsync(
          () => captureImage(boundary.currentContext! as Element),
        ))!,
      );
      // The card's 3 s run out within this pump; the fold starts with the
      // next frame.
      await tester.pump(SyncIndicator.peek);
      var at = 0;
      for (final ms in _frames) {
        await tester.pump(Duration(milliseconds: ms - at));
        at = ms;
        await shoot();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sync-pill')), findsOneWidget);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final frame = _crop * _ratio;
      final step = frame.width + _gap * _ratio;
      canvas.drawColor(
        brightness == Brightness.light
            ? const Color(0xff9aa0b4)
            : const Color(0xff2a3150),
        BlendMode.src,
      );
      for (final (i, shot) in shots.indexed) {
        // The shot comes at its own pixel ratio.
        final scale = shot.width / _phone.width;
        canvas.drawImageRect(
          shot,
          Offset.zero & _crop * scale,
          Offset(i * step, 0) & frame,
          Paint(),
        );
      }
      final png = await tester.runAsync(() async {
        final strip = await recorder.endRecording().toImage(
          (shots.length * step - _gap * _ratio).round(),
          frame.height.round(),
        );
        return await strip.toByteData(format: ui.ImageByteFormat.png);
      });
      final file = File('$_dir/morph-strip-$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
      // A path a reviewer can open.
      // ignore: avoid_print
      print(file.absolute.path);
    });
  }
}
