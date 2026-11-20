import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/chain_picker.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_app.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The store screen's chain and app (job 313, flag `open-store-app`): the
/// app card (OS3) when the store's chain has an app, with the choice of
/// app when it has several (SS-Q8, kept per store), and the chain line
/// (SS1): the chain with Ändern and Lösen, or a button to link one.
class const StoreChainSection(final Store store, {super.key})
    extends StatelessWidget {
  Future<void> _pick(BuildContext context) async {
    final cubit = context.read<ListCubit>();
    final picked = await showChainPicker(
      context,
      list: cubit.listRetailers,
      match: cubit.matchRetailers,
      current: store.retailer,
    );
    if (picked != null && picked.key != store.retailer?.key) {
      await cubit.linkStore(store.id, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final text = Theme.of(context).textTheme;
    final cubit = context.read<ListCubit>();
    final retailer = store.retailer;
    final app = store.app;
    final chainLine = switch (retailer) {
      null => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('store-chain-connect'),
          onPressed: () => unawaited(_pick(context)),
          icon: const Icon(Icons.link),
          label: Text(l10n.storeChainConnect),
        ),
      ),
      final retailer => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: HlSpace.s2,
        children: [
          Text(
            l10n.storeChainLinked(
              retailer.name,
              l10n.countryName(retailer.country),
            ),
            key: const ValueKey('store-chain'),
            style: text.bodyMedium?.copyWith(color: t.textMuted),
          ),
          Semantics(
            label: l10n.storeChainChangeLabel,
            button: true,
            excludeSemantics: true,
            onTap: () => unawaited(_pick(context)),
            child: TextButton(
              key: const ValueKey('store-chain-change'),
              onPressed: () => unawaited(_pick(context)),
              child: Text(l10n.storeChainChange),
            ),
          ),
          Semantics(
            label: l10n.storeChainUnlinkLabel,
            button: true,
            excludeSemantics: true,
            onTap: () => unawaited(cubit.declineStore(store.id)),
            child: TextButton(
              key: const ValueKey('store-chain-unlink'),
              onPressed: () => unawaited(cubit.declineStore(store.id)),
              child: Text(l10n.storeChainUnlink),
            ),
          ),
        ],
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (retailer != null && app != null)
          HlGroup(
            key: const ValueKey('store-app-card'),
            top: HlSpace.s3,
            children: [
              Padding(
                padding: const EdgeInsets.all(HlSpace.s3),
                child: Row(
                  spacing: HlSpace.s3,
                  children: [
                    HlRowHex(Icons.phone_iphone, face: t.surfaceSunken),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.storeAppCardTitle,
                            style: text.labelMedium?.copyWith(
                              color: t.textMuted,
                            ),
                          ),
                          Text(
                            app.name,
                            key: const ValueKey('store-app-name'),
                            style: text.titleMedium?.copyWith(
                              color: t.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      label: l10n.storeAppOpen(app.name),
                      button: true,
                      excludeSemantics: true,
                      onTap: () => unawaited(_open(context)),
                      child: FilledButton.icon(
                        key: const ValueKey('store-app-open'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.standard,
                        ),
                        onPressed: () => unawaited(_open(context)),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(l10n.storeAppCardOpen),
                      ),
                    ),
                  ],
                ),
              ),
              if (retailer.apps.length > 1)
                RadioGroup<String>(
                  groupValue: app.android,
                  onChanged: (android) {
                    if (android != null) {
                      unawaited(cubit.setStoreApp(store.id, android));
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          HlSpace.s3,
                          HlSpace.s3,
                          HlSpace.s3,
                          0,
                        ),
                        child: Text(
                          l10n.storeAppCardChoose,
                          style: text.bodySmall?.copyWith(color: t.textMuted),
                        ),
                      ),
                      for (final choice in retailer.apps)
                        HexRadioTile<String>(
                          key: ValueKey('store-app-choice-${choice.android}'),
                          value: choice.android,
                          title: Text(choice.name),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HlSpace.s4,
            HlSpace.s2,
            HlSpace.s4,
            0,
          ),
          child: chainLine,
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context) => openStoreApp(
    store,
    opener: context.read<StoreAppOpener>(),
    analytics: context.read<Analytics?>(),
  );
}
