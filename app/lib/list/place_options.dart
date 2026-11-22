import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/model.dart';
import 'package:material_ui/material_ui.dart';

/// The place chip's text: „Ganz vorne“ or „Neben {name}“.
String placementLabel(
  AppLocalizations l10n,
  Placement placement,
  List<Item> run,
) => switch (placement) {
  PlaceFirst() => l10n.placeFirst,
  PlaceAfter(:final anchorId) => l10n.placeNextTo(
    run.where((i) => i.id == anchorId).firstOrNull?.name ?? '',
  ),
};

/// Above this many other items the options get a filter field (IO-Q12).
const placeFilterFrom = 15;

/// The place chip's options: „Ganz vorne“, then the section's other open
/// items in walk order, [selected] marked; a filter field on top when there
/// are more than [placeFilterFrom] others.
class const PlaceOptions({
  required final List<Item> others,
  required final Placement selected,
  required final ValueChanged<Placement> onPick,
  super.key,
}) extends StatefulWidget {
  @override
  State<PlaceOptions> createState() => _PlaceOptionsState();
}

class _PlaceOptionsState() extends State<PlaceOptions> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = widget.others.length > placeFilterFrom;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          if (filtered)
            HintNamed(
              controller: _filter,
              hint: l10n.placeFilter,
              field: TextField(
                key: const ValueKey('place-filter'),
                autofillHints: null,
                controller: _filter,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l10n.placeFilter,
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
              ),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OptionChip(
                key: const ValueKey('place-option-start'),
                label: l10n.placeFirst,
                selected: widget.selected == const PlaceFirst(),
                onTap: () => widget.onPick(const PlaceFirst()),
              ),
              for (final item in _shown(filtered))
                OptionChip(
                  key: ValueKey('place-option-${item.id}'),
                  label: item.name,
                  selected: widget.selected == PlaceAfter(item.id),
                  onTap: () => widget.onPick(PlaceAfter(item.id)),
                ),
            ],
          ),
          const SizedBox(height: HlSpace.s1),
        ],
      ),
    );
  }

  Iterable<Item> _shown(bool filtered) {
    final text = _filter.text.trim().toLowerCase();
    return !filtered || text.isEmpty
        ? widget.others
        : widget.others.where((i) => i.name.toLowerCase().contains(text));
  }
}
