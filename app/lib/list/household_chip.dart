import 'dart:async';
import 'dart:math';
import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:family_groceries/design/measured_width.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_parts.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The switcher (PLAN S1, job 169b): the shown household's name with an
/// expand icon, top left of the list, a raised button like Anpassen. It
/// opens the households sheet ([ListParts.openHouseholds]). Shown with one
/// household too, so a second one can be found. As wide as its name, at
/// most [maxWidth] ([widest]), with the bar's gap after it; [onWidth] hears
/// the width it took, gap included, after each layout that changed it.
class const HouseholdChip({
  required final double maxWidth,
  final ValueChanged<double>? onWidth,
  super.key,
}) extends StatelessWidget {
  /// The largest share of the bar's row the chip takes.
  static const _share = 0.55;

  /// Anpassen at its widest, until it is measured.
  static const _anpassen = 160.0;

  /// The sync pill's least width.
  static const _pill = HlSize.target;

  /// The least the chip needs: its padding between the hex tips, the
  /// expand icon and a letter or two. Narrower, it steps aside (320 px at
  /// large text while the sync pill shows).
  static const _least = 2 * (HlHex.tip * HlSize.target + HlSpace.s3) + 44;

  /// The widest the chip may be in a top bar [row] wide: [_share] of it,
  /// and room for [anpassen] (its width; 0 while unknown) and, while there
  /// is [trouble], the sync pill (which then shows its icon alone). 0 when
  /// that leaves it too little.
  static double widest(
    double row, {
    required double anpassen,
    required bool trouble,
  }) {
    final room = min(
      row * _share,
      row -
          (anpassen > 0 ? anpassen : _anpassen) -
          (trouble ? _pill : 0) -
          // The gaps after the chip, the pill's slot and the new adds.
          3 * HlSpace.s2,
    );
    return room < _least ? 0 : room;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // No session above: a list on its own (tests, Widgetbook) has no chip.
    final session = context.watch<SessionCubit?>()?.state;
    return MeasuredWidth(
      onWidth: onWidth,
      child: session is! InHousehold || maxWidth <= 0
          ? const SizedBox.shrink()
          : Padding(
              // The bar's gap after it: no gap while it steps aside.
              padding: const EdgeInsetsDirectional.only(end: HlSpace.s2),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Semantics(
                  container: true,
                  hint: l10n.householdSwitch,
                  // As Anpassen: on the web the rows under the chip keep
                  // their tappable semantics elements, which would take the
                  // click.
                  hitTestBehavior: SemanticsHitTestBehavior.opaque,
                  child: OutlinedButton.icon(
                    key: const ValueKey('household-chip'),
                    // Desktop's compact density would shrink it under 48 px.
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.standard,
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.expand_more, size: 18),
                    label: Text(
                      session.household.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () =>
                        unawaited(listParts(context).openHouseholds(context)),
                  ),
                ),
              ),
            ),
    );
  }
}
