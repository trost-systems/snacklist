// Job 488: Tab scrolls the control it focuses into view, above as well as
// below. Flutter's own request scrolls only down for Tab, so a Tab from the
// last control of a scrolled page to the first left that one out of sight.
import 'package:family_groceries/design/focus_ring.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester, FocusTraversalPolicy policy) =>
      tester.pumpWidget(
        MaterialApp(
          // Around the navigator, as the app's builder has it: Tab past a
          // page's last control goes on in the group above the page.
          builder: (context, child) =>
              FocusTraversalGroup(policy: policy, child: child!),
          home: Scaffold(
            body: ListView(
              // Every row built, as in the add sheet's short list: Tab
              // finds the first one even while it is far above.
              scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
              children: [
                for (var i = 0; i < 20; i++)
                  SizedBox(
                    height: 80,
                    child: TextButton(
                      onPressed: () {},
                      child: Text('Knopf $i'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  Future<Rect> tabFromLastToFirst(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Knopf 19'), 200);
    Focus.of(tester.element(find.text('Knopf 19'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus,
      Focus.of(tester.element(find.text('Knopf 0', skipOffstage: false))),
    );
    return tester.getRect(find.text('Knopf 0', skipOffstage: false));
  }

  testWidgets('Tab from the last control to the first scrolls up to it', (
    tester,
  ) async {
    await pumpPage(
      tester,
      ReadingOrderTraversalPolicy(requestFocusCallback: revealFocus),
    );
    final screen =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final first = await tabFromLastToFirst(tester);
    expect(screen.intersect(first), first);
  });

  testWidgets("Flutter's own request leaves it out of sight", (tester) async {
    await pumpPage(tester, ReadingOrderTraversalPolicy());
    final screen =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final first = await tabFromLastToFirst(tester);
    expect(screen.overlaps(first), isFalse);
  });

  testWidgets('Tab down to a control below still scrolls to it', (
    tester,
  ) async {
    await pumpPage(
      tester,
      ReadingOrderTraversalPolicy(requestFocusCallback: revealFocus),
    );
    final screen =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    Focus.of(tester.element(find.text('Knopf 0'))).requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    final twelfth = tester.getRect(find.text('Knopf 12'));
    expect(screen.intersect(twelfth), twelfth);
  });
}
