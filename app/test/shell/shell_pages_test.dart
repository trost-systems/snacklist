import 'package:family_groceries/shell/router.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';

/// Every page the shell shows, from its route tables: a page added later is
/// checked too. Redirects show no page of their own.
Iterable<String> _pages(List<RouteBase> routes, [String parent = '']) sync* {
  for (final route in routes.whereType<GoRoute>()) {
    final path = route.path.startsWith('/')
        ? route.path
        : '${parent == '/' ? '' : parent}/${route.path}';
    if (route.redirect == null) {
      yield path.replaceAll(':store', 'lidl');
    }
    yield* _pages(route.routes, path);
  }
}

/// The pages run on behind the floating tab pill (job 144): scrolled to the
/// end, each one's last content stands clear above it.
void main() {
  setUpAll(fakeSupabase);

  final pages = _pages([...listTabRoutes(), ...moreTabRoutes()]).toList();

  test('the route tables give the pages', () {
    expect(pages, containsAll(['/', '/edit', '/edit/lidl', '/more']));
    expect(pages, containsAll(['/more/invites', '/more/settings/language']));
  });

  // An iPhone upright, and a smaller one on its side (its home indicator
  // 21 px there); from 840 px wide the tabs are a rail.
  for (final (size, inset) in const [
    (Size(390, 844), 34.0),
    (Size(812, 375), 21.0),
  ]) {
    for (final path in pages) {
      testWidgets('$path ends above the tab pill at $size', (tester) async {
        tester.view
          ..padding = FakeViewPadding(bottom: inset)
          ..viewPadding = FakeViewPadding(bottom: inset);
        await pumpMore(tester, location: path, size: size, app: true);
        expect(find.byKey(const ValueKey('tab-list')), findsOneWidget);
        final pill = tester.getRect(find.byKey(const ValueKey('tab-list')));
        final page = find.byType(StatefulNavigationShell);
        for (var pass = 0; pass < 2; pass++) {
          for (final scrollable in tester.stateList<ScrollableState>(
            find.descendant(of: page, matching: find.byType(Scrollable)),
          )) {
            if (scrollable.position.axis == Axis.vertical) {
              scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
            }
          }
          await tester.pumpAndSettle();
        }
        final content = find.descendant(
          of: page,
          matching: find.byWidgetPredicate(
            (w) => w is RichText || w is EditableText || w is Image,
          ),
        );
        expect(content, findsWidgets);
        final (bottom, what) = content
            .evaluate()
            .map((e) {
              final box = e.renderObject! as RenderBox;
              final rect = box.localToGlobal(Offset.zero) & box.size;
              return (rect.bottom, e.widget.toStringShort());
            })
            .reduce((a, b) => a.$1 >= b.$1 ? a : b);
        expect(
          bottom,
          lessThanOrEqualTo(pill.top),
          reason: '$path: $what ends at $bottom, under the pill at ${pill.top}',
        );
      });
    }
  }

  // Job 159: a mouse wheel over the pill scrolls the page under it.
  for (final path in ['/', '/more']) {
    testWidgets('the wheel over the tab pill scrolls $path', (tester) async {
      await pumpMore(
        tester,
        location: path,
        app: true,
        seed: (repo) {
          for (var i = 0; i < 30; i++) {
            repo.remoteAdd('Artikel $i', categoryId: 'produce');
          }
        },
      );
      final page = tester
          .stateList<ScrollableState>(
            find.descendant(
              of: find.byType(StatefulNavigationShell),
              matching: find.byType(Scrollable),
            ),
          )
          .firstWhere((s) => s.position.axis == Axis.vertical)
          .position;
      expect(page.pixels, 0);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.hover(tester.getCenter(find.byKey(const ValueKey('tab-list')))),
      );
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      expect(page.pixels, 120);
    });
  }
}
