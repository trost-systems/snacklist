import 'dart:async';

import 'package:family_groceries/design/measured_width.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/household_chip.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_names.dart';
import 'package:family_groceries/list/list_parts.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The decluttered list's switcher (job 229, flag `list-declutter`), in the
/// household chip's place: the household's name small over the shown list's,
/// and an unfold icon, in one raised button that opens the switcher sheet
/// ([ListParts.openSwitcher]). Shown with one household and one list too.
/// Its width follows the chip's rules ([HouseholdChip.widest]): as wide as
/// the longer name, at most [maxWidth], with the bar's gap after it;
/// [onWidth] hears the width it took, gap included.
class const ListSwitcherButton({
  required final double maxWidth,
  final ValueChanged<double>? onWidth,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    // No session above: a list on its own (tests, Widgetbook) has no
    // switcher.
    final session = context.watch<SessionCubit?>()?.state;
    final list = context.select<ListCubit, String?>(
      (c) => switch (c.state.shownList) {
        final shown? => listName(shown, l10n),
        null => null,
      },
    );
    if (session is! InHousehold || maxWidth <= 0) {
      return MeasuredWidth(onWidth: onWidth, child: const SizedBox.shrink());
    }
    final household = session.household.name;
    Text line(String text, TextStyle style) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return MeasuredWidth(
      onWidth: onWidth,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: HlSpace.s2),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: OutlinedButton(
            key: const ValueKey('list-switcher'),
            style: OutlinedButton.styleFrom(
              // Desktop's compact density would shrink it under 48 px.
              visualDensity: VisualDensity.standard,
              // Two lines take the height the label's padding would.
              padding: const EdgeInsetsDirectional.only(
                start: HlHex.tip * HlSize.target + HlSpace.s3,
                end: HlHex.tip * HlSize.target + HlSpace.s1,
              ),
            ),
            onPressed: () =>
                unawaited(listParts(context).openSwitcher(context)),
            child: Semantics(
              label: [?list, household].join(' · '),
              hint: l10n.listSwitch,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: HlSpace.s1,
                  children: [
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          line(
                            household,
                            TextStyle(
                              fontSize: 11.5,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                              color: t.textMuted,
                            ),
                          ),
                          if (list != null)
                            line(
                              list,
                              TextStyle(
                                fontFamily: HlFont.display,
                                fontSize: 15,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: t.text,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.unfold_more, size: 18, color: t.text),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
