import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_names.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/report/report_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// What the picker offers: the shown household's items, lists and name, as
/// they were when the form opened.
@immutable
class const ReportPlaces({
  final List<ItemTarget> items = const [],
  final List<ListTarget> lists = const [],
  final HouseholdTarget? household,
}) {
  /// The shown household and its list, read from [context] above the tabs
  /// (More, the hub). Without a household there is nothing to pick but
  /// somewhere else.
  factory of(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final household = switch (context.read<SessionCubit>().state) {
      InHousehold(:final household) => household,
      _ => null,
    };
    if (household == null) {
      return const ReportPlaces();
    }
    final list = context.read<ListCubit?>()?.state;
    final lists = list?.catalog.lists ?? const [];
    final names = {for (final l in lists) l.id: listName(l, l10n)};
    final first = lists.firstOrNull?.id;
    final items = [...?list?.allItems.values]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ReportPlaces(
      items: [
        for (final item in items)
          ItemTarget(
            id: item.id,
            name: item.name,
            list: names[item.listOn(first)],
            household: household.name,
          ),
      ],
      lists: [
        for (final l in lists)
          ListTarget(
            id: l.id,
            name: listName(l, l10n),
            household: household.name,
          ),
      ],
      household: HouseholdTarget(id: household.id, name: household.name),
    );
  }
}

/// The picker sheet („Wo ist der Inhalt?“): search, the household's items,
/// lists and name, then somewhere else. The picked place, or null when it
/// was closed.
Future<ReportTarget?> showReportPicker(
  BuildContext context,
  ReportPlaces places,
) => showModalBottomSheet<ReportTarget>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  sheetAnimationStyle: AnimationStyle(
    curve: HlEasing.standard,
    reverseCurve: HlEasing.exit,
    duration: hlMotion(context, HlDuration.medium),
    reverseDuration: hlMotion(context, HlDuration.short),
  ),
  builder: (_) => _Picker(places),
);

class const _Picker(final ReportPlaces places) extends StatefulWidget {
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState() extends State<_Picker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final media = MediaQuery.of(context);
    final places = widget.places;
    final query = _search.text.trim().toLowerCase();
    bool hit(String name) =>
        query.isEmpty || name.toLowerCase().contains(query);
    final items = places.items.where((i) => hit(i.name)).toList();
    final lists = places.lists.where((l) => hit(l.name)).toList();
    final household = switch (places.household) {
      final h? when hit(h.name) => h,
      _ => null,
    };
    void pick(ReportTarget target) => Navigator.of(context).pop(target);
    const section = EdgeInsets.fromLTRB(20, 16, 16, 4);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.9,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: l10n.reportWhere,
          child: Column(
            key: const ValueKey('report-picker'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(HlRadius.full),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          l10n.reportWhere,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('report-picker-close'),
                      tooltip: l10n.close,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: HintNamed(
                  controller: _search,
                  hint: l10n.reportPickerSearch,
                  field: TextField(
                    key: const ValueKey('report-picker-search'),
                    autofillHints: null,
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l10n.reportPickerSearch,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ),
              // Above the household's rows, however many: the one way to
              // name content they don't hold.
              Padding(
                padding: const EdgeInsets.only(top: HlSpace.s1),
                child: _PickRow(
                  key: const ValueKey('report-pick-elsewhere'),
                  leading: Icon(Icons.edit_outlined, color: t.text),
                  label: l10n.reportPickerElsewhere,
                  onTap: () => pick(const ElsewhereTarget()),
                ),
              ),
              const Divider(indent: 20, endIndent: 16, height: 1),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(
                    top: HlSpace.s2,
                    bottom: HlSpace.s4 + media.padding.bottom,
                  ),
                  children: [
                    if (items.isNotEmpty) ...[
                      HlSectionLabel(l10n.reportPickerItems, padding: section),
                      for (final item in items)
                        _PickRow(
                          key: ValueKey('report-pick-item-${item.id}'),
                          leading: ItemIcon(item.name, size: 22),
                          label: item.name,
                          onTap: () => pick(item),
                        ),
                    ],
                    if (lists.isNotEmpty) ...[
                      HlSectionLabel(l10n.reportPickerLists, padding: section),
                      for (final list in lists)
                        _PickRow(
                          key: ValueKey('report-pick-list-${list.id}'),
                          leading: Icon(Icons.list_alt, color: t.text),
                          label: list.name,
                          onTap: () => pick(list),
                        ),
                    ],
                    if (household case final household?) ...[
                      HlSectionLabel(
                        l10n.reportPickerHousehold,
                        padding: section,
                      ),
                      _PickRow(
                        key: const ValueKey('report-pick-household'),
                        leading: Icon(Icons.home_outlined, color: t.text),
                        label: household.name,
                        onTap: () => pick(household),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _PickRow({
  required final Widget leading,
  required final String label,
  required final VoidCallback onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FocusRingTile(
    child: ListTile(
      minTileHeight: 52,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      // The glyph is decoration: the row is named by its label alone.
      leading: ExcludeSemantics(
        child: SizedBox(width: 28, child: Center(child: leading)),
      ),
      title: Text(label),
      onTap: onTap,
    ),
  );
}
