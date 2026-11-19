import 'package:family_groceries/core/notices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Snackbars over an open dialog or sheet (job 116): a page's Scaffold sits
/// under the popup's barrier, so they show above it while one is open.
void main() {
  late BuildContext page;
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    final popups = Popups();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [popups],
        builder: (_, child) => NoticesHost(popups: popups, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              page = context;
              return Center(
                child: TextButton(
                  key: const ValueKey('page-button'),
                  onPressed: () {},
                  child: const Text('page'),
                ),
              );
            },
          ),
          bottomNavigationBar: const ColoredBox(
            key: ValueKey('tabs'),
            color: Colors.white,
            child: SizedBox(height: 80),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester, {VoidCallback? onTap}) async {
    showDialog<void>(
      context: page,
      builder: (_) => AlertDialog(
        content: const TextField(key: ValueKey('dialog-field')),
        actions: [
          TextButton(
            key: const ValueKey('dialog-button'),
            onPressed: onTap,
            child: const Text('ok'),
          ),
        ],
      ),
    ).ignore();
    await tester.pumpAndSettle();
  }

  void show(String text, {VoidCallback? onUndo}) => Notices.of(page)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action: onUndo == null
            ? null
            : SnackBarAction(label: 'undo', onPressed: onUndo),
      ),
    );

  testWidgets('over an open dialog, the message is seen and its action '
      'tapped', (tester) async {
    await pump(tester);
    await openDialog(tester);
    var undone = false;
    show('refused', onUndo: () => undone = true);
    await tester.pumpAndSettle();
    expect(find.text('refused').hitTestable(), findsOneWidget);
    await tester.tap(find.text('undo'));
    expect(undone, isTrue);
    expect(key('dialog-field'), findsOneWidget, reason: 'the dialog stays');
  });

  testWidgets('the dialog and its barrier still take taps around it', (
    tester,
  ) async {
    await pump(tester);
    var tapped = false;
    await openDialog(tester, onTap: () => tapped = true);
    show('refused');
    await tester.pumpAndSettle();
    await tester.tap(key('dialog-button'));
    expect(tapped, isTrue);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(key('dialog-field'), findsNothing, reason: 'the barrier closed it');
    expect(find.text('refused'), findsNothing, reason: 'it went with it');
  });

  testWidgets('a screen reader reads it over the dialog', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await openDialog(tester);
    show('refused');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('refused'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('it stays above the keyboard the dialog opened', (tester) async {
    await pump(tester);
    await openDialog(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    show('refused');
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byType(SnackBar)).dy,
      lessThanOrEqualTo(800 - 300),
    );
  });

  testWidgets('without a dialog it shows on the page, above its tabs, and '
      'the page takes taps', (tester) async {
    await pump(tester);
    show('refused');
    await tester.pumpAndSettle();
    expect(find.text('refused').hitTestable(), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(SnackBar)).dy,
      lessThanOrEqualTo(tester.getTopLeft(key('tabs')).dy),
    );
    expect(key('page-button').hitTestable(), findsOneWidget);
  });

  testWidgets('where it shows is decided when it shows', (tester) async {
    await pump(tester);
    final notices = Notices.of(page);
    await openDialog(tester);
    notices.showSnackBar(const SnackBar(content: Text('later')));
    await tester.pumpAndSettle();
    expect(find.text('later').hitTestable(), findsOneWidget);

    Navigator.of(page).pop();
    await tester.pumpAndSettle();
    notices
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('on the page')));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.text('on the page')).dy,
      lessThanOrEqualTo(tester.getTopLeft(key('tabs')).dy),
      reason: 'the dialog closed: back on the page, above its tabs',
    );
  });

  testWidgets('closing the dialog takes its message along: the tabs take '
      'taps again, and the next message is the only one', (tester) async {
    await pump(tester);
    await openDialog(tester);
    show('refused');
    await tester.pumpAndSettle();
    expect(find.text('refused').hitTestable(), findsOneWidget);

    Navigator.of(page).pop();
    await tester.pumpAndSettle();
    expect(find.text('refused'), findsNothing);
    expect(key('tabs').hitTestable(), findsOneWidget);

    show('next');
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('a dialog closed while its message comes in leaves none '
      'behind', (tester) async {
    await pump(tester);
    await openDialog(tester);
    show('refused');
    Navigator.of(page).pop();
    await tester.pumpAndSettle();
    expect(find.text('refused').hitTestable(), findsNothing);
    expect(key('tabs').hitTestable(), findsOneWidget);
  });

  testWidgets('a dialog opened over a dialog keeps the message until the '
      'last one closes', (tester) async {
    await pump(tester);
    await openDialog(tester);
    show('refused');
    await tester.pumpAndSettle();
    showDialog<void>(
      context: page,
      builder: (_) => const AlertDialog(content: Text('second')),
    ).ignore();
    await tester.pumpAndSettle();
    Navigator.of(page).pop();
    await tester.pumpAndSettle();
    expect(find.text('refused').hitTestable(), findsOneWidget);
  });

  testWidgets('a page the router adds below an open dialog leaves the '
      'message above it', (tester) async {
    final popups = Popups();
    final pages = ValueNotifier(['a']);
    addTearDown(pages.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => NoticesHost(popups: popups, child: child!),
        home: ValueListenableBuilder(
          valueListenable: pages,
          builder: (_, names, _) => Navigator(
            observers: [popups],
            pages: [
              for (final name in names)
                MaterialPage<void>(
                  key: ValueKey(name),
                  child: Scaffold(body: Text('page $name')),
                ),
            ],
            onDidRemovePage: (_) {},
          ),
        ),
      ),
    );
    showDialog<void>(
      context: tester.element(find.text('page a')),
      useRootNavigator: false,
      builder: (_) => const AlertDialog(content: Text('dialog')),
    ).ignore();
    await tester.pumpAndSettle();
    pages.value = ['z', 'a'];
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);

    Notices.of(tester.element(find.text('page a')))
        .showSnackBar(const SnackBar(content: Text('refused')));
    await tester.pumpAndSettle();
    expect(find.text('refused').hitTestable(), findsOneWidget);
  });

  testWidgets('a bottom sheet counts as open too', (tester) async {
    await pump(tester);
    showModalBottomSheet<void>(
      context: page,
      useRootNavigator: true,
      builder: (_) => const SizedBox(height: 300, child: Text('sheet')),
    ).ignore();
    await tester.pumpAndSettle();
    show('refused');
    await tester.pumpAndSettle();
    expect(find.text('refused').hitTestable(), findsOneWidget);
  });
}
