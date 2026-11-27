import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:family_groceries/list/store_name_field.dart';
import 'package:family_groceries/session/new_store.dart';
import 'package:material_ui/material_ui.dart';

/// The stores onboarding offers, nothing preselected (Peter, job 58
/// ADDENDUM 3). Change the offer here and nowhere else. Names are plain
/// text: no logos, colours or ® (Legal Review N-23). "EDEKA", "Lidl" and
/// "dm" become those chains on the server, with their researched walking
/// order (`public.add_store`). The hardware store („Baumarkt“, "Hardware
/// store") is a store type, not a chain, so it is offered in the UI
/// language; the server knows both names and brings the DIY categories
/// (job 151). With the flag `open-store-app` the registry's chains of the
/// phone's region take their place ([NewStoresPicker.linked]).
List<String> popularStores(AppLocalizations l10n) => [
  'EDEKA',
  'REWE',
  'Lidl',
  'Aldi Süd',
  'Aldi Nord',
  'Kaufland',
  'Netto',
  'Penny',
  'dm',
  'Rossmann',
  l10n.storeHardware,
];

/// The stores a new household starts with, in the order picked: chips to
/// pick, nothing picked, and own ones typed in place. The guided start's
/// store step and „Neuer Haushalt“ (job 321 OB-Q8).
///
/// [linked] (the flag `open-store-app`): the chips are the chains of the
/// phone's region and the hardware store, a chain picked or typed is a
/// store linked to it, and typing suggests chains of every country. A
/// region the registry has no chains for offers no chips, only typing.
/// Otherwise the chips are [popularStores], every store plain.
class const NewStoresPicker({
  required final List<NewStore> stores,
  required final ValueChanged<List<NewStore>> onChanged,
  required final bool linked,
  final bool enabled = true,
  super.key,
}) extends StatefulWidget {
  @override
  State<NewStoresPicker> createState() => NewStoresPickerState();
}

class NewStoresPickerState() extends State<NewStoresPicker> {
  /// The own store being typed, and its text so far.
  var _naming = false;
  var _typed = '';

  /// Two stores the server would make one: the same chain, or the same
  /// name (`public.store_name_key`).
  static bool _same(NewStore a, NewStore b) =>
      (a.chain != null && a.chain == b.chain) ||
      nameKey(a.name) == nameKey(b.name);

  /// The chips, before the own stores.
  List<NewStore> _offered(AppLocalizations l10n) => switch (widget.linked) {
    false => [for (final name in popularStores(l10n)) NewStore(name)],
    true => [
      for (final r in registryChains(registryRegion()))
        NewStore(r.label, chain: r.key),
      // A region without chains gets no hardware store either: no chips.
      if (registryRegion() != null) NewStore(l10n.storeHardware),
    ],
  };

  void _toggle(NewStore chip) => widget.onChanged(
    widget.stores.any((s) => _same(s, chip))
        ? [...widget.stores.where((s) => !_same(s, chip))]
        : [...widget.stores, chip],
  );

  /// Adds [store] unless it is picked already, and closes the field.
  void _add(NewStore store) {
    if (!widget.stores.any((s) => _same(s, store))) {
      widget.onChanged([...widget.stores, store]);
    }
    _close();
  }

  void _close() => setState(() {
    _naming = false;
    _typed = '';
  });

  /// Adds the own store being typed, as its check does: the button that
  /// goes on calls it, so a name typed without the check is not lost.
  void addTyped() {
    if (_naming && _typed.trim().isNotEmpty) {
      _addOwn(_typed);
    }
  }

  /// A typed name of an offered chain ticks its chip; anything else is a
  /// store of its own, never asked about here (OB-Q6).
  bool _addOwn(String name) {
    final typed = retailerKey(name);
    final chain = widget.linked
        ? registryChains(registryRegion())
              .where(
                (r) =>
                    retailerKey(r.label) == typed ||
                    retailerKey(r.name) == typed,
              )
              .firstOrNull
        : null;
    final chip = _offered(AppLocalizations.of(context))
        .where(
          (o) => chain != null
              ? o.chain == chain.key
              : nameKey(o.name) == nameKey(name),
        )
        .firstOrNull;
    _add(chip ?? NewStore(_collapsed(name)));
    return true;
  }

  /// A suggested chain: its chip when it has one, else a store linked to it
  /// named as typed („Lidl am Markt“), or by the chain when only its start
  /// was typed.
  void _pick(RetailerMatch m) {
    final chip = _offered(AppLocalizations.of(context))
        .where((o) => o.chain == m.retailer.key)
        .firstOrNull;
    _add(
      chip ??
          NewStore(
            m.exact ? _collapsed(_typed) : m.retailer.label,
            chain: m.retailer.key,
          ),
    );
  }

  /// The registry's chains for [typed], without those picked already.
  Future<List<RetailerMatch>> _match(String typed) async => [
    for (final m in matchRegistry(typed, registryRegion()))
      if (!widget.stores.any(
        (s) =>
            s.chain == m.retailer.key ||
            nameKey(s.name) == nameKey(m.retailer.label),
      ))
        m,
  ];

  static String _collapsed(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final offered = _offered(l10n);
    final chips = [
      ...offered,
      for (final s in widget.stores)
        if (!offered.any((o) => _same(o, s))) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          key: const ValueKey('onboarding-stores'),
          spacing: HlSpace.s2,
          runSpacing: HlSpace.s2,
          children: [
            for (final chip in chips)
              if (widget.stores.any((s) => _same(s, chip)) case final picked)
                FocusRingChip(
                  chip: FilterChip(
                    key: ValueKey('onboarding-store-${chip.name}'),
                    label: Text(chip.name),
                    // The theme's label colour is white in dark; on honey the
                    // text is navy.
                    labelStyle: theme.chipTheme.labelStyle?.copyWith(
                      color: picked ? t.onHoney : t.text,
                    ),
                    selected: picked,
                    onSelected: widget.enabled ? (_) => _toggle(chip) : null,
                  ),
                ),
            if (!_naming)
              // A button, not an ActionChip: Flutter web names a chip a
              // check box.
              TextButton.icon(
                key: const ValueKey('onboarding-store-own'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, HlSize.target),
                ),
                icon: const Icon(Icons.add),
                label: Text(l10n.storeAddOwn),
                onPressed: widget.enabled
                    ? () => setState(() => _naming = true)
                    : null,
              ),
          ],
        ),
        if (_naming) ...[
          const SizedBox(height: HlSpace.s2),
          StoreNameField(
            confirmLabel: l10n.storeAddOwn,
            onConfirm: (name) async => _addOwn(name),
            onCancel: _close,
            onChanged: (text) => setState(() => _typed = text),
          ),
          if (widget.linked) ...[
            const SizedBox(height: HlSpace.s2),
            ChainSuggestions(text: _typed, match: _match, onPick: _pick),
          ],
        ],
      ],
    );
  }
}
