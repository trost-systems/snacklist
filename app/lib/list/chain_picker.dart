import 'dart:async';

import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:material_ui/material_ui.dart';

/// Lets the user pick the chain a store is (job 313, SS1): a search over
/// [list], the phone region's chains first, and, for two letters or more,
/// [match]'s chains of every country first (aliases too: „Hofer“ on a
/// German phone finds Hofer · Österreich). Null when closed without one.
Future<Retailer?> showChainPicker(
  BuildContext context, {
  required Future<List<Retailer>> Function() list,
  required Future<List<RetailerMatch>> Function(String name) match,
  Retailer? current,
}) => showModalBottomSheet<Retailer>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _ChainPicker(list: list, match: match, current: current),
);

class const _ChainPicker({
  required final Future<List<Retailer>> Function() list,
  required final Future<List<RetailerMatch>> Function(String name) match,
  required final Retailer? current,
}) extends StatefulWidget {
  @override
  State<_ChainPicker> createState() => _ChainPickerState();
}

class _ChainPickerState() extends State<_ChainPicker> {
  final _search = TextEditingController();
  List<Retailer>? _all;
  var _matched = const <Retailer>[];
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.list().then((all) {
        if (mounted) {
          setState(() => _all = all);
        }
      }),
    );
  }

  @override
  void dispose() {
    _wait?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _changed(String text) {
    setState(() {});
    _wait?.cancel();
    final query = text.trim();
    if (query.length < 2) {
      setState(() => _matched = const []);
      return;
    }
    _wait = Timer(const Duration(milliseconds: 250), () async {
      final rows = await widget.match(query);
      if (mounted && _search.text.trim() == query) {
        setState(() => _matched = [for (final m in rows) m.retailer]);
      }
    });
  }

  /// The server's matches, then the chains whose name holds the text.
  List<Retailer> _shown(List<Retailer> all) {
    final query = nameKey(_search.text);
    if (query.isEmpty) {
      return all;
    }
    final seen = <({String chain, String country})>{};
    return [
      for (final r in [
        ..._matched,
        ...all.where((r) => nameKey(r.name).contains(query)),
      ])
        if (seen.add(r.key)) r,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final all = _all;
    final shown = all == null ? null : _shown(all);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HlSpace.s4),
            child: Semantics(
              header: true,
              child: Text(
                l10n.storeChainPickerTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(HlSpace.s4),
            child: HintNamed(
              controller: _search,
              hint: l10n.storeChainPickerSearch,
              field: TextField(
                autofillHints: null,
                key: const ValueKey('chain-picker-search'),
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _changed,
                decoration: InputDecoration(
                  hintText: l10n.storeChainPickerSearch,
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
              ),
            ),
          ),
          Flexible(
            child: switch (shown) {
              null => const Padding(
                padding: EdgeInsets.all(HlSpace.s5),
                child: Center(child: CircularProgressIndicator()),
              ),
              [] => Padding(
                padding: const EdgeInsets.all(HlSpace.s4),
                child: Text(
                  l10n.storeChainPickerEmpty,
                  key: const ValueKey('chain-picker-empty'),
                  style: TextStyle(color: t.textMuted),
                ),
              ),
              _ => ListView(
                key: const ValueKey('chain-picker-list'),
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: HlSpace.s4),
                children: [
                  for (final r in shown)
                    _ChainRow(
                      key: ValueKey('chain-pick-${r.chain}-${r.country}'),
                      retailer: r,
                      current: widget.current?.key == r.key,
                      onTap: () => Navigator.of(context).pop(r),
                    ),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// A chain in the picker: „Lidl · Deutschland“, its app below; a check on
/// the store's chain.
class const _ChainRow({
  required final Retailer retailer,
  required final bool current,
  required final VoidCallback onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final country = l10n.countryName(retailer.country);
    final app = retailer.apps.firstOrNull;
    return Semantics(
      button: true,
      selected: current,
      label: l10n.chainWithCountry(retailer.name, country),
      onTap: onTap,
      excludeSemantics: true,
      child: FocusRingTile(
        child: ListTile(
          leading: Icon(Icons.storefront_outlined, color: t.textMuted),
          title: Text(retailer.name),
          subtitle: Text(
            app == null ? country : '$country · ${app.name}',
            style: TextStyle(color: t.textMuted),
          ),
          trailing: current ? Icon(Icons.check, color: t.accent) : null,
          onTap: onTap,
        ),
      ),
    );
  }
}
