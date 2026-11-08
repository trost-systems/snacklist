import 'dart:async';

import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/tips/checklist.dart';
import 'package:family_groceries/tips/hint_host.dart';
import 'package:family_groceries/tips/hint_views.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/tips/hints_cubit.dart';
import 'package:family_groceries/tips/usage_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import 'hints_cubit_test.dart' show MemoryHintStore;

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

  final editHint = hints.firstWhere((h) => h.id == HintId.editLongPress);

  testWidgets('the hint card is flat: the contour, no shadow', (tester) async {
    await tester.pumpWidget(
      app(HintCard(hint: editHint, onAct: () {}, onDismiss: () {})),
    );
    final sticker = tester.widget<HlSticker>(find.byType(HlSticker));
    expect(sticker.depth, StickerDepth.flat);
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(HlSticker),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.boxShadow, isEmpty);
    expect((decoration.border! as Border).top.width, 2);
    expect(find.text('Artikel bearbeiten'), findsOneWidget);
    expect(
      find.text(
        'Halte einen Artikel gedrückt und ändere Menge, Marke, Laden und mehr.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a hint with an action shows its button', (tester) async {
    var acted = 0;
    final invite = hints.firstWhere((h) => h.id == HintId.invitePartner);
    await tester.pumpWidget(
      app(HintCard(hint: invite, onAct: () => acted++, onDismiss: () {})),
    );
    expect(find.text('Gemeinsam einkaufen'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Einladen'));
    expect(acted, 1);
  });

  testWidgets('X shows where the tips are for 3 s and hides the hint for '
      'good', (tester) async {
    final repo = FakeRepository();
    for (var i = 0; i < 6; i++) {
      repo.remoteAdd('Artikel $i');
    }
    final store = MemoryHintStore()
      ..logs['peter'] = UsageLog(since: DateTime(2026, 11, 8)).toJson();
    var now = DateTime(2026, 11, 8, 9);

    /// The list and its hints as a fresh session; the tree closes both.
    Future<void> session() async {
      await tester.pumpWidget(
        app(
          MultiBlocProvider(
            key: UniqueKey(),
            providers: [
              BlocProvider(
                create: (_) => ListCubit(
                  repo,
                  MemoryListCache()
                    ..prefs = const ListPrefs(hintDismissed: true),
                  userId: 'peter',
                  clock: () => now,
                )..start(),
              ),
              BlocProvider(
                create: (context) {
                  final hints = HintsCubit(
                    store,
                    context.read<ListCubit>(),
                    platform: HintPlatform.android,
                    clock: () => now,
                  );
                  unawaited(hints.load());
                  return hints;
                },
              ),
            ],
            child: const ListHints(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final card = find.byKey(const ValueKey('tip-edit-long-press'));
    await session();
    expect(card, findsNothing, reason: 'the quiet start');
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);

    await tester.tap(find.byTooltip('Tipp ausblenden'));
    await tester.pump();
    expect(find.text('Alle Tipps unter Mehr → Tipps.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(card, findsNothing);
    expect(find.text('Alle Tipps unter Mehr → Tipps.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Alle Tipps unter Mehr → Tipps.'), findsNothing);
    expect(store.of('peter').of(HintId.editLongPress).dismissed, isTrue);

    now = now.add(const Duration(days: 3));
    await session();
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(card, findsNothing, reason: 'hidden for good');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a callout under Anpassen points up at its end', (tester) async {
    final order = hints.firstWhere((h) => h.id == HintId.storeOrder);
    await tester.pumpWidget(
      app(
        Align(
          alignment: Alignment.topRight,
          child: HintCallout(
            hint: order,
            pointing: AxisDirection.up,
            onAct: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );
    expect(find.text('Sortiert wie dein Laden'), findsOneWidget);
    final shape =
        (tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(HintCallout),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as ShapeDecoration)
            .shape;
    expect(shape, isA<CalloutBorder>().having((b) => b.up, 'up', isTrue));
    expect(find.byTooltip('Tipp ausblenden'), findsOneWidget);
  });

  group('Erste Schritte', () {
    Future<void> pump(
      WidgetTester tester,
      HouseholdKind? kind, {
      bool owner = true,
      UsageLog? log,
    }) => tester.pumpWidget(
      app(
        ChecklistCard(
          checklist: Checklist.of(
            log ?? UsageLog(since: DateTime(2026)),
            kind: kind,
            owner: owner,
          ),
          onDismiss: () {},
        ),
      ),
    );

    testWidgets('a partner household: invite and the first shop', (
      tester,
    ) async {
      await pump(tester, HouseholdKind.partner);
      expect(find.text('Erste Schritte'), findsOneWidget);
      expect(find.text('1 von 3'), findsOneWidget);
      expect(find.text('Liste angelegt'), findsOneWidget);
      expect(find.text('Partner einladen'), findsOneWidget);
      expect(find.text('Einmal einkaufen'), findsOneWidget);
      expect(find.text('Tippen hakt ab · Halten bearbeitet'), findsOneWidget);
      expect(find.text('KI-Assistenten verbinden'), findsNothing);
      expect(find.byTooltip('Erste Schritte ausblenden'), findsOneWidget);
    });

    testWidgets('shopping alone: no invite', (tester) async {
      await pump(tester, HouseholdKind.solo);
      expect(find.text('1 von 2'), findsOneWidget);
      expect(find.textContaining('einladen'), findsNothing);
      expect(find.text('Einladen'), findsNothing);
    });

    testWidgets('a club: members and the AI assistant', (tester) async {
      await pump(tester, HouseholdKind.club);
      expect(find.text('1 von 4'), findsOneWidget);
      expect(find.text('Mitglieder einladen'), findsOneWidget);
      expect(find.text('KI-Assistenten verbinden'), findsOneWidget);
      expect(find.text('Öffnen'), findsOneWidget);
    });

    testWidgets('joined: no invite, and it says so', (tester) async {
      await pump(tester, HouseholdKind.family, owner: false);
      expect(find.text('Haushalt beigetreten'), findsOneWidget);
      expect(find.text('Familie einladen'), findsNothing);
    });

    testWidgets('a done item loses its button', (tester) async {
      await pump(
        tester,
        HouseholdKind.club,
        log: UsageLog(since: DateTime(2026))
            .note(Signal.assistantConnected)
            .note(Signal.memberJoined),
      );
      expect(find.text('3 von 4'), findsOneWidget);
      expect(find.text('Öffnen'), findsNothing);
      expect(find.text('Einladen'), findsNothing);
    });
  });
}
