import 'dart:math' as math;

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/pop_if_current.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/foldout_chips.dart' show OptionChip;
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart' show Store;
import 'package:family_groceries/log/model.dart';
import 'package:family_groceries/log/store_dot.dart';
import 'package:family_groceries/log/trip_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

/// What the trip sheet did.
sealed class const TripChange();

/// [trip] was saved; [created] when it is new.
final class const TripSaved(final Trip trip, {required final bool created})
    extends TripChange;

final class const TripDeleted(final String id) extends TripChange;

/// The store chosen in the trip sheet. A new trip without a preset starts
/// [NotPicked]: „Ohne Laden“ is a choice of its own, not the default.
sealed class const StorePick();

final class const NotPicked() extends StorePick;

/// „Ohne Laden“, or in an edit the trip's own store that is gone from the
/// household.
final class const PickedNone() extends StorePick;

final class const PickedStore(final String id) extends StorePick;

/// [storeId] as a preset: a store, or „Ohne Laden“ for null.
StorePick presetStore(String? storeId) =>
    storeId == null ? const PickedNone() : PickedStore(storeId);

/// The longest item name and amount the sheet takes (`save_trip`: names
/// 1..120 characters).
const _maxName = 120;
const _maxQuantity = 40;

/// The most items one trip holds (`save_trip`).
const _maxItems = 200;

/// Opens "Einkauf eintragen", or "Einkauf bearbeiten" for [trip]: the store
/// (the household's, from the list above [context], or none), the day (not
/// after today) and the bought items with an optional amount. A new trip
/// starts at [store], [day] (today by default) and [items], under [id] when
/// given, so another sheet for the same trip writes the same row. Saves and
/// deletes through the [TripRepository] above [context]; a failure is told
/// and keeps the sheet open. Null when the user closes it.
Future<TripChange?> showTripSheet(
  BuildContext context, {
  required TripSource source,
  Trip? trip,
  StorePick store = const NotPicked(),
  DateTime? day,
  List<TripItem> items = const [],
  String? id,
  DateTime Function() clock = DateTime.now,
}) {
  final today = dateOnly(clock());
  return showModalBottomSheet<TripChange>(
    context: context,
    // Over the whole app, tabs included: the sheet stands on the bottom edge.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            curve: HlEasing.standard,
            reverseCurve: HlEasing.exit,
            duration: HlDuration.medium,
            reverseDuration: HlDuration.short,
          ),
    builder: (_) => _TripSheet(
      repository: context.read<TripRepository>(),
      stores: context.read<ListCubit>().state.catalog.stores,
      analytics: context.read<Analytics?>(),
      source: source,
      trip: trip,
      id: trip?.id ?? id ?? const Uuid().v4(),
      store: trip == null ? store : presetStore(trip.storeId),
      day: trip?.day ?? dateOnly(day ?? today),
      items: trip?.items ?? items,
      today: today,
      clock: clock,
    ),
  );
}

/// One item row's fields.
class _Row({final String name = '', final String? quantity}) {
  final nameField = TextEditingController(text: name);
  final quantityField = TextEditingController(text: quantity);
  final key = UniqueKey();

  void dispose() {
    nameField.dispose();
    quantityField.dispose();
  }
}

class const _TripSheet({
  required final TripRepository repository,
  required final List<Store> stores,
  required final Analytics? analytics,
  required final TripSource source,
  required final Trip? trip,
  required final String id,
  required final StorePick store,
  required final DateTime day,
  required final List<TripItem> items,
  required final DateTime today,
  required final DateTime Function() clock,
}) extends StatefulWidget {
  @override
  State<_TripSheet> createState() => _TripSheetState();
}

class _TripSheetState() extends State<_TripSheet> {
  /// A store that is gone from the household is no choice: an edit shows
  /// it as [_goneName], a preset is not picked. A household without stores
  /// has only „Ohne Laden“.
  late StorePick _pick = switch (widget.store) {
    PickedStore(:final id) when !widget.stores.any((s) => s.id == id) =>
      widget.trip != null ? const PickedNone() : const NotPicked(),
    NotPicked() when widget.stores.isEmpty => const PickedNone(),
    final pick => pick,
  };

  /// Save was tapped before a store was picked: said under the chips.
  var _pickMissing = false;

  String? get _storeId => switch (_pick) {
    PickedStore(:final id) => id,
    NotPicked() || PickedNone() => null,
  };

  void _choose(StorePick pick) => setState(() {
    _pick = pick;
    _pickMissing = false;
  });

  /// The name the trip was saved with when its store is gone. It takes the
  /// place of "Ohne Laden": a save without a store keeps it (`save_trip`).
  late final String? _goneName = switch (widget.trip) {
    Trip(:final storeName?, :final storeId)
        when !widget.stores.any((s) => s.id == storeId) =>
      storeName,
    _ => null,
  };

  /// Minted once per sheet, so a retry after a lost answer writes the row the
  /// first try may have committed (`save_trip` upserts by id). A new trip
  /// counts as created on the sheet's first successful save, the one that
  /// closes it, whatever an earlier try left on the server.
  late final String _id = widget.id;
  late DateTime _day = widget.day;
  late final List<_Row> _rows = [
    for (final item in widget.items)
      _Row(name: item.name, quantity: item.quantity),
    if (widget.items.isEmpty) _Row(),
  ];
  var _busy = false;

  /// Why the last save or delete failed, said above the buttons: a snackbar
  /// would sit on Speichern, right where the next try goes.
  String? _failure;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<TripItem> _items() => [
    for (final row in _rows)
      if (row.nameField.text.trim() case final name when name.isNotEmpty)
        TripItem(
          name: name,
          quantity: switch (row.quantityField.text.trim()) {
            '' => null,
            final q => q,
          },
        ),
  ];

  void _addRow() => setState(() => _rows.add(_Row()));

  void _removeRow(_Row row) {
    setState(() => _rows.remove(row));
    // Its fields leave the tree with this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: widget.today,
    );
    if (picked != null && mounted) {
      setState(() => _day = dateOnly(picked));
    }
  }

  Future<void> _save() async {
    final items = _items();
    if (items.isEmpty || _busy) {
      return;
    }
    if (_pick is NotPicked) {
      setState(() => _pickMissing = true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final before = widget.trip;
    final trip = Trip(
      id: _id,
      storeId: _storeId,
      storeName: switch (_storeId) {
        final id? => widget.stores.where((s) => s.id == id).firstOrNull?.name,
        null => _goneName,
      },
      day: _day,
      items: items,
      loggedBy: before?.loggedBy,
      createdAt: before?.createdAt ?? widget.clock(),
    );
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.repository.save(trip);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = l10n.tripSaveFailed;
        });
      }
      return;
    }
    if (before == null) {
      widget.analytics?.track('trip_logged', {'source': widget.source.name});
    }
    if (mounted) {
      popIfCurrent(context, TripSaved(trip, created: before == null));
    }
  }

  Future<void> _delete() async {
    final trip = widget.trip;
    if (trip == null || _busy) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tripDeleteTitle),
        content: Text(l10n.tripDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('trip-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.repository.delete(trip.id);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = l10n.tripDeleteFailed;
        });
      }
      return;
    }
    if (mounted) {
      popIfCurrent(context, TripDeleted(trip.id));
    }
  }

  /// [chips], and under them that no store is picked yet after a save, or
  /// while the gone store is picked, that it was deleted.
  Widget _withNote(Widget chips, AppLocalizations l10n, SnacklistColors t) {
    final note = switch (_pick) {
      NotPicked() when _pickMissing => Semantics(
        liveRegion: true,
        child: Text(
          l10n.tripStoreMissing,
          key: const ValueKey('trip-store-missing'),
          style: HlType.caption.copyWith(color: t.error),
        ),
      ),
      PickedNone() when _goneName != null => Text(
        l10n.tripStoreGone,
        key: const ValueKey('trip-store-gone-note'),
        style: HlType.caption.copyWith(color: t.textMuted),
      ),
      _ => null,
    };
    return note == null
        ? chips
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: HlSpace.s1,
            children: [chips, note],
          );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final title = widget.trip == null ? l10n.tripAdd : l10n.tripEdit;
    final yesterday = DateTime(
      widget.today.year,
      widget.today.month,
      widget.today.day - 1,
    );
    final otherDay = _day != widget.today && _day != yesterday;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: title,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              HlSpace.s4,
              0,
              HlSpace.s4,
              HlSpace.s4 + math.max(0, media.padding.bottom - keyboard),
            ),
            child: Column(
              key: const ValueKey('trip-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: HlSpace.s4,
              children: [
                SizedBox(
                  height: 16,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      margin: const EdgeInsets.only(top: 7),
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.divider,
                        borderRadius: BorderRadius.circular(HlRadius.full),
                      ),
                    ),
                  ),
                ),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: HlType.title.copyWith(color: t.text),
                  ),
                ),
                LabeledField(
                  label: l10n.tripStore,
                  field: _withNote(
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (i, store) in widget.stores.indexed)
                          OptionChip(
                            key: ValueKey('trip-store-${store.id}'),
                            label: store.name,
                            leading: StoreDot(
                              storeColour(
                                t,
                                Theme.of(context).brightness,
                                i % storePaletteSize,
                              ),
                            ),
                            selected: _storeId == store.id,
                            onTap: () => _choose(PickedStore(store.id)),
                          ),
                        OptionChip(
                          key: ValueKey(
                            _goneName == null
                                ? 'trip-store-none'
                                : 'trip-store-gone',
                          ),
                          label: _goneName ?? l10n.noStore,
                          selected: _pick is PickedNone,
                          onTap: () => _choose(const PickedNone()),
                        ),
                      ],
                    ),
                    l10n,
                    t,
                  ),
                ),
                LabeledField(
                  label: l10n.tripDay,
                  field: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OptionChip(
                        key: const ValueKey('trip-day-today'),
                        label: l10n.dayToday,
                        selected: _day == widget.today,
                        onTap: () => setState(() => _day = widget.today),
                      ),
                      OptionChip(
                        key: const ValueKey('trip-day-yesterday'),
                        label: l10n.dayYesterday,
                        selected: _day == yesterday,
                        onTap: () => setState(() => _day = yesterday),
                      ),
                      OptionChip(
                        key: const ValueKey('trip-day-other'),
                        label: otherDay
                            ? DateFormat.MMMEd(locale).format(_day)
                            : l10n.tripOtherDay,
                        leading: const Icon(Icons.event_outlined, size: 18),
                        selected: otherDay,
                        onTap: _pickDay,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: HlSpace.s2,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: hexFieldInset,
                      ),
                      child: Text(
                        l10n.tripItems,
                        style: LabeledField.labelStyle.copyWith(
                          color: t.textMuted,
                        ),
                      ),
                    ),
                    for (final (i, row) in _rows.indexed)
                      _ItemRow(
                        key: row.key,
                        index: i,
                        row: row,
                        onRemove: _rows.length > 1
                            ? () => _removeRow(row)
                            : null,
                        // Speichern waits for a name.
                        onChanged: () => setState(() {}),
                        onSubmitted: _save,
                      ),
                    if (_rows.length < _maxItems)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const ValueKey('trip-item-add'),
                          onPressed: _addRow,
                          icon: const Icon(Icons.add),
                          label: Text(l10n.tripAddItem),
                        ),
                      ),
                  ],
                ),
                if (_failure case final failure?)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      failure,
                      key: const ValueKey('trip-failure'),
                      style: HlType.caption.copyWith(color: t.error),
                    ),
                  ),
                // Large text stacks Speichern over Löschen.
                OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  overflowDirection: VerticalDirection.up,
                  overflowSpacing: HlSpace.s2,
                  children: [
                    if (widget.trip != null)
                      TextButton.icon(
                        key: const ValueKey('trip-delete'),
                        onPressed: _busy ? null : _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(l10n.tripDelete),
                      )
                    else
                      const SizedBox.shrink(),
                    FilledButton(
                      key: const ValueKey('trip-save'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(132, 52),
                      ),
                      onPressed: _busy || _items().isEmpty ? null : _save,
                      child: Text(l10n.save),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An item's name and its optional amount, and the X that drops the row.
class const _ItemRow({
  required final int index,
  required final _Row row,
  required final VoidCallback? onRemove,
  required final VoidCallback onChanged,
  required final VoidCallback onSubmitted,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    InputDecoration hinted(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      constraints: const BoxConstraints.tightFor(height: HlSize.target),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: HlSpace.s3,
        vertical: HlSpace.s2,
      ),
    );
    return Row(
      spacing: HlSpace.s2,
      children: [
        Expanded(
          child: HintNamed(
            controller: row.nameField,
            hint: l10n.tripItemName,
            field: TextField(
              autofillHints: null,
              key: ValueKey('trip-item-name-$index'),
              controller: row.nameField,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(_maxName)],
              decoration: hinted(l10n.tripItemName),
              onChanged: (_) => onChanged(),
              onSubmitted: (_) => onSubmitted(),
            ),
          ),
        ),
        SizedBox(
          width: 96,
          child: HintNamed(
            controller: row.quantityField,
            hint: l10n.itemQuantity,
            field: TextField(
              autofillHints: null,
              key: ValueKey('trip-item-quantity-$index'),
              controller: row.quantityField,
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(_maxQuantity)],
              decoration: hinted(l10n.itemQuantity),
              onSubmitted: (_) => onSubmitted(),
            ),
          ),
        ),
        SizedBox.square(
          dimension: HlSize.target,
          child: onRemove == null
              ? null
              // No tooltip: on the web a showing one moves the sheet's DOM
              // and blurs the field being typed in (job 122).
              : IconButton(
                  key: ValueKey('trip-item-remove-$index'),
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.close,
                    semanticLabel: l10n.tripRemoveItem(
                      row.nameField.text.trim().isEmpty
                          ? l10n.tripItemName
                          : row.nameField.text.trim(),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
