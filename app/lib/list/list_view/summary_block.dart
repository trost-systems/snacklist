import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/price_views.dart'
    show TotalBar, moneyLocale;
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/list/subtotals.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

const _figures = [FontFeature.tabularFigures()];

/// Where the amount goes in [_qualified]'s answer.
const _slot = '\u{E000}';

/// [amount] with [sum]'s marks, or for screen readers when [spoken]:
/// „mind.“ with items unpriced when [floor], „≈“ with an estimate in it.
String _qualified(
  AppLocalizations l10n,
  Sum sum,
  String amount, {
  required bool floor,
  required bool spoken,
}) {
  var text = amount;
  if (sum.estimate) {
    text = spoken ? l10n.moneyEstimateSpoken(text) : l10n.moneyEstimate(text);
  }
  if (floor && sum.floor) {
    text = spoken ? l10n.moneyAtLeastSpoken(text) : l10n.moneyAtLeast(text);
  }
  return text;
}

/// [sum]'s amount as shown, or for screen readers when [spoken]. Null when
/// nothing in it has a price.
String? sumText(
  BuildContext context,
  Sum sum, {
  required String currency,
  bool floor = true,
  bool spoken = false,
}) => sum.empty
    ? null
    : _qualified(
        AppLocalizations.of(context),
        sum,
        formatMoney(
          sum.cents,
          currency: currency,
          locale: moneyLocale(context),
        ),
        floor: floor,
        spoken: spoken,
      );

/// A line's amount at most this share of its width: a long store name
/// keeps the rest.
const _amountShare = 0.55;

/// [name] and [sum]'s amount on one line, the amount right and only as
/// wide as it needs, up to [_amountShare]; „mind.“ and „≈“ in [marks].
class const _Line({
  required final Widget name,
  required final Sum sum,
  required final String currency,
  required final TextStyle style,
  required final Key amountKey,
  final TextStyle? marks,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final marked = _qualified(l10n, sum, _slot, floor: true, spoken: false);
    final at = marked.indexOf(_slot);
    final (before, after) = at < 0
        ? ('', '')
        : (marked.substring(0, at), marked.substring(at + _slot.length));
    final money = formatMoney(
      sum.cents,
      currency: currency,
      locale: moneyLocale(context),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        spacing: HlSpace.s3,
        children: [
          Expanded(child: name),
          if (!sum.empty)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * _amountShare,
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (before.isNotEmpty) TextSpan(text: before, style: marks),
                    TextSpan(text: money),
                    if (after.isNotEmpty) TextSpan(text: after, style: marks),
                  ],
                ),
                key: amountKey,
                textAlign: TextAlign.end,
                style: style.copyWith(fontFeatures: _figures),
              ),
            ),
        ],
      ),
    );
  }
}

/// ST3 (job 237, flag `list-declutter`): where job 229's total row was,
/// „Einkaufssumme“, a line per store (name, „2 ohne Preis“, subtotal; a tap
/// scrolls to its section) and „Gesamt“. One store: „Gesamt“ alone. While a
/// trip runs on the list, each line splits bought and open.
class const SummaryBlock({
  required final Summary summary,
  required final String currency,

  /// Scrolls to the section of the store line's key.
  required final ValueChanged<String> onJump,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    if (summary.total.priced > 0) {
      final cubit = context.read<ListCubit>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          cubit.totalViewed();
        }
      });
    }
    return Container(
      key: const ValueKey('summary-block'),
      // Inset as the rows' text, the line as wide as theirs.
      margin: const EdgeInsets.fromLTRB(HlSpace.s4, HlSpace.s3, HlSpace.s4, 0),
      padding: const EdgeInsets.symmetric(horizontal: HlSpace.s1),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.text, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary.perStore) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: HlSpace.s3,
                bottom: HlSpace.s1,
              ),
              child: Semantics(
                header: true,
                label: l10n.tripTotal,
                excludeSemantics: true,
                child: Text(
                  l10n.tripTotal.toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: t.textMuted,
                  ),
                ),
              ),
            ),
            for (final tally in summary.stores)
              _StoreLine(
                tally: tally,
                currency: currency,
                onJump: tally.allBought ? null : () => onJump(tally.key),
              ),
            Divider(
              height: HlSpace.s2,
              thickness: HlBorder.width,
              color: t.border,
            ),
          ],
          _TotalLine(summary: summary, currency: currency),
        ],
      ),
    );
  }
}

/// What a line says under its name: while a trip runs bought and open (or
/// „alles gekauft“), then how many have no price. [spoken] for screen
/// readers.
List<String> _details(
  BuildContext context,
  Sum? bought,
  Sum open,
  String currency, {
  required bool allBought,

  /// Bought and open also when nothing was bought yet (Gesamt).
  bool split = false,
  bool spoken = false,
}) {
  final l10n = AppLocalizations.of(context);
  String part(Sum sum) =>
      sumText(context, sum, currency: currency, floor: false, spoken: spoken) ??
      formatMoney(0, currency: currency, locale: moneyLocale(context));
  // Items but no price among them: the count says so, not „0,00 € offen“.
  bool shows(Sum sum) => !sum.empty || !sum.floor;
  final unpriced = (bought ?? Sum.zero).unpriced + open.unpriced;
  return [
    if (allBought)
      l10n.subtotalsAllBought
    else if (bought != null && (split || !bought.empty || bought.floor)) ...[
      if (shows(bought)) l10n.subtotalsBought(part(bought)),
      if (shows(open)) l10n.subtotalsOpen(part(open)),
    ],
    if (unpriced > 0) l10n.subtotalsUnpriced(unpriced),
  ];
}

class const _StoreLine({
  required final StoreTally tally,
  required final String currency,

  /// Null for a store bought in full: it has no section to go to.
  required final VoidCallback? onJump,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final name = tally.store?.name ?? l10n.noStore;
    List<String> details({bool spoken = false}) => _details(
      context,
      tally.bought,
      tally.open,
      currency,
      allBought: tally.allBought,
      spoken: spoken,
    );
    final shown = details();
    final line = Container(
      constraints: const BoxConstraints(minHeight: HlSize.target),
      padding: const EdgeInsets.symmetric(vertical: HlSpace.s1),
      child: _Line(
        amountKey: ValueKey('subtotal-amount-${tally.key}'),
        sum: tally.sum,
        currency: currency,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: t.text,
        ),
        name: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: t.text,
              ),
            ),
            if (shown.isNotEmpty)
              Text.rich(
                TextSpan(
                  children: [
                    if (tally.allBought)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(end: 2),
                          child: Icon(
                            Icons.check,
                            size: 14,
                            color: t.textMuted,
                          ),
                        ),
                      ),
                    TextSpan(text: shown.join(' · ')),
                  ],
                ),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: t.textMuted,
                  fontFeatures: _figures,
                ),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      key: ValueKey('subtotal-${tally.key}'),
      container: true,
      button: onJump != null,
      label: [
        name,
        ?sumText(context, tally.sum, currency: currency, spoken: true),
        ...details(spoken: true),
      ].join(', '),
      hint: onJump == null ? null : l10n.subtotalsJump,
      onTap: onJump,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onJump,
        child: line,
      ),
    );
  }
}

class const _TotalLine({
  required final Summary summary,
  required final String currency,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final total = summary.total;
    final title = summary.perStore ? l10n.subtotalsTotal : l10n.tripTotal;
    // Without a trip the app's count wording (ST-Q6); with one „offen“
    // names the open amount, so the count says „ohne Preis“.
    List<String> details({bool spoken = false}) => summary.split
        ? _details(
            context,
            summary.bought,
            summary.open,
            currency,
            allBought: false,
            split: true,
            spoken: spoken,
          )
        : [l10n.tripCounts(total.priced, total.unpriced)];
    return Semantics(
      key: const ValueKey('total-bar'),
      container: true,
      label: [
        title,
        ?sumText(context, total, currency: currency, spoken: true),
        ...details(spoken: true),
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: TotalBar.height),
        padding: const EdgeInsets.symmetric(vertical: HlSpace.s1),
        // The counts under the whole row: at large text the amount would
        // squeeze them into a narrow column.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Line(
              amountKey: const ValueKey('total-amount'),
              sum: total,
              currency: currency,
              style: TextStyle(
                fontFamily: HlFont.display,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: t.text,
              ),
              marks: TextStyle(
                fontFamily: HlFont.sans,
                fontSize: 15,
                color: t.textMuted,
              ),
              name: Text(
                title,
                style: TextStyle(
                  fontSize: summary.perStore ? 17 : 15,
                  fontWeight: FontWeight.w800,
                  color: t.text,
                ),
              ),
            ),
            Text(
              details().join(' · '),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: t.textMuted,
                fontFeatures: _figures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
