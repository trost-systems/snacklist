// The controls FH1 (job 487) puts a focus ring in, each alone on a small
// screen, for focus_ring_test.dart and focus_ring_golden_test.dart.
import 'dart:ui' as ui;

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/hex_checkbox.dart';
import 'package:family_groceries/design/hex_pill.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/hex_segmented.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/leaving_rows.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _at = DateTime.utc(2026, 11);

final _milk = Item(
  id: 'milk',
  name: 'Milch',
  status: ItemStatus.active,
  createdAt: _at,
  updatedAt: _at,
  categoryId: 'dairy',
  sortKey: 0,
);

/// A hex of [size] centred in the box of [control]: where a check box,
/// switch or radio draws.
Rect Function(WidgetTester) _centred(Finder control, Size size) =>
    (tester) => Rect.fromCenter(
      center: tester.getCenter(control),
      width: size.width,
      height: size.height,
    );

Rect Function(WidgetTester) _rectOf(Finder finder) =>
    (tester) => tester.getRect(finder);

/// The focus node of the control around [inside].
FocusNode Function(WidgetTester) _above(Finder inside) =>
    (tester) => Focus.of(tester.element(inside));

/// One control: build it, focus its node, and the ring shows in navy when
/// honey (else cobalt), within its bounds. An InkWell control shows it only
/// for keyboard focus.
typedef FocusCase = ({
  String name,
  Widget Function() build,
  FocusNode Function(WidgetTester) node,
  Rect Function(WidgetTester) bounds,
  bool honey,
  bool inkWell,
});

final focusCases = <FocusCase>[
  for (final picked in [false, true])
    (
      name: picked ? 'picked chip' : 'chip',
      build: () => FocusRingChip(
        chip: FilterChip(
          label: const Text('Lidl'),
          selected: picked,
          onSelected: (_) {},
        ),
      ),
      node: _above(find.text('Lidl')),
      bounds: _rectOf(
        find
            .descendant(
              of: find.byType(FilterChip),
              matching: find.byType(Material),
            )
            .first,
      ),
      honey: picked,
      inkWell: true,
    ),
  for (final picked in [false, true])
    (
      name: picked ? 'picked option' : 'option',
      build: () =>
          OptionChip(label: 'Kühlregal', selected: picked, onTap: () {}),
      node: _above(find.text('Kühlregal')),
      bounds: _rectOf(
        find
            .descendant(
              of: find.byType(OptionChip),
              matching: find.byType(Material),
            )
            .first,
      ),
      honey: picked,
      inkWell: true,
    ),
  (
    name: 'primary button',
    build: () => FilledButton(onPressed: () {}, child: const Text('Weiter')),
    node: _above(find.text('Weiter')),
    bounds: _rectOf(find.byType(FilledButton)),
    honey: true,
    inkWell: false,
  ),
  (
    name: 'secondary button',
    build: () => OutlinedButton(onPressed: () {}, child: const Text('Später')),
    node: _above(find.text('Später')),
    bounds: _rectOf(find.byType(OutlinedButton)),
    honey: false,
    inkWell: false,
  ),
  (
    name: 'text button',
    build: () => TextButton(onPressed: () {}, child: const Text('Eigener')),
    node: _above(find.text('Eigener')),
    bounds: _rectOf(find.byType(TextButton)),
    honey: false,
    inkWell: true,
  ),
  (
    name: 'text field',
    build: () => const SizedBox(
      width: 240,
      child: TextField(
        autofillHints: null,
        decoration: InputDecoration(hintText: 'Laden'),
      ),
    ),
    node: (tester) => tester
        .state<EditableTextState>(find.byType(EditableText))
        .widget
        .focusNode,
    bounds: _rectOf(find.byType(InputDecorator)),
    honey: false,
    inkWell: false,
  ),
  for (final own in [false, true])
    (
      name: own ? 'icon button with its own colour' : 'icon button',
      build: () => IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Schließen',
        color: own ? const Color(0xFFB3261E) : null,
        focusColor: own ? Colors.transparent : null,
        onPressed: () {},
      ),
      node: _above(find.byIcon(Icons.close)),
      bounds: _rectOf(
        find
            .descendant(
              of: find.byType(IconButton),
              matching: find.byType(Material),
            )
            .first,
      ),
      honey: false,
      inkWell: true,
    ),
  for (final picked in [false, true])
    (
      name: picked ? 'picked card' : 'card',
      build: () => Builder(
        builder: (context) {
          final t = SnacklistColors.of(Theme.of(context).brightness);
          return SizedBox(
            width: 240,
            child: HlSticker(
              color: picked ? t.honey : null,
              child: Material(
                type: MaterialType.transparency,
                child: FocusRingInkWell(
                  outline: HlSticker.innerOutline,
                  color: focusRingColor(t, honey: picked ? 1 : 0),
                  onTap: () {},
                  child: const Padding(
                    padding: EdgeInsets.all(HlSpace.s3),
                    child: Text('Jährlich'),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      node: _above(find.text('Jährlich')),
      bounds: _rectOf(find.byType(HlSticker)),
      honey: picked,
      inkWell: true,
    ),
  (
    name: 'pill',
    build: () => SizedBox(
      width: 300,
      child: HexPill(
        onTap: () {},
        child: const Row(children: [Expanded(child: PillTitle('Bäcker'))]),
      ),
    ),
    node: _above(find.text('Bäcker')),
    bounds: _rectOf(
      find
          .descendant(of: find.byType(HexPill), matching: find.byType(Material))
          .first,
    ),
    honey: false,
    inkWell: true,
  ),
  (
    name: 'list row',
    build: () => SizedBox(
      width: 358,
      child: ItemRow(
        item: _milk,
        category: null,
        leaving: LeavingRows(),
        fresh: false,
        last: true,
        onVisible: (_) {},
        onTickStart: (_) {},
        onTick: (_) {},
        onEdit: (_) {},
        onDelete: (_) {},
      ),
    ),
    node: _above(find.text('Milch')),
    bounds: _rectOf(
      find
          .descendant(of: find.byType(ItemRow), matching: find.byType(InkWell))
          .first,
    ),
    honey: false,
    inkWell: true,
  ),
  for (final on in [false, true]) ...[
    (
      name: on ? 'checked check box' : 'check box',
      build: () => HexCheckbox(value: on, onChanged: (_) {}),
      node: _above(
        find
            .descendant(
              of: find.byType(HexCheckbox),
              matching: find.byType(CustomPaint),
            )
            .first,
      ),
      bounds: (tester) => _centred(
        find.byType(HexCheckbox),
        softLook
            ? const Size.square(HexCheckbox.height * 0.866)
            : const Size(HexCheckbox.height * 0.866, HexCheckbox.height),
      )(tester),
      honey: on,
      inkWell: false,
    ),
    (
      name: on ? 'switch on' : 'switch off',
      build: () => HexSwitch(value: on, onChanged: (_) {}),
      node: _above(
        find
            .descendant(
              of: find.byType(HexSwitch),
              matching: find.byType(CustomPaint),
            )
            .first,
      ),
      bounds: _centred(find.byType(HexSwitch), HexSwitch.track),
      honey: on,
      inkWell: false,
    ),
    (
      name: on ? 'picked radio' : 'radio',
      build: () => RadioGroup<int>(
        groupValue: on ? 1 : 0,
        onChanged: (_) {},
        child: const HexRadio<int>(value: 1),
      ),
      node: _above(
        find
            .descendant(
              of: find.byType(HexRadio<int>),
              matching: find.byType(CustomPaint),
            )
            .first,
      ),
      bounds: _centred(find.byType(HexRadio<int>), HexRadio.hex),
      honey: on,
      inkWell: false,
    ),
  ],
  for (final (label, picked) in [('Hell', true), ('Dunkel', false)])
    (
      name: picked ? 'picked segment' : 'segment',
      build: () => SizedBox(
        width: 300,
        child: HexSegmented<int>(
          value: 1,
          onChanged: (_) {},
          segments: const [
            HexSegment(value: 1, label: 'Hell'),
            HexSegment(value: 2, label: 'Dunkel'),
          ],
        ),
      ),
      node: _above(find.text(label)),
      // The honey indicator's hex: the segment's share, s1 in from the
      // track's top and bottom.
      bounds: (tester) => tester
          .getRect(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(Expanded),
            ),
          )
          .copyWithVertical(HlBorder.width + 2),
      honey: picked,
      inkWell: false,
    ),
  (
    name: 'list tile',
    build: () => SizedBox(
      width: 300,
      child: FocusRingTile(
        child: ListTile(
          title: const Text('Sprache'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),
      ),
    ),
    node: _above(find.text('Sprache')),
    bounds: _rectOf(find.byType(ListTile)),
    honey: false,
    inkWell: true,
  ),
  for (final on in [false, true]) ...[
    (
      name: on ? 'switch tile on' : 'switch tile off',
      build: () => SizedBox(
        width: 300,
        child: HexSwitchTile(
          title: const Text('Erinnerungen'),
          value: on,
          onChanged: (_) {},
        ),
      ),
      node: _above(find.text('Erinnerungen')),
      bounds: _rectOf(find.byType(ListTile)),
      honey: false,
      inkWell: true,
    ),
    (
      name: on ? 'checked check box tile' : 'check box tile',
      build: () => SizedBox(
        width: 300,
        child: HexCheckboxListTile(
          title: const Text('Preise'),
          value: on,
          onChanged: (_) {},
        ),
      ),
      node: _above(find.text('Preise')),
      bounds: _rectOf(find.byType(ListTile)),
      honey: false,
      inkWell: true,
    ),
    (
      name: on ? 'picked radio tile' : 'radio tile',
      build: () => SizedBox(
        width: 300,
        child: RadioGroup<int>(
          groupValue: on ? 1 : 0,
          onChanged: (_) {},
          child: const HexRadioTile<int>(value: 1, title: Text('Euro')),
        ),
      ),
      node: _above(find.text('Euro')),
      bounds: _rectOf(find.byType(ListTile)),
      honey: false,
      inkWell: true,
    ),
  ],
  (
    name: 'tile in a group',
    build: () => SizedBox(
      width: 360,
      child: HlGroup(
        top: 0,
        children: [
          FocusRingTile(
            child: ListTile(title: const Text('Konto'), onTap: () {}),
          ),
          FocusRingTile(
            child: ListTile(title: const Text('Hilfe'), onTap: () {}),
          ),
        ],
      ),
    ),
    node: _above(find.text('Konto')),
    bounds: _rectOf(find.byType(ListTile).first),
    honey: false,
    inkWell: true,
  ),
  (
    name: 'Material check box tile',
    build: () => SizedBox(
      width: 300,
      child: FocusRingTile(
        child: CheckboxListTile(
          title: const Text('Verstanden'),
          value: true,
          onChanged: (_) {},
        ),
      ),
    ),
    node: _above(find.text('Verstanden')),
    bounds: _rectOf(find.byType(ListTile)),
    honey: false,
    inkWell: true,
  ),
  (
    name: 'Material radio tile',
    build: () => SizedBox(
      width: 300,
      child: RadioGroup<int>(
        groupValue: 1,
        onChanged: (_) {},
        child: const FocusRingTile(
          child: RadioListTile<int>(value: 1, title: Text('Franken')),
        ),
      ),
    ),
    node: _above(find.text('Franken')),
    bounds: _rectOf(find.byType(ListTile)),
    honey: false,
    inkWell: true,
  ),
  (
    name: 'open expansion tile',
    build: () => SizedBox(
      width: 300,
      child: FocusRingTile(
        child: ExpansionTile(
          title: const Text('Zuletzt benutzt'),
          initiallyExpanded: true,
          children: [InkWell(onTap: () {}, child: const Text('Butter'))],
        ),
      ),
    ),
    node: _above(find.text('Zuletzt benutzt')),
    // The header only, not the rows below it.
    bounds: _rectOf(find.byType(ListTile)),
    honey: false,
    inkWell: true,
  ),
];

extension on Rect {
  /// This rect moved in by [inset] at the top and bottom.
  Rect copyWithVertical(double inset) =>
      Rect.fromLTRB(left, top + inset, right, bottom - inset);
}

final _boundary = GlobalKey();

/// Pumps [c] alone, centred on a 400 x 240 screen above a neighbour text.

Future<void> pumpFocusCase(
  WidgetTester tester,
  Brightness brightness,
  FocusCase c,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(400, 240);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(brightness),
      locale: const Locale('de'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepaintBoundary(
        key: _boundary,
        child: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Its own key: the next case of the same shape would keep this
                // one's element, and with it the focus.
                KeyedSubtree(key: ValueKey(c.name), child: c.build()),
                const Text('Nachbar', key: ValueKey('neighbour')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The screen [pumpFocusCase] built, as it shows now.
Future<ui.Image> captureFocusCase(WidgetTester tester) async => (await tester
    .runAsync(() => captureImage(_boundary.currentContext! as Element)))!;
