import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:material_ui/material_ui.dart';

/// [ChainQuestion]'s question, also announced where it appears without a
/// focus change.
String chainQuestionTitle(
  AppLocalizations l10n,
  String storeName,
  List<Retailer> chains, {
  required bool existing,
}) => switch (chains) {
  [final chain] =>
    existing
        ? l10n.chainQuestionOneExisting(
            storeName,
            chain.name,
            l10n.countryName(chain.country),
          )
        : l10n.chainQuestionOne(chain.name, l10n.countryName(chain.country)),
  _ =>
    existing
        ? l10n.chainQuestionWhichExisting(storeName)
        : l10n.chainQuestionWhich(storeName),
};

/// Asks once whether the store [storeName] is one of [chains] (job 313,
/// SS2 and SS5): „Ist das REWE (Deutschland)?“ with Ja and Nein, or, for a
/// name several chains carry, „Welches Aldi?“ with a button per chain and
/// „Keins davon“. [onAnswer] gets the chain picked, or null for no.
/// [existing] words it for a store the household already has (the list
/// card) rather than one just saved. Bare content: the caller frames it in
/// a card, sheet or dialog.
class const ChainQuestion({
  required final String storeName,
  required final List<Retailer> chains,
  required final bool existing,
  required final ValueChanged<Retailer?> onAnswer,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final countries = {for (final c in chains) c.country};
    final (title, line, buttons) = switch (chains) {
      [final chain] => (
        chainQuestionTitle(l10n, storeName, chains, existing: existing),
        switch (chain.apps.firstOrNull) {
          _ when existing => l10n.migrateBody,
          final app? => l10n.chainQuestionApp(app.name),
          null => null,
        },
        [
          FilledButton(
            key: const ValueKey('chain-question-yes'),
            onPressed: () => onAnswer(chain),
            child: Text(l10n.chainQuestionYes),
          ),
          TextButton(
            key: const ValueKey('chain-question-no'),
            onPressed: () => onAnswer(null),
            child: Text(
              existing ? l10n.chainQuestionNo : l10n.chainQuestionKeep,
            ),
          ),
        ],
      ),
      _ => (
        chainQuestionTitle(l10n, storeName, chains, existing: existing),
        existing ? l10n.migrateBody : null,
        [
          for (final chain in chains)
            OutlinedButton(
              key: ValueKey('chain-question-${chain.chain}-${chain.country}'),
              onPressed: () => onAnswer(chain),
              child: Text(
                countries.length > 1
                    ? l10n.chainWithCountry(
                        chain.name,
                        l10n.countryName(chain.country),
                      )
                    : chain.name,
              ),
            ),
          TextButton(
            key: const ValueKey('chain-question-none'),
            onPressed: () => onAnswer(null),
            child: Text(l10n.chainQuestionNone),
          ),
        ],
      ),
    };
    return Column(
      key: const ValueKey('chain-question'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Its own node: merged into the card's container, the whole card
        // became the header (a banner landmark on the web).
        Semantics(
          container: true,
          header: true,
          child: Text(title, style: text.titleMedium),
        ),
        if (line != null)
          Padding(
            padding: const EdgeInsets.only(top: HlSpace.s1),
            child: Text(
              line,
              style: text.bodyMedium?.copyWith(color: t.textMuted),
            ),
          ),
        const SizedBox(height: HlSpace.s3),
        Wrap(
          spacing: HlSpace.s2,
          runSpacing: HlSpace.s2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: buttons,
        ),
      ],
    );
  }
}

/// Asks [chains]' question about [store], just saved, in a dialog: an
/// answer goes to [answer] (null: none of them). Closed without one, the
/// store stays unanswered, so the list may ask later.
Future<void> askChain(
  BuildContext context,
  Store store,
  List<Retailer> chains,
  Future<bool> Function(String storeId, Retailer? chain) answer,
) async {
  final picked = await showDialog<(Retailer?,)>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('chain-question-dialog'),
      scrollable: true,
      content: ChainQuestion(
        storeName: store.name,
        chains: chains,
        existing: false,
        onAnswer: (chain) => Navigator.of(context).pop((chain,)),
      ),
    ),
  );
  if (picked case (final chain,)) {
    await answer(store.id, chain);
  }
}
