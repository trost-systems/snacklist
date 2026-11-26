import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_names.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The list Siri, Alexa and AI assistants add to in [householdId] when no
/// list is named (job 207), the user's own pick: [builder] makes the row
/// naming it, and a tap on that row opens a menu of the household's lists
/// to pick another. Nothing with the flag `default-list-voice-target` off,
/// with fewer than two lists (one too with [single]), or until the server
/// named the pick.
class const DefaultListPicker({
  required final String householdId,
  required final Widget Function(
    BuildContext context,
    String list,
    VoidCallback pick,
  )
  builder,

  /// The household's lists as its list shows them, so renames and deletes
  /// show at once; null asks the server.
  final List<HouseholdList>? lists,

  /// Also a household's only list.
  final bool single = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final on = context.select<Flags?, bool>(
      (flags) => flags?.isOn(defaultListFlag) ?? false,
    );
    final least = single ? 1 : 2;
    if (!on || (lists != null && lists!.length < least)) {
      return const SizedBox.shrink();
    }
    return _Picker(
      householdId,
      lists,
      builder,
      least: least,
      key: ValueKey(householdId),
    );
  }
}

class const _Picker(
  final String householdId,
  final List<HouseholdList>? lists,
  final Widget Function(BuildContext context, String list, VoidCallback pick)
  builder, {
  required final int least,
  super.key,
}) extends StatefulWidget {
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState() extends State<_Picker> {
  List<HouseholdList>? _fetched;
  String? _pick;

  /// The pick the server last confirmed, what a refusal puts back.
  String? _saved;

  /// Picks still waiting for the server; once none is, the row shows
  /// [_saved].
  var _saving = 0;

  /// Counts reads and picks: an older answer does not overwrite a newer one.
  var _asked = 0;

  List<HouseholdList> get _lists => widget.lists ?? _fetched ?? const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_Picker old) {
    super.didUpdateWidget(old);
    // A list came or went: deleting the pick moves it to the first list.
    if (!_sameIds(old.lists, widget.lists)) {
      unawaited(_load());
    }
  }

  static bool _sameIds(List<HouseholdList>? a, List<HouseholdList>? b) =>
      a?.map((l) => l.id).join(',') == b?.map((l) => l.id).join(',');

  Future<void> _load() async {
    final session = context.read<SessionCubit>();
    final asked = ++_asked;
    try {
      final lists = widget.lists == null
          ? await session.lists(widget.householdId)
          : null;
      final pick = await session.defaultList(widget.householdId);
      if (mounted && asked == _asked) {
        setState(() {
          _fetched = lists ?? _fetched;
          _pick = _saved = pick;
        });
      }
    } on HouseholdError {
      // Offline or refused: the row stays as it was, or away.
    }
  }

  /// Shows [listId] at once; a refusal puts the pick back.
  Future<void> _choose(String listId) async {
    final notices = Notices.of(context);
    final l10n = AppLocalizations.of(context);
    final session = context.read<SessionCubit>();
    final asked = ++_asked;
    _saving++;
    setState(() => _pick = listId);
    var failed = false;
    try {
      await session.setDefaultList(listId);
      _saved = listId;
    } on HouseholdError catch (e) {
      failed = true;
      notices.showSnackBar(
        SnackBar(content: Text(householdProblemText(l10n, e.problem))),
      );
    } finally {
      _saving--;
    }
    if (mounted && (_saving == 0 || (failed && asked == _asked))) {
      setState(() => _pick = _saved);
    }
  }

  Future<void> _open(BuildContext anchor, HouseholdList current) async {
    final overlay = Navigator.of(
      anchor,
      rootNavigator: true,
    ).overlay?.context.findRenderObject();
    if (anchor.findRenderObject() case final RenderBox row
        when overlay is RenderBox) {
      final l10n = AppLocalizations.of(anchor);
      final chosen = await showMenu<String>(
        context: anchor,
        useRootNavigator: true,
        position: RelativeRect.fromRect(
          Rect.fromPoints(
            row.localToGlobal(Offset.zero, ancestor: overlay),
            row.localToGlobal(
              row.size.bottomRight(Offset.zero),
              ancestor: overlay,
            ),
          ),
          Offset.zero & overlay.size,
        ),
        items: [
          for (final list in _lists)
            CheckedPopupMenuItem(
              key: ValueKey('default-list-${list.id}'),
              value: list.id,
              checked: list.id == current.id,
              child: Text(
                listName(list, l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      );
      if (chosen != null && chosen != current.id && mounted) {
        await _choose(chosen);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lists = _lists;
    final pick = _pick;
    if (lists.length < widget.least || pick == null) {
      return const SizedBox.shrink();
    }
    // Until the server is asked again, a deleted pick shows as what it
    // falls back to.
    final current = lists.where((l) => l.id == pick).firstOrNull ?? lists.first;
    return Builder(
      builder: (anchor) => widget.builder(
        context,
        listName(current, AppLocalizations.of(context)),
        () => unawaited(_open(anchor, current)),
      ),
    );
  }
}
