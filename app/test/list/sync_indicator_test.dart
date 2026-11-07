import 'dart:async';
import 'dart:math';

import 'package:family_groceries/app/network.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/sync_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

void main() {
  group('the phases (reduceSync)', () {
    const hidden = SyncView();
    const offlineOpen = SyncView(
      phase: SyncPhase.open,
      kind: SyncTrouble.offline,
    );
    const offlinePill = SyncView(
      phase: SyncPhase.collapsed,
      kind: SyncTrouble.offline,
    );
    const failingOpen = SyncView(
      phase: SyncPhase.open,
      kind: SyncTrouble.failing,
    );
    const failingPill = SyncView(
      phase: SyncPhase.collapsed,
      kind: SyncTrouble.failing,
    );

    test('trouble opens the card; the same kind again never reopens it', () {
      expect(
        reduceSync(hidden, const TroubleChanged(SyncTrouble.offline)),
        offlineOpen,
      );
      expect(
        reduceSync(offlinePill, const TroubleChanged(SyncTrouble.offline)),
        offlinePill,
      );
      expect(
        reduceSync(failingPill, const TroubleChanged(SyncTrouble.failing)),
        failingPill,
      );
      expect(
        reduceSync(offlineOpen, const TroubleChanged(SyncTrouble.offline)),
        offlineOpen,
      );
    });

    test('another kind opens the card again', () {
      expect(
        reduceSync(offlinePill, const TroubleChanged(SyncTrouble.failing)),
        failingOpen,
      );
      expect(
        reduceSync(failingPill, const TroubleChanged(SyncTrouble.offline)),
        offlineOpen,
      );
    });

    test('no trouble hides it, keeping the face it fades with', () {
      for (final view in [offlineOpen, failingPill]) {
        final after = reduceSync(view, const TroubleChanged(null));
        expect(after.phase, SyncPhase.hidden);
        expect(after.kind, view.kind);
        expect(after.showsCard || after.showsPill, isFalse);
      }
      final gone = reduceSync(offlinePill, const TroubleChanged(null));
      expect(
        reduceSync(gone, const TroubleChanged(SyncTrouble.offline)),
        offlineOpen,
        reason: 'trouble after a clear spell is news',
      );
    });

    test('the timer, a scroll and a swipe up collapse the open card', () {
      for (final event in const [TimerFired(), Scrolled(), SwipedUp()]) {
        expect(reduceSync(offlineOpen, event), offlinePill, reason: '$event');
        expect(reduceSync(failingOpen, event), failingPill, reason: '$event');
        expect(reduceSync(offlinePill, event), offlinePill, reason: '$event');
        expect(reduceSync(hidden, event), hidden, reason: '$event');
      }
    });

    test('offline, a tap toggles the card', () {
      expect(reduceSync(offlinePill, const Tapped()), offlineOpen);
      expect(reduceSync(offlineOpen, const Tapped()), offlinePill);
    });

    test('failing, a tap on either form retries in that form', () {
      final fromPill = reduceSync(failingPill, const Tapped());
      expect(fromPill.phase, SyncPhase.busy);
      expect(fromPill.showsPill, isTrue);
      final fromCard = reduceSync(failingOpen, const Tapped());
      expect(fromCard.phase, SyncPhase.busy);
      expect(fromCard.showsCard, isTrue);
    });

    test('a tap while busy or hidden does nothing', () {
      final busy = reduceSync(failingOpen, const Tapped());
      expect(reduceSync(busy, const Tapped()), busy);
      expect(reduceSync(hidden, const Tapped()), hidden);
      final gone = reduceSync(failingPill, const TroubleChanged(null));
      expect(reduceSync(gone, const Tapped()), gone);
    });

    test('a busy form does not collapse or reopen while the retry runs', () {
      final busy = reduceSync(failingOpen, const Tapped());
      expect(reduceSync(busy, const TimerFired()), busy);
      expect(reduceSync(busy, const Scrolled()), busy);
      expect(reduceSync(busy, const TroubleChanged(SyncTrouble.failing)), busy);
    });

    test(
      'a retry that worked hides it; one that failed settles in the pill',
      () {
        for (final from in [failingOpen, failingPill]) {
          final busy = reduceSync(from, const Tapped());
          expect(
            reduceSync(busy, const RetryDone(ok: true)).phase,
            SyncPhase.hidden,
          );
          expect(reduceSync(busy, const RetryDone(ok: false)), failingPill);
        }
        expect(
          reduceSync(offlinePill, const RetryDone(ok: false)),
          offlinePill,
        );
      },
    );
  });

  group('on the list', () {
    late FakeRepository repo;

    /// The one hex shell, in either form.
    Finder shell() => find.byKey(const ValueKey('sync-indicator'));

    /// The shell's content in the open and in the folded form.
    Finder card() => find.byKey(const ValueKey('sync-card'));
    Finder pill() => find.byKey(const ValueKey('sync-pill'));
    Finder edit() => find.byKey(const ValueKey('list-edit'));
    ListCubit cubit(WidgetTester tester) =>
        tester.element(find.byType(ShoppingList)).read<ListCubit>();

    void phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = size * 3;
      addTearDown(tester.view.reset);
    }

    Future<void> pumpList(
      WidgetTester tester, {
      Locale locale = const Locale('de'),
      Brightness brightness = Brightness.light,
      bool reduceMotion = false,
      Stream<Network>? network,
    }) async {
      repo = FakeRepository();
      [
        'Äpfel',
        'Birnen',
        'Gurke',
        'Tomaten',
        'Paprika',
        'Zucchini',
        'Möhren',
        'Kartoffeln',
        'Zwiebeln',
        'Knoblauch',
        'Salat',
        'Spinat',
        'Brokkoli',
        'Zitronen',
      ].forEach(repo.remoteAdd);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: BlocProvider(
            create: (_) => ListCubit(
              repo,
              MemoryListCache(),
              userId: 'peter',
              network: network,
            )..start(),
            child: const ShoppingList(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.emitStatus!(ConnectionStatus.online);
      await tester.pumpAndSettle();
    }

    /// The channel drops; nothing can be sent.
    Future<void> goOffline(WidgetTester tester) async {
      repo.online = false;
      repo.emitStatus!(ConnectionStatus.offline);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    /// The server answers every read with a 503, until the list calls it
    /// failing (after its automatic retry, since job 165).
    Future<void> goFailing(WidgetTester tester) async {
      repo.fetchTrouble = true;
      unawaited(cubit(tester).resync());
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (cubit(tester).state.trouble == SyncTrouble.failing) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(cubit(tester).state.trouble, SyncTrouble.failing);
      await tester.pumpAndSettle();
    }

    /// Lets the cubit's own retries run out before the test ends.
    Future<void> recover(WidgetTester tester) async {
      repo
        ..online = true
        ..fetchTrouble = false;
      repo.emitStatus!(ConnectionStatus.online);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    }

    /// The indicator's semantics node, by the start of its label.
    Finder node(String start) => find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.label?.startsWith(start) ?? false),
    );

    testWidgets('online shows nothing, also with a change pending', (
      tester,
    ) async {
      phone(tester);
      await pumpList(tester);
      expect(card(), findsNothing);
      expect(pill(), findsNothing);

      repo.gate = Completer<void>();
      cubit(tester).addEntry(const Entry('Kaffee', null));
      await tester.pump(const Duration(seconds: 1));
      expect(cubit(tester).state.pending, isNotEmpty);
      expect(card(), findsNothing);
      expect(pill(), findsNothing);
      repo.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('offline opens the card, the pill after 3 s; back online it '
        'goes without a word', (tester) async {
      phone(tester);
      await pumpList(tester);
      final handle = tester.ensureSemantics();
      await goOffline(tester);
      expect(card(), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget, reason: 'the title');
      expect(pill(), findsNothing);

      await tester.pump(const Duration(milliseconds: 2400));
      expect(card(), findsOneWidget, reason: 'not yet');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(card(), findsNothing);
      expect(pill(), findsOneWidget);
      expect(
        tester.getRect(pill()).right,
        lessThan(tester.getRect(edit()).left),
      );

      await recover(tester);
      expect(card(), findsNothing);
      expect(pill(), findsNothing);
      expect(tester.takeAnnouncements(), isEmpty, reason: 'no confirmation');
      handle.dispose();
    });

    testWidgets('the OS network going down opens the card with no tap; back '
        'up it goes on its own (job 166)', (tester) async {
      phone(tester);
      final network = StreamController<Network>();
      addTearDown(network.close);
      await pumpList(tester, network: network.stream);
      network.add(Network.up);
      await tester.pumpAndSettle();
      expect(card(), findsNothing);

      repo.online = false;
      network.add(Network.down);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(card(), findsOneWidget, reason: 'no channel drop, no request');
      expect(find.text('Offline'), findsOneWidget);

      // Past the 3 s retry, which failed; the next comes at 6 s.
      await tester.pump(const Duration(milliseconds: 3100));
      expect(pill(), findsOneWidget);
      repo.online = true;
      network.add(Network.up);
      await tester.pump();
      await tester.pump(networkSettle - const Duration(milliseconds: 100));
      expect(pill(), findsOneWidget, reason: 'the network has to hold');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(card(), findsNothing);
      expect(pill(), findsNothing);
    });

    testWidgets('the fading card text stays inside the shrinking hex', (
      tester,
    ) async {
      phone(tester);
      await pumpList(tester);
      await goOffline(tester);
      await tester.tap(node('Offline:'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final fading = tester.layers.whereType<OpacityLayer>().where(
        (l) => (l.alpha ?? 255) > 0 && (l.alpha ?? 255) < 255,
      );
      expect(fading, isNotEmpty, reason: 'the card text is fading');
      for (final layer in fading) {
        var clipped = false;
        for (Layer? up = layer.parent; up != null; up = up.parent) {
          clipped = clipped || up is ClipPathLayer;
        }
        expect(clipped, isTrue, reason: 'a fading part under the hex clip');
      }
      await tester.pumpAndSettle();
    });

    testWidgets('one shell folds from the card into the pill and back, '
        'moving and resizing on the way', (tester) async {
      phone(tester);
      await pumpList(tester);
      await goOffline(tester);
      // By its semantics node: the shell a screen reader and a finger find.
      Finder shell() => node('Offline:');
      expect(shell(), findsOneWidget);
      final card = tester.getRect(shell());

      /// The shell's rect at every frame after a tap on it, settled last.
      Future<List<Rect>> fold() async {
        await tester.tap(shell());
        final rects = <Rect>[];
        for (var ms = 16; ms <= 480; ms += 16) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(shell(), findsOneWidget, reason: 'one shell at $ms ms');
          rects.add(tester.getRect(shell()));
        }
        await tester.pumpAndSettle();
        rects.add(tester.getRect(shell()));
        return rects;
      }

      void travels(List<Rect> rects, Rect from, Rect to) {
        double? Function(Rect) side(String name) => switch (name) {
          'top' => (r) => r.top,
          'width' => (r) => r.width,
          _ => (r) => r.height,
        };
        for (final name in ['top', 'width', 'height']) {
          final of = side(name);
          final sign = (of(to)! - of(from)!).sign;
          expect(sign, isNot(0), reason: '$name differs between the forms');
          var before = of(from)!;
          for (final (i, rect) in rects.indexed) {
            expect(
              (of(rect)! - before) * sign,
              greaterThanOrEqualTo(-0.01),
              reason: '$name runs one way, frame $i: $rects',
            );
            before = of(rect)!;
          }
        }
        expect(
          rects.any(
            (r) => [r.top, r.width, r.height].indexed.every((e) {
              final (i, v) = e;
              final a = [from.top, from.width, from.height][i];
              final b = [to.top, to.width, to.height][i];
              return v > min(a, b) + 0.5 && v < max(a, b) - 0.5;
            }),
          ),
          isTrue,
          reason: 'a frame between the forms in top, width and height: $rects',
        );
        expect(rects.last, to);
      }

      final there = await fold();
      final pill = there.last;
      expect(pill.height, 48, reason: 'the pill: a 48 px target');
      expect(pill.width, lessThan(card.width / 2));
      travels(there, card, pill);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget, reason: 'one icon');

      travels(await fold(), pill, card);
      await recover(tester);
    });

    testWidgets('a scroll of the list collapses the card at once', (
      tester,
    ) async {
      phone(tester);
      await pumpList(tester);
      await goOffline(tester);
      await tester.drag(find.text('Gurke'), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(card(), findsNothing);
      expect(pill(), findsOneWidget);
      await recover(tester);
    });

    testWidgets('a swipe up on the card collapses it', (tester) async {
      phone(tester);
      await pumpList(tester);
      await goOffline(tester);
      await tester.drag(card(), const Offset(0, -10));
      await tester.pump();
      expect(card(), findsOneWidget, reason: 'under 20 px');
      await tester.drag(card(), const Offset(0, -30));
      await tester.pumpAndSettle();
      expect(card(), findsNothing);
      expect(pill(), findsOneWidget);
      await recover(tester);
    });

    testWidgets('offline, a tap on the pill opens the card and a tap on the '
        'card closes it, retrying nothing', (tester) async {
      phone(tester);
      await pumpList(tester);
      await goOffline(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(pill());
      await tester.pumpAndSettle();
      expect(card(), findsOneWidget);
      await tester.tap(card());
      await tester.pump();
      expect(find.byIcon(Icons.sync), findsNothing, reason: 'no retry');
      await tester.pumpAndSettle();
      expect(card(), findsNothing);
      expect(pill(), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      await recover(tester);
    });

    testWidgets('the same trouble on the next retry does not reopen the card', (
      tester,
    ) async {
      phone(tester);
      await pumpList(tester);
      await goFailing(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(pill(), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      await tester.pumpAndSettle();
      expect(card(), findsNothing);
      expect(pill(), findsOneWidget);

      repo.emitStatus!(ConnectionStatus.offline);
      repo.online = false;
      await tester.pumpAndSettle();
      expect(card(), findsOneWidget, reason: 'another kind is news');
      await recover(tester);
    });

    testWidgets('failing, a tap retries; success hides it and says '
        '"Synchronisiert"', (tester) async {
      phone(tester);
      await pumpList(tester);
      await goFailing(tester);
      expect(find.text('Sync gestört'), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-retry')), findsOneWidget);
      tester.takeAnnouncements();

      final held = repo.itemsGate = Completer<void>();
      repo.fetchTrouble = false;
      await tester.tap(find.byKey(const ValueKey('sync-retry')));
      await tester.pump();
      expect(find.byIcon(Icons.sync), findsOneWidget, reason: 'busy');
      held.complete();
      repo.itemsGate = null;
      await tester.pumpAndSettle();
      expect(card(), findsNothing);
      expect(pill(), findsNothing);
      expect(tester.takeAnnouncements(), [
        isAccessibilityAnnouncement('Synchronisiert'),
      ]);
    });

    testWidgets('a retry that fails again settles in the pill and says '
        '"Immer noch gestört"', (tester) async {
      phone(tester);
      await pumpList(tester);
      await goFailing(tester);
      tester.takeAnnouncements();
      await tester.tap(card());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(card(), findsNothing);
      expect(pill(), findsOneWidget);
      expect(find.byIcon(Icons.sync_problem), findsOneWidget);
      expect(tester.takeAnnouncements(), [
        isAccessibilityAnnouncement('Immer noch gestört'),
      ]);

      // From the pill too.
      await tester.tap(pill());
      await tester.pumpAndSettle();
      expect(pill(), findsOneWidget);
      expect(tester.takeAnnouncements(), [
        isAccessibilityAnnouncement('Immer noch gestört'),
      ]);
      await recover(tester);
    });

    testWidgets('reduced motion only fades: no morph, scale, slide or turn', (
      tester,
    ) async {
      phone(tester);
      await pumpList(tester, reduceMotion: true);

      /// Anything between the indicator and [of] that moves it. Inside the
      /// shell only turns count: its face moves when pressed, as every
      /// raised button's does.
      Finder moving(Finder of, {bool transforms = true}) => find.ancestor(
        of: of,
        matching: find.descendant(
          of: find.byType(SyncIndicator),
          matching: find.byWidgetPredicate(
            (w) =>
                w is ScaleTransition ||
                w is SlideTransition ||
                w is RotationTransition ||
                (transforms && w is Transform && !w.transform.isIdentity()),
          ),
        ),
      );
      double opacity() => tester
          .widgetList<Opacity>(
            find.ancestor(of: shell(), matching: find.byType(Opacity)),
          )
          .fold(1, (o, w) => o * w.opacity);

      await goFailing(tester);
      final open = tester.getRect(shell());
      expect(card(), findsOneWidget);
      await tester.tap(card());
      final rects = <Rect>{};
      var faded = false;
      for (var ms = 0; ms < 2000; ms += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(moving(shell()), findsNothing, reason: 'no scale or nudge');
        rects.add(tester.getRect(shell()));
        faded |= opacity() < 0.5;
      }
      await tester.pumpAndSettle();
      expect(pill(), findsOneWidget, reason: 'the retry failed');
      final pillRect = tester.getRect(shell());
      expect(rects, {open, pillRect}, reason: 'no rect between the forms');
      expect(faded, isTrue, reason: 'the forms crossfade');

      final held = repo.itemsGate = Completer<void>();
      repo.fetchTrouble = false;
      await tester.tap(pill());
      for (final step in [50, 250, 500]) {
        await tester.pump(Duration(milliseconds: step));
        expect(find.byIcon(Icons.sync), findsOneWidget, reason: 'busy');
        expect(
          moving(find.byIcon(Icons.sync), transforms: false),
          findsNothing,
          reason: 'the arrows pulse instead of turning',
        );
      }
      held.complete();
      repo.itemsGate = null;
      await tester.pumpAndSettle();
      expect(shell(), findsNothing);
      await recover(tester);
    });

    for (final (locale, offline, failing, retry, details) in [
      (
        const Locale('de'),
        'Offline: Änderungen werden synchronisiert, sobald du wieder online '
            'bist.',
        'Sync gestört: Deine Änderungen sind auf dem Gerät gespeichert.',
        'Erneut versuchen',
        'Details anzeigen',
      ),
      (
        const Locale('en'),
        "Offline: Your changes will sync once you're back online.",
        'Sync failing: Your changes are saved on this device.',
        'Try again',
        'Show details',
      ),
    ]) {
      testWidgets('one node a screen reader reads (${locale.languageCode})', (
        tester,
      ) async {
        phone(tester);
        final handle = tester.ensureSemantics();
        await pumpList(tester, locale: locale);
        await goOffline(tester);
        expect(node('Offline:'), findsOneWidget);
        expect(
          tester.getSemantics(node('Offline:')),
          matchesSemantics(
            label: offline,
            isButton: true,
            hasTapAction: true,
            hasExpandedState: true,
            isExpanded: true,
          ),
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(
          node('Offline:'),
          findsOneWidget,
          reason: 'the pill says it all',
        );
        expect(
          tester.getSemantics(node('Offline:')),
          matchesSemantics(
            label: offline,
            hint: details,
            isButton: true,
            hasTapAction: true,
            hasExpandedState: true,
          ),
        );

        await recover(tester);
        expect(node('Offline:'), findsNothing);
        await goFailing(tester);
        final start = failing.substring(0, failing.indexOf(':') + 1);
        expect(node(start), findsOneWidget);
        expect(
          tester.getSemantics(node(start)),
          matchesSemantics(
            label: failing,
            hint: retry,
            isButton: true,
            hasTapAction: true,
          ),
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(node(start), findsOneWidget);
        await recover(tester);
        handle.dispose();
      });
    }

    testWidgets('Anpassen and the list stay put in every state', (
      tester,
    ) async {
      phone(tester);
      await pumpList(tester);
      final anpassen = tester.getRect(edit());
      final first = tester.getRect(find.text('Äpfel'));
      void same(String reason) {
        expect(tester.getRect(edit()), anpassen, reason: reason);
        expect(tester.getRect(find.text('Äpfel')), first, reason: reason);
      }

      await goOffline(tester);
      await tester.pumpAndSettle();
      same('offline, open');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      same('offline, collapsed');
      await recover(tester);
      same('online');
      await goFailing(tester);
      await tester.pumpAndSettle();
      same('failing, open');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      same('failing, collapsed');
      await recover(tester);
    });

    for (final locale in const [Locale('de'), Locale('en')]) {
      testWidgets('fits 320 px at text scale 2 (${locale.languageCode})', (
        tester,
      ) async {
        phone(tester, size: const Size(320, 568));
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpList(tester, locale: locale);
        for (final go in [goOffline, goFailing]) {
          await go(tester);
          await tester.pumpAndSettle();
          expect(card(), findsOneWidget);
          expect(tester.getSize(shell()).height, greaterThanOrEqualTo(48));
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(pill(), findsOneWidget);
          final folded = tester.getRect(shell());
          expect(folded.height, greaterThanOrEqualTo(48));
          expect(folded.right, lessThanOrEqualTo(tester.getRect(edit()).left));
          await recover(tester);
        }
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('text on both faces is readable (${brightness.name})', (
        tester,
      ) async {
        phone(tester);
        await pumpList(tester, brightness: brightness);
        void readable(Finder form) {
          final face = tester
              .widget<TactileFace>(
                find
                    .descendant(of: shell(), matching: find.byType(TactileFace))
                    .first,
              )
              .colors
              .face;
          final texts = tester.widgetList<Text>(
            find.descendant(of: form, matching: find.byType(Text)),
          );
          expect(texts, isNotEmpty);
          for (final text in texts) {
            expect(
              contrastRatio(text.style!.color!, face),
              greaterThanOrEqualTo(4.5),
              reason: '${text.data} on $face',
            );
          }
        }

        for (final go in [goOffline, goFailing]) {
          await go(tester);
          await tester.pumpAndSettle();
          readable(card());
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          readable(pill());
          await recover(tester);
        }
      });
    }
  });
}
