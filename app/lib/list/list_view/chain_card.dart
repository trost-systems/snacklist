import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/chain_question.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The card at the list's top that asks the household's existing stores
/// for their chain (job 313, SS5), one store at a time with its progress
/// („1 / 3“): only unlinked, unanswered stores whose exact match has an
/// app. Flag `open-store-app`; none offline or behind the add sheet.
class const ChainCard({super.key}) extends StatefulWidget {
  /// How long the stores stay unchanged before the questions are asked
  /// again: a reload or a burst of realtime events asks once.
  static const settle = Duration(milliseconds: 500);

  @override
  State<ChainCard> createState() => _ChainCardState();
}

class _ChainCardState() extends State<ChainCard> {
  var _questions = const <StoreQuestion>[];

  /// Stores answered while the card showed, for its progress.
  var _answered = 0;
  var _asked = false;
  Timer? _settle;

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  void _askSoon() {
    _settle?.cancel();
    _settle = Timer(ChainCard.settle, () => unawaited(_ask()));
  }

  Future<void> _ask() async {
    final questions = await context.read<ListCubit>().retailerQuestions();
    if (!mounted) {
      return;
    }
    setState(() {
      _questions = questions;
      if (questions.isEmpty) {
        _answered = 0;
      }
    });
  }

  Future<void> _answer(String storeId, Retailer? chain) async {
    final cubit = context.read<ListCubit>();
    setState(() => _answered++);
    final saved = chain == null
        ? await cubit.declineStore(storeId)
        : await cubit.linkStore(storeId, chain);
    if (!mounted) {
      return;
    }
    if (saved && chain != null) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(context).migrateDone,
          Directionality.of(context),
        ),
      );
    }
    setState(() {
      if (saved) {
        _questions = [..._questions.where((q) => q.storeId != storeId)];
      } else {
        _answered--;
      }
    });
  }

  /// What a change to the stores can change about the questions.
  static List<Object?> _storesKey(ListState state) => [
    for (final s in state.catalog.stores) ...[
      s.id,
      s.name,
      s.retailer?.key,
      s.retailerAnswered,
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final on = context.select<Flags?, bool>(
      (f) => f?.isOn(openStoreAppFlag) ?? false,
    );
    final offline = context.select<ListCubit, bool>(
      (c) => c.state.connection == ConnectionStatus.offline,
    );
    final behindSheet = context.select<AddSheetCubit?, bool>(
      (c) => c?.state.open ?? false,
    );
    if (on && !_asked) {
      _asked = true;
      _askSoon();
    }
    final catalog = context.select<ListCubit, Catalog>((c) => c.state.catalog);
    final open = [
      for (final q in _questions)
        if (catalog.store(q.storeId) case final store?
            when store.retailer == null && !store.retailerAnswered)
          (store, q.chains),
    ];
    final listener = BlocListener<ListCubit, ListState>(
      listenWhen: (before, after) =>
          on &&
          (!listEquals(_storesKey(before), _storesKey(after)) ||
              (before.connection != ConnectionStatus.online &&
                  after.connection == ConnectionStatus.online)),
      listener: (context, state) => _askSoon(),
      child: switch (open) {
        [(final store, final chains), ...]
            when on && !offline && !behindSheet =>
          _Card(
            key: ValueKey('chain-card-${store.id}'),
            store: store,
            chains: chains,
            index: _answered + 1,
            total: _answered + open.length,
            onAnswer: (chain) => unawaited(_answer(store.id, chain)),
          ),
        _ => const SizedBox.shrink(),
      },
    );
    return listener;
  }
}

class const _Card({
  required final Store store,
  required final List<Retailer> chains,
  required final int index,
  required final int total,
  required final ValueChanged<Retailer?> onAnswer,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HlSpace.s3,
        vertical: HlSpace.s2,
      ),
      child: Semantics(
        container: true,
        child: HlSticker(
          depth: StickerDepth.s,
          child: Padding(
            padding: const EdgeInsets.all(HlSpace.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: HlSpace.s1,
              children: [
                Semantics(
                  container: true,
                  label: l10n.chainCardProgressLabel(index, total),
                  excludeSemantics: true,
                  child: Text(
                    l10n.chainCardProgress(index, total),
                    key: const ValueKey('chain-card-progress'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                ChainQuestion(
                  storeName: store.name,
                  chains: chains,
                  existing: true,
                  onAnswer: onAnswer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
