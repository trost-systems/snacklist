import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:family_groceries/list/store_app.dart';
import 'package:family_groceries/list/store_done.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The card at the list's top after the user ticked a linked store's last
/// open item (job 399, SC1): the store's header and its app key are gone,
/// the card brings the key back ([storeDoneCard] says when). Flag
/// `open-store-app`; none behind the add sheet.
class const StoreDoneCard({super.key}) extends StatefulWidget {
  @override
  State<StoreDoneCard> createState() => _StoreDoneCardState();
}

class _StoreDoneCardState() extends State<StoreDoneCard> {
  Timer? _expiry;
  StoreDone? _timed;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state
            case AppLifecycleState.paused ||
                AppLifecycleState.hidden ||
                AppLifecycleState.detached) {
          if (mounted) {
            setState(() {});
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _expiry?.cancel();
    super.dispose();
  }

  /// Builds again when [done]'s card has run out.
  void _expireAt(StoreDone? done, DateTime now) {
    if (done == _timed) {
      return;
    }
    _timed = done;
    _expiry?.cancel();
    _expiry = done == null
        ? null
        : Timer(done.at.add(storeDoneShowFor).difference(now), () {
            if (mounted) {
              setState(() {});
            }
          });
  }

  @override
  Widget build(BuildContext context) {
    final on = context.select<Flags?, bool>(
      (f) => f?.isOn(openStoreAppFlag) ?? false,
    );
    final behindSheet = context.select<AddSheetCubit?, bool>(
      (c) => c?.state.open ?? false,
    );
    final cubit = context.watch<ListCubit>();
    final done = on ? cubit.storeDone() : null;
    _expireAt(done, cubit.now);
    final shown = behindSheet ? null : done;
    final switcher = AnimatedSwitcher(
      duration: hlMotion(context, HlDuration.short),
      switchInCurve: HlEasing.standard,
      switchOutCurve: HlEasing.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: switch ((shown, shown?.store.app)) {
        (final done?, final app?) => Padding(
          key: ValueKey('store-done-${done.store.id}'),
          padding: const EdgeInsets.symmetric(
            horizontal: HlSpace.s3,
            vertical: HlSpace.s2,
          ),
          child: StoreDoneView(
            store: done.store,
            app: app,
            onOpen: () => unawaited(
              openStoreApp(
                done.store,
                opener: context.read<StoreAppOpener>(),
                analytics: context.read<Analytics?>(),
                source: StoreAppSource.card,
              ),
            ),
            onDismiss: () => cubit.dismissStoreDone(done),
          ),
        ),
        _ => const SizedBox(width: double.infinity),
      },
    );
    final resize = hlMotion(context, HlDuration.medium);
    // A zero-length AnimatedSize finishes inside its own layout and asserts
    // when the card changes height with reduced motion.
    return resize == Duration.zero
        ? switcher
        : AnimatedSize(
            duration: resize,
            curve: HlEasing.standard,
            alignment: Alignment.topCenter,
            child: switcher,
          );
  }
}

/// The card itself: „Lidl ist erledigt“, „App öffnen“ below it, an X.
/// Flat like a tip card: only the button and the X are tappable.
class const StoreDoneView({
  required final Store store,
  required final RetailerApp app,
  required final VoidCallback onOpen,
  required final VoidCallback onDismiss,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Semantics(
      container: true,
      child: HlSticker(
        depth: StickerDepth.flat,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: HlSpace.s3,
            top: HlSpace.s1,
            bottom: HlSpace.s1,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: HlSpace.s3,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: HlSpace.s3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: HlSpace.s2,
                    children: [
                      Text(
                        l10n.storeDoneTitle(store.name),
                        key: const ValueKey('store-done-title'),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                      FilledButton(
                        key: const ValueKey('store-done-open'),
                        onPressed: onOpen,
                        child: Text(
                          l10n.storeDoneOpen,
                          semanticsLabel: l10n.storeAppOpen(app.name),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('store-done-close'),
                onPressed: onDismiss,
                tooltip: l10n.close,
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                icon: Icon(Icons.close, size: 20, color: t.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
