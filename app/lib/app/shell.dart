import 'dart:math' as math;
import 'dart:ui' show SemanticsHitTestBehavior, SemanticsRole;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/scroll_through.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_scope.dart';
import 'package:family_groceries/log/trip_repository.dart';
import 'package:family_groceries/trip/trip_repository.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// From this width the tabs become a rail and More shows two panes.
const wideLayout = 840.0;

/// The widest a settings page's list runs (store layout, categories, Läden):
/// on a wide window it stays a readable column (job 56 item 26).
const pageMaxWidth = 640.0;

/// Whether the add sheet is open. The shell hides the tabs while it is;
/// the List tab opens and closes it. Leaving the tab closes it.
class const SheetOpen({
  required super.notifier,
  required super.child,
  super.key,
}) extends InheritedNotifier<SheetOpenNotifier> {
  static SheetOpenNotifier of(BuildContext context) => maybeOf(context)!;

  /// Null outside the shell (widget tests of a single tab).
  static SheetOpenNotifier? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetOpen>()?.notifier;
}

/// [SheetOpen]'s value, which a closing list can still reset after the
/// shell is gone.
class SheetOpenNotifier() extends ValueNotifier<bool> {
  this : super(false);

  var _disposed = false;

  /// Shows the tabs again, unless the shell went away meanwhile.
  void release() {
    if (!_disposed) {
      value = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The tabs in the order they show, for the bottom pill and the rail
/// alike, each with its shell [branch] (`appRoutes`).
enum _Destination(
  final int branch,
  final Key key,
  final IconData icon,
  final IconData selectedIcon,
) {
  list(
    0,
    ValueKey('tab-list'),
    Icons.shopping_cart_outlined,
    Icons.shopping_cart,
  ),

  /// Only while the flag `grocery-log` is on (job 199).
  history(2, ValueKey('tab-history'), Icons.history, Icons.history),
  more(1, ValueKey('tab-more'), Icons.menu, Icons.menu);

  String label(AppLocalizations l10n) => switch (this) {
    list => l10n.tabList,
    history => l10n.tabHistory,
    more => l10n.tabMore,
  };

  /// The tabs shown; no flags above (a test's shell) shows none behind one.
  static List<_Destination> shown(BuildContext context) {
    final history = context.select<Flags?, bool>(
      (flags) => flags?.isOn(groceryLogFlag) ?? false,
    );
    return [
      for (final d in values)
        if (d != _Destination.history || history) d,
    ];
  }
}

/// What the phone layout's bottom band shows. With the keyboard up there is
/// no band at all.
enum _Band() {
  /// The floating tab pill.
  tabs,

  /// The add sheet is open: the pill gives way to how adding works.
  hint,
}

/// The tab pill's height, the add field's.
const _pillHeight = 52.0;

/// The pill's narrowest width; it grows with large text.
const _pillMinWidth = 236.0;

/// The band's height: the pill and the gap below it, which keeps the pill
/// clear of the home indicator or gesture bar without the whole safe area
/// (iPhone 34 -> 26, Android 24 -> 16, none -> 12). The view padding stays
/// put while the keyboard comes up, so the band never changes height.
double _bandHeight(BuildContext context) =>
    _pillHeight +
    math.max(HlSpace.s3, MediaQuery.viewPaddingOf(context).bottom - HlSpace.s2);

/// The signed-in app: the List and More tabs, as a floating pill on phones
/// and a rail from [wideLayout] on.
class const AppShell({
  required final StatefulNavigationShell shell,
  super.key,

  /// Overrides the Supabase list repository per household, for tests.
  final ListRepository Function(String householdId)? repositories,

  /// Overrides the Supabase trips per household, for tests.
  final TripRepository Function(String householdId)? trips,

  /// Overrides the Supabase trip-mode trips per household, for tests.
  final TripSessionRepository Function(String householdId)? tripSessions,
}) extends StatefulWidget {
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState() extends State<AppShell> {
  final _sheetOpen = SheetOpenNotifier();

  /// The page under the tab band, which takes the wheel over the band.
  final _page = GlobalKey(debugLabel: 'shell-page');

  @override
  void dispose() {
    _sheetOpen.dispose();
    super.dispose();
  }

  void _select(_Destination destination) {
    _sheetOpen.value = false;
    final branch = destination.branch;
    // Tapping the current tab again goes back to its first page.
    widget.shell.goBranch(
      branch,
      initialLocation: branch == widget.shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final branch = widget.shell.currentIndex;
    final shown = _Destination.shown(context);
    if (!shown.any((d) => d.branch == branch)) {
      // The flag behind the current tab went off: the list takes over.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.shell.currentIndex == branch) {
          widget.shell.goBranch(_Destination.list.branch);
        }
      });
    }
    return ListScope(
      repositories: widget.repositories,
      trips: widget.trips,
      tripSessions: widget.tripSessions,
      child: SheetOpen(
        notifier: _sheetOpen,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= wideLayout) {
              return Scaffold(
                body: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: switch (shown.indexWhere(
                        (d) => d.branch == branch,
                      )) {
                        -1 => null,
                        final i => i,
                      },
                      onDestinationSelected: (i) => _select(shown[i]),
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerLow,
                      destinations: [
                        for (final destination in shown)
                          NavigationRailDestination(
                            icon: Icon(destination.icon, key: destination.key),
                            selectedIcon: Icon(destination.selectedIcon),
                            label: Text(destination.label(l10n)),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: widget.shell),
                  ],
                ),
              );
            }
            // Once the keyboard rises past the band, the band goes: no page
            // gets an inset for a band under the keyboard. Below that the
            // band stays, hidden, so the field above it never jumps.
            final keyboard =
                MediaQuery.viewInsetsOf(context).bottom > _bandHeight(context);
            final band = keyboard
                ? null
                : SheetOpen.of(context).value
                ? _Band.hint
                : _Band.tabs;
            return Scaffold(
              // Every page runs on behind the pill; the band's height
              // reaches it as the bottom padding.
              extendBody: true,
              // A page's floating button keeps off the view padding, which
              // the Scaffold leaves at the system's: it covers the band too.
              body: Builder(
                builder: (context) {
                  final media = MediaQuery.of(context);
                  return MediaQuery(
                    key: _page,
                    data: media.copyWith(
                      viewPadding: media.viewPadding.copyWith(
                        bottom: math.max(
                          media.viewPadding.bottom,
                          media.padding.bottom,
                        ),
                      ),
                    ),
                    child: widget.shell,
                  );
                },
              ),
              bottomNavigationBar: band == null
                  ? null
                  : ScrollThrough(
                      under: _page,
                      child: _TabBand(
                        band: band,
                        shown: shown,
                        branch: branch,
                        onSelect: _select,
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// The bottom band: "Liste" and "Mehr" in a hex pill that floats over the
/// page. While the add sheet is open the pill slides away and the band, now
/// the sheet's surface, shows how adding works; it keeps its height, so the
/// input above it stays put.
class const _TabBand({
  required final _Band band,
  required final List<_Destination> shown,
  required final int branch,
  required final ValueChanged<_Destination> onSelect,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final open = band == _Band.hint;
    final short = hlMotion(context, HlDuration.short);
    final hint = DefaultTextStyle.of(context).style
        .merge(TextStyle(fontSize: 13, color: scheme.onSurfaceVariant));
    final height = _bandHeight(context);
    // On the web the rows under the band keep their tappable semantics
    // elements, which take a browser click before the framework sees it;
    // the opaque node blocks them, the tabs still get theirs.
    return Semantics(
      container: true,
      hitTestBehavior: SemanticsHitTestBehavior.opaque,
      // The whole band takes taps: a near miss beside the pill must not act
      // on a row under it (DECISIONS, Job 135 item 5).
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          height: open ? _openHeight(context, hint, height) : height,
          duration: short,
          curve: HlEasing.standard,
          color: open ? t.surfaceRaised : t.surfaceRaised.withValues(alpha: 0),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: open ? 1 : 0,
                  duration: short,
                  curve: Interval(open ? 0.4 : 0, 1),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      HlSpace.s5,
                      HlSpace.s4,
                      HlSpace.s5,
                      0,
                    ),
                    child: Text(
                      l10n.addSheetHint,
                      key: const ValueKey('add-sheet-hint'),
                      textAlign: TextAlign.center,
                      style: hint,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: HlSpace.s4,
                right: HlSpace.s4,
                height: _pillHeight,
                child: IgnorePointer(
                  ignoring: open,
                  child: ExcludeFocus(
                    excluding: open,
                    child: ExcludeSemantics(
                      excluding: open,
                      child: AnimatedSlide(
                        offset: Offset(0, open ? 1 : 0),
                        duration: hlMotion(context, HlDuration.medium),
                        curve: open ? HlEasing.exit : HlEasing.standard,
                        child: AnimatedOpacity(
                          opacity: open ? 0 : 1,
                          duration: short,
                          child: Center(
                            child: _Pill(
                              shown: shown,
                              branch: branch,
                              onSelect: onSelect,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The open band's height: the closed [height], or more where the hint
/// wraps further (large text on a small phone), so it ends a closed band's
/// gap above the bottom edge.
double _openHeight(BuildContext context, TextStyle hint, double height) {
  final painter = TextPainter(
    text: TextSpan(
      text: AppLocalizations.of(context).addSheetHint,
      style: hint,
    ),
    textAlign: TextAlign.center,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: MediaQuery.sizeOf(context).width - 2 * HlSpace.s5);
  final text = painter.height;
  painter.dispose();
  return math.max(height, HlSpace.s4 + text + height - _pillHeight);
}

/// The raised hex capsule with the tabs, as wide as its widest tab needs
/// (twice over) and at least [_pillMinWidth]. Semantics as Material's
/// NavigationBar has them, so screen readers and the web e2e find a tab bar.
class const _Pill({
  required final List<_Destination> shown,
  required final int branch,
  required final ValueChanged<_Destination> onSelect,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final t = SnacklistColors.of(brightness);
    final declutter = context.select<Flags?, bool>(
      (flags) => flags?.isOn(listDeclutterFlag) ?? false,
    );
    return MediaQuery.withClampedTextScaling(
      // Large text still fits the 44 high indicator.
      maxScaleFactor: 1.5,
      child: LayoutBuilder(
        builder: (context, constraints) => _face(
          context,
          t,
          brightness,
          constraints.maxWidth,
          declutter: declutter,
        ),
      ),
    );
  }

  /// Each shown tab's width with its label, with [chrome] beside it.
  List<double> _labelled(BuildContext context, double chrome) {
    final l10n = AppLocalizations.of(context);
    // As the pill's Material sets it for the tabs.
    final style = Theme.of(context).textTheme.bodyMedium!
        .merge(_Tab.labelStyle);
    double widthOf(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width + chrome;
    }

    return [for (final d in shown) widthOf(d.label(l10n))];
  }

  Widget _face(
    BuildContext context,
    SnacklistColors t,
    Brightness brightness,
    double maxWidth, {
    required bool declutter,
  }) {
    // Equal shares while the widest label fits each; then shares as wide
    // as each label (three tabs on a small phone); and when not even that
    // fits (large text), the other tabs keep their icon only and their name
    // for screen readers, the selected one the room for its label.
    final room = maxWidth - 2 * _pillInset;
    bool fits(List<double> widths) => widths.reduce((a, b) => a + b) <= room;
    var widths = _labelled(context, _Tab.chrome);
    // Decluttered (job 229), a pill about to drop labels first narrows its
    // tabs' hexes: three labels stay at 130 % text on a 358 px phone.
    final tight =
        !fits(widths) &&
        declutter &&
        fits(_labelled(context, _Tab.tightChrome));
    if (tight) {
      widths = _labelled(context, _Tab.tightChrome);
    }
    final equal = widths.length * widths.reduce(math.max) <= room;
    final crowded = !fits(widths);
    final row = SizedBox(
      height: _pillHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, destination) in shown.indexed)
            if (crowded && destination.branch != branch)
              SizedBox(
                width: _Tab.iconOnlyWidth,
                child: _tab(destination, i, label: false),
              )
            else
              Expanded(
                flex: equal || crowded ? 1 : widths[i].ceil(),
                child: _tab(destination, i, label: true, tight: tight),
              ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const HexBorder(),
        shadows: HlSticker.shadow(brightness, StickerDepth.s),
      ),
      child: Material(
        color: t.surfaceRaised,
        shape: HexBorder(
          side: BorderSide(color: t.border, width: HlBorder.width),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          role: SemanticsRole.tabBar,
          explicitChildNodes: true,
          container: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _pillMinWidth),
            child: Padding(
              // The face's inset inside the contour.
              padding: const EdgeInsets.symmetric(horizontal: _pillInset),
              child: equal
                  ? IntrinsicWidth(child: row)
                  : SizedBox(width: room, child: row),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(
    _Destination destination,
    int position, {
    required bool label,
    bool tight = false,
  }) => _Tab(
    destination: destination,
    position: position,
    count: shown.length,
    selected: destination.branch == branch,
    label: label,
    tight: tight,
    onTap: () => onSelect(destination),
  );
}

/// The face's inset inside the pill's contour.
const _pillInset = HlSpace.s3 + HlBorder.width;

/// One tab: its whole share of the pill takes the tap; the selected one
/// sits on the honey hex.
class const _Tab({
  required final _Destination destination,

  /// Its place among the [count] tabs shown, from 0.
  required final int position,
  required final int count,
  required final bool selected,
  required final VoidCallback onTap,

  /// False in a crowded pill: the icon alone, the name for screen readers.
  final bool label = true,

  /// The indicator's narrower insets ([tightChrome]).
  final bool tight = false,
}) extends StatefulWidget {
  static const _indicatorHeight = 44.0;

  static const labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  /// A labelled tab's width beside its label: the indicator's insets, the
  /// selected hex's contour, the icon and the gap.
  static const chrome = 11.0 + 14 + 2 * 1.5 + 20 + 6;

  /// [chrome] with the indicator's insets of a [tight] tab.
  static const tightChrome = 8.0 + 10 + 2 * 1.5 + 20 + 6;

  /// An unlabelled tab's share of a crowded pill.
  static const iconOnlyWidth = 56.0;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState() extends State<_Tab> {
  var _focused = false;

  // Hover and press show on the hex, never on the tab's whole share.
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final _Tab(
      :destination,
      :position,
      :count,
      :selected,
      :onTap,
      :label,
      :tight,
    ) = widget;
    final color = selected ? t.onHoney : t.text;
    final indicator = Container(
      height: _Tab._indicatorHeight,
      padding: tight
          ? const EdgeInsetsDirectional.only(start: 8, end: 10)
          : const EdgeInsetsDirectional.only(start: 11, end: 14),
      decoration: ShapeDecoration(
        color: selected
            ? t.honey
            : _hovered || _pressed
            ? t.surfaceSunken
            : null,
        shape: HexBorder(
          side: selected
              ? BorderSide(color: t.border, width: 1.5)
              : BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(
            selected ? destination.selectedIcon : destination.icon,
            size: 20,
            color: color,
          ),
          if (label)
            Flexible(
              child: Text(
                destination.label(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _Tab.labelStyle.copyWith(color: color),
              ),
            ),
        ],
      ),
    );
    return MergeSemantics(
      child: Semantics(
        role: SemanticsRole.tab,
        selected: selected,
        button: true,
        label: label ? null : destination.label(l10n),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InkWell(
              key: destination.key,
              onTap: onTap,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              onHover: (hovered) => setState(() => _hovered = hovered),
              onHighlightChanged: (pressed) =>
                  setState(() => _pressed = pressed),
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: Center(
                child: CustomPaint(
                  foregroundPainter: _focused ? _Ring(t.accent) : null,
                  child: indicator,
                ),
              ),
            ),
            // As NavigationBar: "Tab 1 von 2" after the label, except on
            // the web, where the tab role says it.
            if (!kIsWeb)
              Semantics(
                label: MaterialLocalizations.of(context)
                    .tabLabel(tabIndex: position + 1, tabCount: count),
              ),
          ],
        ),
      ),
    );
  }
}

/// The focus ring round a tab's hex, [HlFocus.ringGap] off it.
class const _Ring(final Color color) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      const HexBorder().pathFor(
        Offset.zero & size,
        outset: HlFocus.ringGap + HlFocus.ringWidth / 2,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = HlFocus.ringWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_Ring oldDelegate) => oldDelegate.color != color;
}
