import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:material_ui/material_ui.dart';

/// The question after an own tick while no trip runs (job 234, TM2's
/// sheet). [itemName] is the item just ticked off. [quiet]: a line under
/// the buttons says that „Nein“ snoozes it for an hour (job 357's snooze)
/// and keeps this shop from being detected (job 352).
Future<AskAnswer> showTripAsk(
  BuildContext context, {
  required String itemName,
  bool quiet = false,
}) async =>
    await showModalBottomSheet<AskAnswer>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => TripAskSheet(itemName: itemName, quiet: quiet),
    ) ??
    AskAnswer.no;

class const TripAskSheet({
  required final String itemName,
  final bool quiet = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    void answer(AskAnswer a) => Navigator.of(context).pop(a);
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('trip-ask'),
        padding: const EdgeInsets.fromLTRB(
          HlSpace.s5,
          0,
          HlSpace.s5,
          HlSpace.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MergeSemantics(
              child: Row(
                spacing: HlSpace.s2,
                children: [
                  ExcludeSemantics(child: ItemIcon(itemName, size: 18)),
                  Flexible(
                    child: Text(
                      l10n.itemTicked(itemName),
                      style: HlType.label.copyWith(color: t.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HlSpace.s2),
            Semantics(
              header: true,
              child: Text(
                l10n.shopAskTitle,
                style: HlType.title.copyWith(color: t.text),
              ),
            ),
            const SizedBox(height: HlSpace.s1),
            Text(
              l10n.shopAskBody,
              style: HlType.body.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: HlSpace.s4),
            FilledButton(
              key: const ValueKey('trip-ask-yes'),
              onPressed: () => answer(AskAnswer.yes),
              child: Text(l10n.shopAskYes),
            ),
            const SizedBox(height: HlSpace.s3),
            OutlinedButton(
              key: const ValueKey('trip-ask-no'),
              onPressed: () => answer(AskAnswer.no),
              child: Text(l10n.shopAskNo),
            ),
            if (quiet) ...[
              const SizedBox(height: HlSpace.s2),
              Text(
                l10n.shopAskQuiet,
                key: const ValueKey('trip-ask-quiet'),
                textAlign: TextAlign.center,
                style: HlType.caption.copyWith(color: t.textMuted),
              ),
            ],
            const SizedBox(height: HlSpace.s3),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.shopAskMistake,
                  style: HlType.body.copyWith(color: t.textMuted),
                ),
                TextButton(
                  key: const ValueKey('trip-ask-take-back'),
                  onPressed: () => answer(AskAnswer.takeBack),
                  child: Text(l10n.shopAskTakeBack),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
