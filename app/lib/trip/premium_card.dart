import 'package:family_groceries/app/router.dart' show premiumPath;
import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_page_cubit.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/purchase_repository.dart'
    show NoSale;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// What a Free summary shows in place of the planned and extra rows (job
/// 234, PB3a, TM2's card, no blur). The button only where More lists
/// Snacklist Premium, as in Verlauf's locked row.
class const TripLockedCard({super.key}) extends StatefulWidget {
  @override
  State<TripLockedCard> createState() => _TripLockedCardState();
}

class _TripLockedCardState() extends State<TripLockedCard> {
  late final Future<OfferSwitch?> _offer = Future.value(
    context.read<PremiumServer?>()?.offerSwitch(),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final held = context.select<Entitlements?, bool>(
      (e) => e?.has(Entitlement.premium) ?? false,
    );
    final noSale = context.select<PurchaseCubit?, NoSale?>(
      (c) => c?.state.noSale,
    );
    return FutureBuilder(
      future: _offer,
      builder: (context, snapshot) {
        final opens = premiumListed(
          held: held,
          offer: snapshot.data,
          noSale: noSale,
        );
        return HlSticker(
          key: const ValueKey('trip-locked'),
          depth: StickerDepth.s,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HlSpace.s4,
              HlSpace.s4,
              HlSpace.s4,
              HlSpace.s4,
            ),
            child: Column(
              spacing: HlSpace.s2,
              children: [
                ExcludeSemantics(
                  child: PointyHex(
                    face: t.honey,
                    contour: t.border,
                    size: 40,
                    child: Icon(Icons.lock_outline, size: 22, color: t.onHoney),
                  ),
                ),
                // Own nodes: in the card's node the body would join the
                // heading, and the card's label would read before it.
                Semantics(
                  container: true,
                  header: true,
                  child: Text(
                    l10n.shopLockedTitle,
                    textAlign: TextAlign.center,
                    style: HlType.title.copyWith(color: t.text),
                  ),
                ),
                Semantics(
                  container: true,
                  child: Text(
                    l10n.shopLockedBody,
                    textAlign: TextAlign.center,
                    style: HlType.body.copyWith(color: t.textMuted),
                  ),
                ),
                if (opens)
                  Padding(
                    padding: const EdgeInsets.only(top: HlSpace.s2),
                    child: FilledButton(
                      key: const ValueKey('trip-locked-premium'),
                      onPressed: () => context.go(
                        Uri(
                          path: premiumPath,
                          queryParameters: {'from': PaywallEntry.trip.name},
                        ).toString(),
                      ),
                      child: Text(l10n.shopLockedButton),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
