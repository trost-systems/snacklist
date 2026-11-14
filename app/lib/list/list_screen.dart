import 'dart:async';
import 'dart:math' show max;
import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/scroll_through.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/design/bottom_scroll_edge.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/measured_width.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/home_widget/widget_launch.dart';
import 'package:family_groceries/household/household_switcher.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/dictation.dart';
import 'package:family_groceries/list/dictation_button.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/list/list_scope.dart';
import 'package:family_groceries/list/list_switcher_button.dart';
import 'package:family_groceries/list/list_tabs.dart';
import 'package:family_groceries/list/list_view/price_views.dart';
import 'package:family_groceries/list/list_view/shopping_list_view.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/sync_indicator.dart';
import 'package:family_groceries/log/trip_prompts.dart';
import 'package:family_groceries/review/review_prompt_trigger.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/tips/hint_views.dart';
import 'package:family_groceries/trip/trip_on_list.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The List tab: a status bar on top, the list, and the add bar at the
/// bottom, which opens the add sheet. Needs the list scope
/// (`ListScope`) above it.
class const ListScreen({super.key}) extends StatelessWidget {
  /// The add bar's recognizer, null for none. The Linux capture entrypoint
  /// (`test_driver/main_marionette.dart`) sets a scripted one first.
  @visibleForTesting
  static Dictation? dictation = dictationFor(
    defaultTargetPlatform,
    web: kIsWeb,
  );

  /// Only iOS and Android recognize speech on the device; elsewhere typing
  /// is the way in.
  @visibleForTesting
  static Dictation? dictationFor(
    TargetPlatform platform, {
    required bool web,
  }) =>
      !web &&
          (platform == TargetPlatform.iOS || platform == TargetPlatform.android)
      ? DeviceDictation()
      : null;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    if (session is! InHousehold) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ShoppingList(dictation: dictation);
  }
}

/// The tab's content; needs a [ListCubit] above it.
class const ShoppingList({
  /// Null hides the microphone button.
  final Dictation? dictation,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Another household brings another ListCubit while the tabs stay
    // (joining or restoring one from More): the sheet and the screen start
    // over with it, or adds would go to the household that was left.
    final list = context.select<ListCubit, ListCubit>((cubit) => cubit);
    return MultiBlocProvider(
      key: ObjectKey(list),
      providers: [
        BlocProvider(create: (_) => AddSheetCubit(list)),
        BlocProvider(create: (_) => TripPrompts(list)),
      ],
      child: ProvideHints(
        list: list,
        // The list's snackbars float above the add bar, not above the tabs.
        child: ScaffoldMessenger(
          // Job 234: the question after a tick, the summary after Beenden.
          child: TripOnList(child: _ShoppingList(dictation: dictation)),
        ),
      ),
    );
  }
}

class const _ShoppingList({required final Dictation? dictation})
    extends StatefulWidget {
  @override
  State<_ShoppingList> createState() => _ShoppingListState();
}

class _ShoppingListState() extends State<_ShoppingList> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  /// The field's own scrolling, which follows dictated words: unfocused it
  /// would keep showing the sentence's start.
  final _inputScroll = ScrollController();

  /// The page under the add bar, which takes the wheel over the bar.
  final _page = GlobalKey(debugLabel: 'list-page');

  /// The item whose price editor is open (job 190): the add bar steps
  /// aside for it, so the editor and the total fit above the keyboard.
  final _pricing = ValueNotifier<String?>(null);

  /// The household chip's and Anpassen's widths in the top bar, once laid
  /// out: the sync pill sits right of the chip, the chip leaves Anpassen
  /// its room.
  final _chipWidth = ValueNotifier<double>(0);
  final _anpassenWidth = ValueNotifier<double>(0);

  /// The bar's room for the partner's new adds, null until laid out:
  /// narrower than their line, it shows below the household chip instead.
  final _statusRoom = ValueNotifier<double?>(null);

  /// The add bar around the input: it holds focus between a tap in the
  /// sheet and the input's refocus, and after a close, and takes Escape
  /// there (job 64). An Escape right after a tap on a row closed nothing,
  /// and a focused row going with the closing sheet sent focus back to the
  /// input, which opened it again.
  final _barFocus = FocusNode();
  RejectionNotices? _notices;
  SheetOpenNotifier? _sheetOpen;
  AddSheetRequest? _addSheetRequest;
  ListLinks? _links;
  StreamSubscription<DedupeHint>? _hints;
  StreamSubscription<Merge>? _renameMerges;

  /// The duplicate hint on screen, until it closes.
  (DedupeHint, ScaffoldFeatureController<SnackBar, SnackBarClosedReason>)?
  _openHint;
  var _listening = false;

  /// Set once the user's close has settled: the field's next focus is the
  /// user coming back to type, and opens the sheet. On the web a click can
  /// reach the field as a semantics tap or focus, which never calls
  /// `TextField.onTap`. Not set by a tap on the list: after one, the field
  /// can get focus back without a tap (fg sync's sign-in, job 52).
  var _openOnFocus = false;

  /// Phones get the keyboard only when asked; with a hardware keyboard
  /// the field is ready for typing at once.
  static final _autofocus =
      defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _notices = context.read<RejectionNotices?>()?..listTab = _rejected;
    _hints = context.read<ListCubit>().hints.listen(_hint);
    _renameMerges = context.read<ListCubit>().renameMerges.listen(_showMerged);
    _inputFocus.addListener(_focusChanged);
    _input.addListener(_followWords);
    _addSheetRequest = context.read<AddSheetRequest?>()
      ?..listTab = _openRequested;
    // A widget's Add that started the app came before this tab.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequested());
    _links = context.read<ListLinks?>()?..changes.addListener(_linked);
    // A cold start's `/add` came before this list was built.
    _linked();
  }

  /// A Home Screen widget's Add: the sheet opens, ready for typing.
  void _openRequested() {
    if (mounted && (_addSheetRequest?.take() ?? false)) {
      context.read<AddSheetCubit>().show();
      _inputFocus.requestFocus();
    }
  }

  /// An `/add` link opens the sheet with the field focused. After the
  /// frame: the router asks during its own work, the tab may still be
  /// switching to the list.
  void _linked() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _links?.take<AddLink>() != null) {
        _openOnFocus = false;
        context.read<AddSheetCubit>().show();
        _inputFocus.requestFocus();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Keeps the latest dictated words in view while the user speaks.
  void _followWords() {
    if (!_listening) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inputScroll.hasClients) {
        _inputScroll.jumpTo(_inputScroll.position.maxScrollExtent);
      }
    });
  }

  void _focusChanged() {
    if (_inputFocus.hasFocus && _openOnFocus) {
      _openOnFocus = false;
      context.read<AddSheetCubit>().show();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = SheetOpen.maybeOf(context);
    if (notifier != _sheetOpen) {
      _sheetOpen?.removeListener(_followShell);
      _sheetOpen = notifier?..addListener(_followShell);
    }
  }

  /// The shell closes the sheet when the user leaves the tab.
  void _followShell() {
    if (_sheetOpen?.value == false) {
      context.read<AddSheetCubit>().dismiss();
    }
  }

  @override
  void dispose() {
    _pricing.dispose();
    _chipWidth.dispose();
    _anpassenWidth.dispose();
    _statusRoom.dispose();
    _links?.changes.removeListener(_linked);
    _sheetOpen?.removeListener(_followShell);
    if (_addSheetRequest?.listTab == _openRequested) {
      _addSheetRequest?.listTab = null;
    }
    // The tabs come back, after this frame: the tree is locked now, and a
    // new household's list may already have taken the notifier over.
    if (_sheetOpen case final notifier? when notifier.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifier.release());
    }
    if (_notices?.listTab == _rejected) {
      _notices?.listTab = null;
    }
    unawaited(_hints?.cancel());
    unawaited(_renameMerges?.cancel());
    _refocus?.cancel();
    _input.dispose();
    _inputScroll.dispose();
    _inputFocus.dispose();
    _barFocus.dispose();
    super.dispose();
  }

  /// Job 32b: "Möhren steht schon auf der Liste" with Zusammenführen, after
  /// "Karotten" went on the list anyway. While the add sheet is open it is
  /// part of the sheet's note (a snackbar would cover the sheet); otherwise,
  /// and once the sheet closes, a snackbar. That queues behind one already
  /// showing (a dictation summary) instead of cutting it short. Every hint
  /// shown ends merged or ignored, once; [counted] when the sheet showed it
  /// already.
  void _hint(DedupeHint hint, {bool counted = false}) {
    if (!mounted) {
      return;
    }
    if (!counted && context.read<AddSheetCubit>().offer(hint)) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    if (!counted) {
      cubit.hintShown();
    }
    var merged = false;
    final shown = Notices.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('dedupe-hint'),
        content: Text(l10n.alreadyOnList(hint.onList.name)),
        persist: false,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          key: const ValueKey('dedupe-merge'),
          label: l10n.dedupeMerge,
          onPressed: () {
            merged = true;
            // Closing on its own now; `close` would hit the next snackbar.
            _openHint = null;
            if (mounted) {
              _showMerged(context.read<ListCubit>().merge(hint));
            }
          },
        ),
      ),
    );
    _openHint = (hint, shown);
    unawaited(
      shown.closed.then((_) {
        if (_openHint?.$2 == shown) {
          _openHint = null;
        }
        if (!merged) {
          cubit.hintIgnored();
        }
      }),
    );
  }

  /// Says what the open item holds after [merge] (Zusammenführen on a hint,
  /// or a rename onto it), with Rückgängig. The
  /// action closes the hint itself, after this: hiding it here too would,
  /// with animations off (screen readers, the web's semantics), close the
  /// new snackbar instead.
  void _showMerged(Merge? merge) {
    if (!mounted || merge == null) {
      return;
    }
    final cubit = context.read<ListCubit>();
    final result = merge.result;
    final l10n = AppLocalizations.of(context);
    Notices.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('dedupe-merged'),
        content: Text(
          l10n.dedupeMerged([?result.quantity, result.name].join(' ')),
        ),
        persist: false,
        action: SnackBarAction(
          key: const ValueKey('dedupe-undo'),
          label: l10n.undo,
          onPressed: () => cubit.unmerge(merge),
        ),
      ),
    );
  }

  /// A refused write, in the list's own messenger while the list is on
  /// screen; false sends it to the app's (More, screens opened on top).
  bool _rejected(String text) {
    if (!mounted ||
        !TickerMode.valuesOf(context).enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    _snack(text);
    return true;
  }

  void _snack(String text) => Notices.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), persist: false));

  void _close() {
    _refocus?.cancel();
    context.read<AddSheetCubit>().dismiss();
    _barFocus.requestFocus();
    unawaited(_settleClose());
  }

  /// The web engine defers a semantics focus raised during a frame to a
  /// `Timer.run` after that frame, so a refocus just before a close can
  /// reach the framework after it. A zero-delay timer started after the next
  /// frame runs after that one.
  Future<void> _settleClose() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    if (!mounted || context.read<AddSheetCubit>().state.open) {
      return;
    }
    if (_inputFocus.hasFocus) {
      _barFocus.requestFocus();
    }
    _openOnFocus = true;
  }

  void _take(Suggestion suggestion) {
    _afterAdd(context.read<AddSheetCubit>().take(suggestion));
    _refocusAfterTap();
  }

  Future<void> _submit() async {
    _afterAdd(await context.read<AddSheetCubit>().takeFirst());
  }

  void _afterAdd(AddResult? result) {
    if (!mounted || result == null || result is NothingToAdd) {
      return;
    }
    _input.clear();
    _inputFocus.requestFocus();
  }

  /// On web a tap outside the field blurs its DOM input while Flutter keeps
  /// the field focused, so requestFocus does nothing. A fresh focus gives the
  /// input back; it waits for the engine's deferred blur of the closed
  /// connection (a zero-delay timer) to run first, or that blur wins.
  void _refocusAfterTap() {
    if (!kIsWeb) {
      _inputFocus.requestFocus();
      return;
    }
    _barFocus.requestFocus();
    _refocus?.cancel();
    _refocus = Timer(const Duration(milliseconds: 50), () {
      if (mounted) {
        _inputFocus.requestFocus();
      }
    });
  }

  Timer? _refocus;

  /// Acting on the list ends typing, which also drops the soft keyboard
  /// while ticking things off in the store. A tick commits 440 ms after
  /// the tap; by then the user may have opened the sheet to type, and the
  /// late call must not take the field away.
  void _leaveField() {
    if (!context.read<AddSheetCubit>().state.open) {
      _inputFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = context.select<AddSheetCubit, bool>((c) => c.state.open);
    final declutter = context.select<Flags?, bool>(
      (flags) => flags?.isOn(listDeclutterFlag) ?? false,
    );
    // Decluttered, the lists are switched in the switcher's sheet.
    final tabs =
        !declutter &&
        context.select<ListCubit, bool>(
          (c) => ListTabs.shownFor(c.state.catalog.lists),
        );
    final prices = context.select<Flags?, bool>(
      (flags) => flags?.isOn(pricesFlag) ?? false,
    );
    final hasItems = context.select<ListCubit, bool>(
      (c) => c.state.items.isNotEmpty,
    );
    return ReviewPromptTrigger(
      cubit: context.read<ListCubit>(),
      listening: _listening,
      child: MultiBlocListener(
        listeners: [
          // A hint whose items are no longer both open (the add undone, a
          // partner ticked one) has nothing left to merge: it goes.
          BlocListener<ListCubit, ListState>(
            listenWhen: (a, b) =>
                !identical(a.server, b.server) ||
                !identical(a.pending, b.pending),
            listener: (context, list) {
              final items = list.items;
              bool stale(DedupeHint hint) => [
                hint.added,
                hint.onList,
              ].any((i) => items[i.id]?.status != ItemStatus.active);
              if (_openHint case (final hint, final bar) when stale(hint)) {
                bar.close();
              }
              final sheet = context.read<AddSheetCubit>();
              if (sheet.state.hint case final hint? when stale(hint)) {
                sheet.drop(hint);
              }
            },
          ),
          BlocListener<AddSheetCubit, AddSheetState>(
            listenWhen: (a, b) => a.open != b.open,
            listener: (_, sheet) => _sheetOpen?.value = sheet.open,
          ),
          // A hint or merge in the closing sheet's note goes on as a snackbar.
          BlocListener<AddSheetCubit, AddSheetState>(
            listenWhen: (a, b) => a.open && !b.open,
            listener: (context, _) {
              final (hint, merge) = context.read<AddSheetCubit>().handOver();
              if (merge != null) {
                _showMerged(merge);
              } else if (hint != null) {
                _hint(hint, counted: true);
              }
            },
          ),
          // A sheet that starts over (closed, or opened again) clears the
          // input too.
          BlocListener<AddSheetCubit, AddSheetState>(
            listenWhen: (a, b) => b.text.isEmpty && a.text.isNotEmpty,
            listener: (_, _) {
              if (_input.text.isNotEmpty) {
                _input.clear();
              }
            },
          ),
        ],
        // Tab goes input, suggestions, chips, Schließen, then the bar's
        // buttons (DECISIONS, Job 17).
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Scaffold(
            // The shell's scaffold makes room for the keyboard.
            resizeToAvoidBottomInset: false,
            // The list scrolls on under the floating add field (job 135).
            extendBody: true,
            body: Stack(
              key: _page,
              children: [
                ExcludeFocus(
                  excluding: open,
                  child: ExcludeSemantics(
                    excluding: open,
                    child: SyncIndicator(
                      rowTop: _Header._gap,
                      rowHeight: _Header.height,
                      cardTop: _Header.extentFor(tabs: tabs),
                      pillInset: _chipWidth,
                      // A screen reader reads the new adds below the chip
                      // before the list, not after its last row: one node, so
                      // the sync shell beside it doesn't split their order.
                      child: Semantics(
                        container: true,
                        explicitChildNodes: true,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Semantics(
                              sortKey: const OrdinalSortKey(1),
                              child: BottomScrollEdge(
                                child: ShoppingListView(
                                  onInteract: _leaveField,
                                  pricing: _pricing,
                                  header: _Header(
                                    chipWidth: _chipWidth,
                                    anpassenWidth: _anpassenWidth,
                                    statusRoom: _statusRoom,
                                    tabs: tabs,
                                    declutter: declutter,
                                  ),
                                ),
                              ),
                            ),
                            _StatusBelow(
                              room: _statusRoom,
                              anpassenWidth: _anpassenWidth,
                              tabs: tabs,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: TextFieldTapRegion(
                    // Escape from a row or chip of the sheet; never focused
                    // itself, and no semantics node: on the web one this
                    // size would take every tap on the list.
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      includeSemantics: false,
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent ||
                            event.logicalKey != LogicalKeyboardKey.escape ||
                            !open) {
                          return KeyEventResult.ignored;
                        }
                        _close();
                        return KeyEventResult.handled;
                      },
                      child: AddSheet(
                        onTake: _take,
                        onClose: _close,
                        onPicked: _refocusAfterTap,
                      ),
                    ),
                  ),
                ),
                // Above the add bar, which the body extends under.
                PositionedDirectional(
                  start: HlSpace.s3,
                  end: HlSpace.s3,
                  bottom: MediaQuery.paddingOf(context).bottom + HlSpace.s2,
                  child: Align(
                    alignment: AlignmentDirectional.bottomEnd,
                    child: AddBarHint(hidden: open),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: ValueListenableBuilder(
              valueListenable: _pricing,
              builder: (context, pricing, addBar) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Job 234: the running trip, above the total and the
                  // field; away while typing or pricing.
                  TripStripSlot(hidden: open || pricing != null),
                  // Decluttered, the total is a row of the list.
                  if (prices && hasItems && !declutter)
                    // In the add bar's place, it keeps clear of the shell's
                    // tab pill as the add bar does.
                    SafeArea(
                      top: false,
                      bottom: pricing != null,
                      child: const TotalBar(),
                    ),
                  Visibility(
                    visible: pricing == null,
                    maintainState: true,
                    child: addBar!,
                  ),
                ],
              ),
              child: ScrollThrough(
                under: _page,
                child: TextFieldTapRegion(
                  child: _AddBar(
                    input: _input,
                    inputScroll: _inputScroll,
                    focus: _inputFocus,
                    barFocus: _barFocus,
                    autofocus: _autofocus,
                    listening: _listening,
                    onSubmit: () => unawaited(_submit()),
                    onClose: _close,
                    onLeave: _leaveField,
                    onRefocus: _refocusAfterTap,
                    dictation: switch (widget.dictation) {
                      final dictation? => DictationButton(
                        dictation: dictation,
                        input: _input,
                        onMessage: _snack,
                        onListening: (listening) =>
                            setState(() => _listening = listening),
                        // The dictated text waits in the field; a tap opens it.
                        onDone: () {
                          _openOnFocus = false;
                          _inputFocus.requestFocus();
                        },
                      ),
                      null => null,
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The input, in the thumb zone: the field, clear while the sheet is open,
/// and the microphone, in one hex that is a tap target as a whole (Peter,
/// job 78). It never moves while the sheet opens, grows or closes.
class const _AddBar({
  required final TextEditingController input,
  required final ScrollController inputScroll,
  required final FocusNode focus,

  /// The bar's own node around the field, which takes Enter and Escape.
  required final FocusNode barFocus,
  required final bool autofocus,
  required final bool listening,
  required final VoidCallback onSubmit,
  required final VoidCallback onClose,
  required final VoidCallback onLeave,

  /// Focuses the field after a tap beside its input, which on the web blurs
  /// the input while Flutter keeps the field focused.
  required final VoidCallback onRefocus,
  required final Widget? dictation,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.read<AddSheetCubit>();
    final sheet = context.watch<AddSheetCubit>().state;
    final list = context.watch<ListCubit>();
    final open = sheet.open;
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final hint = listening ? l10n.dictationListening : l10n.addFieldHint;
    void show() {
      cubit.show();
      // Text the microphone left behind.
      if (input.text.isNotEmpty) {
        cubit.type(input.text);
      }
    }

    // The hex is the container's, never the field's: an InputBorder on the
    // field changes its padding when focused (DECISIONS, Job 52 item 7).
    final compose = Container(
      height: _composeHeight,
      // The text starts clear of the tip; the buttons' own padding keeps
      // their icons clear of the other one.
      padding: const EdgeInsetsDirectional.only(
        start: HlHex.tip * _composeHeight + HlSpace.s1,
        end: HlHex.tip * _composeHeight - HlSpace.s1,
      ),
      decoration: ShapeDecoration(
        color: t.surfaceRaised,
        shape: HexBorder(
          side: BorderSide(color: t.border, width: HlBorder.width),
        ),
        // Lifted off the list that scrolls under it, like a sticker.
        shadows: HlSticker.shadow(Theme.of(context).brightness, StickerDepth.s),
      ),
      child: Row(
        spacing: HlSpace.s2,
        children: [
          Expanded(
            child: Focus(
              focusNode: barFocus,
              // Enter is handled here on web and desktop, also a
              // web soft keyboard's, because Flutter web's
              // text-input action path blurs the field and leaves
              // it dead for the next Enter. Native soft keyboards
              // still submit below.
              onKeyEvent: (_, event) {
                final key = event.logicalKey;
                final enter =
                    key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.numpadEnter;
                if (event is KeyUpEvent) {
                  return KeyEventResult.ignored;
                }
                if (key == LogicalKeyboardKey.escape && open) {
                  onClose();
                  return KeyEventResult.handled;
                }
                if (!enter) {
                  return KeyEventResult.ignored;
                }
                if (event is KeyDownEvent) {
                  onSubmit();
                }
                return KeyEventResult.handled;
              },
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                // The bar around it draws the hex; the app's field theme
                // must not reach this field (DECISIONS job 52, item 7).
                child: InputDecorationTheme(
                  data: const InputDecorationThemeData(),
                  child: HintNamed(
                    controller: input,
                    hint: hint,
                    field: TextField(
                      autofillHints: null,
                      key: const ValueKey('add-item-field'),
                      controller: input,
                      scrollController: inputScroll,
                      focusNode: focus,
                      autofocus: autofocus,
                      // Focus comes back after every tap in the
                      // sheet; typing goes on where it was.
                      selectAllOnFocus: false,
                      // The server caps names at 120 characters.
                      maxLength: 120,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(fontSize: 18, color: scheme.onSurface),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(
                          fontSize: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        border: InputBorder.none,
                        counterText: '',
                      ),
                      onTap: show,
                      onChanged: cubit.type,
                      // Keeps the soft keyboard up after submitting.
                      onEditingComplete: () {},
                      // On web every Enter, soft keyboards' too, reaches
                      // the key handler above first. An onSubmitted here
                      // would also make EditableText restart the input
                      // connection, whose deferred engine blur can land
                      // after the refocus: Firefox lost the field (job 210).
                      onSubmitted: kIsWeb ? null : (_) => onSubmit(),
                      onTapOutside: (_) {
                        if (!open) {
                          onLeave();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (open && sheet.text.isNotEmpty)
            FocusTraversalOrder(
              order: const NumericFocusOrder(5),
              child: IconButton(
                key: const ValueKey('add-clear'),
                tooltip: l10n.clearInput,
                icon: const Icon(Icons.close),
                onPressed: () {
                  input.clear();
                  cubit.type('');
                  focus.requestFocus();
                },
              ),
            ),
          if (dictation case final dictation?)
            FocusTraversalOrder(
              order: const NumericFocusOrder(6),
              child: dictation,
            ),
        ],
      ),
    );
    // In the list's first column, where the sheet opens. Closed, only the
    // hex is painted and the list shows around it; open, the bar carries on
    // the sheet above it.
    return LayoutBuilder(
      builder: (context, constraints) {
        final frame = ShoppingListView.frameFor(
          constraints.maxWidth,
          list.state,
        );
        return Padding(
          padding: EdgeInsetsDirectional.only(start: frame.side),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            heightFactor: 1,
            child: AnimatedContainer(
              width: frame.columnWidth,
              duration: hlMotion(context, HlDuration.short),
              curve: HlEasing.standard,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: hlMotion(context, HlDuration.short),
                      curve: HlEasing.standard,
                      color: open
                          ? t.surfaceRaised
                          : t.surfaceRaised.withValues(alpha: 0),
                    ),
                  ),
                  // On the web the rows under the band keep their tappable
                  // semantics elements, which take a browser click before
                  // the framework sees it; the opaque node blocks them, its
                  // children (field, microphone, ✕) still get theirs.
                  Semantics(
                    container: true,
                    hitTestBehavior: SemanticsHitTestBehavior.opaque,
                    child: SafeArea(
                      top: false,
                      // A tap anywhere on the band counts as one on the
                      // field: a near miss beside the hex must not act on a
                      // row hidden under it. No semantics node of its own: on
                      // the web one this size would take the field's taps.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTap: () {
                          show();
                          onRefocus();
                        },
                        child: Container(
                          height: addBarHeight,
                          // The rows' own inset (item_row.dart).
                          padding: const EdgeInsets.symmetric(
                            horizontal: HlSpace.s4,
                          ),
                          alignment: Alignment.center,
                          child: compose,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The compose field's height: the site's `.compose`.
const _composeHeight = 52.0;

/// The bar above the list: the household chip (the switcher, job 169b),
/// how many partner adds are new, the sync state and Anpassen, which opens
/// the stores and categories; no count (Peter, DECISIONS Job 29a). It
/// floats over the list like the tab pill below (job 148), at the frame's
/// end, [height] tall in every state; the rows scroll on under it.
/// Anpassen is a raised button on its own, with no frame around it (job
/// 152); the new adds sit in their own small capsule beside it, only while
/// there are any. The sync indicator's
/// pill sits right of the household chip (job 161). With [tabs], the
/// household's lists follow below the bar (job 169b K). With [declutter]
/// (job 229) the [ListSwitcherButton] takes the chip's place, and the list
/// draws the bar and the status bar as one see-through layer.
class const _Header({
  required final ValueNotifier<double> chipWidth,
  required final ValueNotifier<double> anpassenWidth,
  required final ValueNotifier<double?> statusRoom,
  required final bool tabs,
  required final bool declutter,
}) extends StatelessWidget implements PreferredSizeWidget {
  /// The bar's height: the tab pill's.
  static const height = 52.0;

  /// Room above the bar, below the top safe area.
  static const _gap = HlSpace.s2;

  /// How far below the top safe area the list's first row starts: the
  /// bar, its shadow and a gap.
  static const extent = _gap + height + HlSpace.s2;

  /// [extent], with the list tabs and their gap when [tabs].
  static double extentFor({required bool tabs}) =>
      extent + (tabs ? ListTabs.height + HlSpace.s2 : 0);

  @override
  Size get preferredSize => Size.fromHeight(extentFor(tabs: tabs));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final state = context.watch<ListCubit>().state;
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      key: const ValueKey('list-header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The status bar keeps the page behind it, not passing rows; the
        // decluttered layer covers both.
        ColoredBox(
          color: declutter ? Colors.transparent : t.surface,
          child: SizedBox(height: top),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final side = ShoppingListView.frameFor(
              constraints.maxWidth,
              state,
            ).side;
            final row = constraints.maxWidth - 2 * (side + HlSpace.s4);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                side + HlSpace.s4,
                _gap,
                side + HlSpace.s4,
                extent - _gap - height,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: HlSpace.s2,
                children: [
                  _bar(context, l10n, state, row),
                  if (tabs)
                    MediaQuery.withClampedTextScaling(
                      // Large text still fits the 32 high tab hex.
                      maxScaleFactor: SyncPillSpace.maxTextScale,
                      child: const SizedBox(
                        height: ListTabs.height,
                        child: ListTabs(),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _bar(
    BuildContext context,
    AppLocalizations l10n,
    ListState state,
    double row,
  ) => SizedBox(
    height: height,
    child: MediaQuery.withClampedTextScaling(
      // Large text still fits the 52 high bar.
      maxScaleFactor: SyncPillSpace.maxTextScale,
      child: ListenableBuilder(
        listenable: Listenable.merge([chipWidth, anpassenWidth]),
        builder: (context, _) => Row(
          children: [
            if (declutter)
              ListSwitcherButton(
                maxWidth: HouseholdChip.widest(
                  row,
                  anpassen: anpassenWidth.value,
                  trouble: state.trouble != null,
                ),
                onWidth: (width) => chipWidth.value = width,
              )
            else
              HouseholdChip(
                maxWidth: HouseholdChip.widest(
                  row,
                  anpassen: anpassenWidth.value,
                  trouble: state.trouble != null,
                ),
                onWidth: (width) => chipWidth.value = width,
              ),
            SyncPillSpace(row: row - chipWidth.value),
            const SizedBox(width: HlSpace.s2),
            Expanded(
              child: MeasuredWidth(
                onWidth: (width) => statusRoom.value = width,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _Status(room: statusRoom),
                ),
              ),
            ),
            const SizedBox(width: HlSpace.s2),
            // On the web the rows under the button keep their
            // tappable semantics elements, which take a browser
            // click before the framework sees it; the opaque node
            // blocks them. Rows beside it stay tappable: they show
            // in full.
            Semantics(
              container: true,
              hitTestBehavior: SemanticsHitTestBehavior.opaque,
              // Large text shrinks the label rather than the bar.
              child: MeasuredWidth(
                onWidth: (width) => anpassenWidth.value = width,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: OutlinedButton(
                    key: const ValueKey('list-edit'),
                    // Desktop's compact density would shrink it
                    // under 48 px.
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.standard,
                    ),
                    onPressed: () => context.go(editPath),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l10n.listEdit),
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

/// The partner's new adds below the household chip, where the bar has no
/// room for their whole line (a phone): floating over the list like the
/// sync card, at the same place.
class const _StatusBelow({
  required final ValueListenable<double?> room,
  required final ValueListenable<double> anpassenWidth,
  required final bool tabs,
}) extends StatelessWidget {
  /// Anpassen at its widest, until it is measured.
  static const _anpassen = 160.0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ListCubit>().state;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset =
            ShoppingListView.frameFor(constraints.maxWidth, state).side +
            HlSpace.s4;
        return Stack(
          children: [
            PositionedDirectional(
              start: inset,
              top:
                  MediaQuery.paddingOf(context).top +
                  _Header.extentFor(tabs: tabs),
              // Clear of the column under Anpassen, where a store divider
              // has its count and fold key: a long name ellipsizes.
              child: ValueListenableBuilder(
                valueListenable: anpassenWidth,
                builder: (context, anpassen, child) => ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: max(
                      0,
                      constraints.maxWidth -
                          2 * inset -
                          (anpassen > 0 ? anpassen : _anpassen) -
                          HlSpace.s4,
                    ),
                  ),
                  child: child,
                ),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: SyncPillSpace.maxTextScale,
                  child: _Status(room: room, below: true),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The partner's new adds in a small raised capsule beside Anpassen, while
/// their whole line fits in the bar's [room], else [below] the household
/// chip; nothing while there are none.
class const _Status({
  required final ValueListenable<double?> room,
  final bool below = false,
}) extends StatelessWidget {
  static const _inset = HlHex.tip * HlSize.target + HlSpace.s1;

  /// The capsule's width with [text] whole on one line, and that line's
  /// height.
  static ({double width, double line}) _measure(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble() + 2 * _inset;
    final line = painter.height;
    painter.dispose();
    return (width: width, line: line);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    final t = SnacklistColors.of(brightness);
    final cubit = context.watch<ListCubit>();
    final state = cubit.state;
    final fresh = cubit.fresh;
    final by = {for (final id in fresh) state.items[id]?.addedBy};
    final partner = by.length == 1 ? state.catalog.member(by.single) : null;
    if (fresh.isEmpty) {
      return const SizedBox.shrink();
    }
    final text = partner == null
        ? l10n.newItems(fresh.length)
        : l10n.newItemsFrom(fresh.length, partner.displayName);
    final style = TextStyle(
      fontSize: 13,
      color: t.success,
      fontWeight: FontWeight.w700,
    );
    return ValueListenableBuilder(
      valueListenable: room,
      builder: (context, room, _) {
        if (room == null) {
          return const SizedBox.shrink();
        }
        // One line decides the place: below the chip it may wrap within
        // its own width.
        final (:width, :line) = _measure(context, text, style);
        if (below == (width <= room)) {
          return const SizedBox.shrink();
        }
        // A long name takes a second line below the chip while two fit
        // inside the contour; large text keeps one, ellipsized.
        final lines = below && 2 * line <= HlSize.target - 2 * HlBorder.width
            ? 2
            : 1;
        return Semantics(
          key: const ValueKey('list-status'),
          container: true,
          sortKey: below ? const OrdinalSortKey(0) : null,
          hitTestBehavior: SemanticsHitTestBehavior.opaque,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: const HexBorder(),
              shadows: HlSticker.shadow(brightness, StickerDepth.s),
            ),
            child: Material(
              color: t.surfaceRaised,
              shape: HexBorder(
                side: BorderSide(color: t.border, width: HlBorder.width),
              ),
              child: SizedBox(
                height: HlSize.target,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _inset),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          text,
                          key: const ValueKey('new-items-subtitle'),
                          maxLines: lines,
                          textWidthBasis: TextWidthBasis.longestLine,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
