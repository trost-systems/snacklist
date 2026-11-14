import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/list_view/price_views.dart'
    show moneyLocale;
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/premium_card.dart';
import 'package:family_groceries/trip/summary.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// A finished trip's summary (job 234, TM1's page): the head, then without
/// Premium the locked card, with it a section per store with what was on
/// the list at the start and what came in since, and with [prices] the
/// amounts. Plain inputs; the page around it finds the trip.
class const TripSummaryView({
  required final FinishedTrip trip,
  required final Catalog catalog,
  required final bool prices,

  /// Free (PB3a): the head and the count, then the locked card, also for a
  /// trip whose lines this device computed itself.
  final bool locked = false,

  /// „War geplant“ changes not in [trip] yet, by line key.
  final Map<String, bool> marks = const {},

  /// „War geplant“ on an extra; null: not offered.
  final void Function(TripLine line, bool planned)? onMark,

  /// Just ended on this device: „Weiter einkaufen“ and „Fertig“.
  final VoidCallback? onKeepShopping,
  final VoidCallback? onDone,

  /// The end has not reached the server yet; null when it has.
  final VoidCallback? onRetrySave,

  /// The server refused the end for good: not saved, and no retry.
  final bool refused = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final hm = DateFormat.Hm(locale);
    final lines = switch (trip.lines) {
      final lines? when marks.isNotEmpty => [
        for (final l in lines)
          if (marks[l.key] case final on?) l.withMarked(on) else l,
      ],
      final lines => lines,
    };
    final report = lines == null || locked
        ? null
        : tripReport(lines, catalog.stores);
    final stores = [for (final name in trip.stores) ?name];
    final when = l10n.shopSummaryWhen(
      DateFormat.MMMEd(locale).format(trip.startedAt.toLocal()),
      hm.format(trip.startedAt.toLocal()),
      hm.format(trip.endedAt.toLocal()),
    );
    final totals = report?.totals;
    final lede = switch (totals) {
      null => l10n.shopTicked(trip.bought),
      TripTotals(plannedCount: 0, :final bought) => l10n.shopLedeNoList(bought),
      TripTotals(:final plannedBought, :final plannedCount, :final extraBought)
          when extraBought > 0 =>
        '${l10n.shopLede(plannedBought, plannedCount)} · '
            '${l10n.shopLedeExtra(extraBought)}',
      TripTotals(:final plannedBought, :final plannedCount) => l10n.shopLede(
        plannedBought,
        plannedCount,
      ),
    };
    final money = _Money(
      currency: trip.currency,
      locale: moneyLocale(context),
      l10n: l10n,
    );
    final hintAfter = report?.sections.indexWhere(
      (s) => s.extras.any((l) => l.bought) || s.planned.any((l) => !l.planned),
    );
    return ListView(
      key: const ValueKey('trip-summary'),
      padding: EdgeInsets.fromLTRB(
        HlSpace.s4,
        HlSpace.s3,
        HlSpace.s4,
        HlSpace.s7 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          [when, ...stores].join(' · '),
          key: const ValueKey('trip-summary-when'),
          style: HlType.label.copyWith(color: t.textMuted),
        ),
        const SizedBox(height: HlSpace.s1),
        Semantics(
          header: true,
          child: Text(
            l10n.shopShoppedFor(_duration(l10n, trip.active)),
            style: HlType.headline.copyWith(color: t.text, fontSize: 28),
          ),
        ),
        const SizedBox(height: HlSpace.s2),
        Text(
          lede,
          key: const ValueKey('trip-summary-lede'),
          style: HlType.bodyL.copyWith(
            color: t.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trip.end == TripEnd.auto)
          Padding(
            padding: const EdgeInsets.only(top: HlSpace.s1),
            child: Text(
              l10n.shopAutoEndHint(hm.format(trip.endedAt.toLocal())),
              style: HlType.body.copyWith(color: t.textMuted),
            ),
          ),
        if (onRetrySave != null || refused)
          Padding(
            padding: const EdgeInsets.only(top: HlSpace.s3),
            child: _NotSaved(onRetry: onRetrySave),
          ),
        if (report == null)
          const Padding(
            padding: EdgeInsets.only(top: HlSpace.s5),
            child: TripLockedCard(),
          )
        else ...[
          for (final (i, section) in report.sections.indexed)
            _Section(
              section: section,
              catalog: catalog,
              money: prices ? money : null,
              onMark: onMark,
              hint: i == hintAfter && onMark != null,
              titled: report.sections.length > 1 || section.store is! NoStore,
            ),
          if (prices && report.sections.isNotEmpty) ...[
            const SizedBox(height: HlSpace.s5),
            _Totals(
              key: const ValueKey('trip-summary-total'),
              label: l10n.shopPaidTotal,
              totals: report.totals,
              money: money,
              strong: true,
            ),
            const SizedBox(height: HlSpace.s2),
            Text(
              l10n.shopTotalsNote,
              style: HlType.caption.copyWith(color: t.textMuted),
            ),
          ],
        ],
        if (onDone != null || onKeepShopping != null)
          Padding(
            padding: const EdgeInsets.only(top: HlSpace.s5),
            child: OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: HlSpace.s2,
              overflowSpacing: HlSpace.s2,
              children: [
                if (onKeepShopping case final keep?)
                  TextButton(
                    key: const ValueKey('trip-summary-keep-shopping'),
                    onPressed: keep,
                    child: Text(l10n.shopKeepShopping),
                  ),
                if (onDone case final done?)
                  FilledButton(
                    key: const ValueKey('trip-summary-done'),
                    onPressed: done,
                    child: Text(l10n.done),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// „25 Min.“, „1 Std. 5 Min.“, to the nearest minute as the header's
/// times; a trip of under half a minute is „Unter 1 Min.“.
String _duration(AppLocalizations l10n, Duration active) {
  final minutes = (active.inSeconds + 30) ~/ 60;
  return minutes < 1
      ? l10n.shopUnderAMinute
      : minutes < 60
      ? l10n.shopMinutes(minutes)
      : l10n.shopHoursMinutes(minutes ~/ 60, minutes % 60);
}

class const _Money({
  required final String currency,
  required final String locale,
  required final AppLocalizations l10n,
}) {
  String call(int cents) =>
      formatMoney(cents, currency: currency, locale: locale);

  /// „2,45 € mehr“, „0,30 € weniger“, „wie geplant“.
  String difference(int cents) => switch (cents) {
    0 => l10n.shopAsPlanned,
    > 0 => l10n.shopMore(call(cents)),
    _ => l10n.shopLess(call(-cents)),
  };
}

class const _NotSaved({required final VoidCallback? onRetry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return HlSticker(
      depth: StickerDepth.flat,
      color: t.honeySoft,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          HlSpace.s3,
          HlSpace.s2,
          HlSpace.s2,
          HlSpace.s2,
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: HlSpace.s2,
          children: [
            Text(l10n.shopNotSaved, style: HlType.body.copyWith(color: t.text)),
            if (onRetry != null)
              TextButton(
                key: const ValueKey('trip-summary-retry'),
                onPressed: onRetry,
                child: Text(l10n.retry),
              ),
          ],
        ),
      ),
    );
  }
}

class const _Section({
  required final TripSection section,
  required final Catalog catalog,
  required final _Money? money,
  required final void Function(TripLine line, bool planned)? onMark,

  /// The „War geplant“ explanation under this section's extras.
  required final bool hint,

  /// A store title; a trip without stores has none.
  required final bool titled,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final name = switch (section.store) {
      HouseholdStore(:final store) => store.name,
      GoneStore(:final name) => name,
      NoStore() => l10n.noStore,
    };
    const labelPadding = EdgeInsets.fromLTRB(4, HlSpace.s4, 0, HlSpace.s2);
    Widget rows(List<TripLine> lines) => HlSticker(
      depth: StickerDepth.s,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final (i, line) in lines.indexed) ...[
              if (i > 0) Divider(height: 1, color: t.divider),
              _Row(line: line, catalog: catalog, money: money, onMark: onMark),
            ],
          ],
        ),
      ),
    );
    // The section is one node of the page's list: each part below is its
    // own container, or its text and flags would merge into the section.
    Widget count(int n) => Semantics(
      container: true,
      label: l10n.listItemCount(n),
      excludeSemantics: true,
      child: Text('$n', style: HlSectionLabel.overline(t.text)),
    );
    return Column(
      key: ValueKey('trip-section-$name'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titled)
          Padding(
            padding: const EdgeInsets.only(top: HlSpace.s5),
            child: Semantics(
              container: true,
              header: true,
              child: Row(
                spacing: HlSpace.s2,
                children: [
                  Icon(Icons.storefront_outlined, color: t.text, size: 22),
                  Flexible(
                    child: Text(
                      name,
                      style: HlType.title.copyWith(color: t.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (section.planned.isNotEmpty) ...[
          HlSectionLabel(
            l10n.shopPlannedSection,
            padding: labelPadding,
            badge: count(section.planned.length),
          ),
          rows(section.planned),
        ],
        if (section.extras.isNotEmpty) ...[
          HlSectionLabel(
            l10n.shopExtraSection,
            padding: labelPadding,
            badge: count(section.extras.length),
          ),
          rows(section.extras),
        ],
        if (hint)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, HlSpace.s2, 4, 0),
            child: Semantics(
              container: true,
              child: Text(
                l10n.shopMarkPlannedHint,
                style: HlType.caption.copyWith(color: t.textMuted),
              ),
            ),
          ),
        if (money case final money?) ...[
          const SizedBox(height: HlSpace.s3),
          _Totals(label: l10n.shopPaid, totals: section.totals, money: money),
        ],
      ],
    );
  }
}

class const _Row({
  required final TripLine line,
  required final Catalog catalog,
  required final _Money? money,
  required final void Function(TripLine line, bool planned)? onMark,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final by = switch (catalog.member(line.addedBy)?.displayName) {
      final name? when line.byOther && name.trim().isNotEmpty => l10n.shopBy(
        name,
      ),
      _ when line.byOther => l10n.shopByOther,
      _ => null,
    };
    final paid = line.paidCents;
    final planned = line.plannedCents;
    final amounts = switch (money) {
      null => null,
      final money => [
        if (paid != null) money(paid),
        if (paid != null && planned != null) ...[
          l10n.shopPlannedPrice(money(planned)),
          money.difference(paid - planned),
        ],
      ],
    };
    final meta = [
      ?by,
      if (!line.bought) l10n.shopNotBought,
      ...?amounts,
    ].join(' · ');
    final name = switch (line.quantity) {
      final q? when q.trim().isNotEmpty => '$q ${line.name}',
      _ => line.name,
    };
    final markable = onMark != null && line.bought && !line.planned;
    return ConstrainedBox(
      key: ValueKey('trip-line-${line.key}'),
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          HlSpace.s3,
          HlSpace.s2,
          HlSpace.s2,
          HlSpace.s2,
        ),
        child: Row(
          spacing: HlSpace.s2,
          children: [
            Expanded(
              child: MergeSemantics(
                child: Row(
                  spacing: HlSpace.s2,
                  children: [
                    Semantics(
                      // „nicht gekauft“ is in the meta line already.
                      label: line.bought ? l10n.shopBought : null,
                      excludeSemantics: true,
                      child: PointyHex(
                        face: line.bought ? t.mint : t.surfaceRaised,
                        contour: t.border,
                        size: 24,
                        child: line.bought
                            ? Icon(Icons.check, size: 15, color: t.onMint)
                            : null,
                      ),
                    ),
                    ExcludeSemantics(child: ItemIcon(line.name, size: 20)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Text(
                            name,
                            style: HlType.body.copyWith(
                              color: line.bought ? t.text : t.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (meta.isNotEmpty)
                            Text(
                              meta,
                              style: HlType.caption.copyWith(
                                color: t.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (markable)
              // The toggled state on the button's own node.
              MergeSemantics(
                child: Semantics(
                  toggled: line.markedPlanned,
                  child: OutlinedButton.icon(
                    key: ValueKey('trip-mark-${line.key}'),
                    onPressed: () => onMark?.call(line, !line.markedPlanned),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: line.markedPlanned ? t.mintSoft : null,
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: HlSpace.s3,
                      ),
                    ),
                    icon: line.markedPlanned
                        ? const Icon(Icons.undo, size: 16)
                        : null,
                    label: Text(l10n.shopMarkPlanned),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// „Bezahlt 23,45 €“ with what it compares to and what it leaves out.
class const _Totals({
  required final String label,
  required final TripTotals totals,
  required final _Money money,
  final bool strong = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final style = (strong ? HlType.title : HlType.label).copyWith(
      color: t.text,
    );
    final notes = [
      if (totals.compared > 0)
        [
          l10n.shopCompared(
            money(totals.planned),
            money.difference(totals.difference),
          ),
          l10n.shopComparedCount(totals.compared),
        ].join(' · '),
      if (totals.withoutPrice > 0) l10n.shopWithoutPrice(totals.withoutPrice),
      if (totals.withoutPlan > 0) l10n.shopWithoutPlan(totals.withoutPlan),
    ];
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: style)),
                Text(money(totals.paid), style: style),
              ],
            ),
            for (final note in notes)
              Text(note, style: HlType.caption.copyWith(color: t.textMuted)),
          ],
        ),
      ),
    );
  }
}
