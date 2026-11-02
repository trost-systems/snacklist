import 'dart:async';

import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/tips/tips.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The tip on screen, or null. Picked once per List tab: a dismissed tip's
/// successor waits for the next start, so the user never meets a stack of
/// cards (DECISIONS, Job 80).
class TipsCubit(
  final TipStore _store, {
  required final String userId,
  required final TipSurface surface,
  final Future<String?> Function() appVersion = _appVersion,
  final List<Tip>? queue,
}) extends Cubit<Tip?> {
  this : super(null);

  final List<Tip> _queue = queue ?? tips;
  Set<String> _dismissed = const {};

  Future<void> load() async {
    _dismissed = await _store.dismissedTips(userId);
    final version = await appVersion();
    if (!isClosed) {
      emit(
        nextTip(
          _queue,
          surface: surface,
          appVersion: version,
          dismissed: _dismissed,
        ),
      );
    }
  }

  void dismiss() {
    if (state case final tip?) {
      _dismissed = {..._dismissed, tip.id};
      unawaited(_store.saveDismissedTips(userId, _dismissed));
      emit(null);
    }
  }
}

Future<String?> _appVersion() async {
  try {
    return (await PackageInfo.fromPlatform()).version;
  } on Object {
    return null;
  }
}

/// The List tab's tip, at the top of the list. Shows once the list has items
/// and the gesture card is gone: the first empty list stays clean. Needs a
/// [ListCubit] above it; without a [TipStore] there is none.
class const ListTips({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final store = context.read<TipStore?>();
    if (store == null) {
      return const SizedBox.shrink();
    }
    return BlocProvider(
      create: (context) {
        final cubit = TipsCubit(
          store,
          userId: context.read<ListCubit>().userId,
          surface: TipSurface.current(
            web: kIsWeb,
            platform: defaultTargetPlatform,
          ),
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: const _TipSlot(),
    );
  }
}

class const _TipSlot() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tip = context.watch<TipsCubit>().state;
    // The same test as the list's empty state: an active item shows.
    final shown = context.select<ListCubit, bool>(
      (c) =>
          c.state.prefs.hintDismissed &&
          c.state.items.values.any((i) => i.status == ItemStatus.active),
    );
    return AnimatedSize(
      duration: hlMotion(context, HlDuration.medium),
      curve: HlEasing.standard,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: hlMotion(context, HlDuration.short),
        switchInCurve: HlEasing.standard,
        switchOutCurve: HlEasing.exit,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: tip != null && shown
            ? Padding(
                key: ValueKey(tip.id),
                padding: const EdgeInsets.symmetric(
                  horizontal: HlSpace.s3,
                  vertical: HlSpace.s2,
                ),
                child: TipCard(
                  tip: tip,
                  onDismiss: context.read<TipsCubit>().dismiss,
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}

/// One tip: icon, title and text, and an X that hides it for good.
class const TipCard({
  required final Tip tip,
  required final VoidCallback onDismiss,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = HummlistColors.of(Theme.of(context).brightness);
    return Semantics(
      key: ValueKey('tip-${tip.id}'),
      container: true,
      child: HlSticker(
        depth: StickerDepth.s,
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
              Padding(
                padding: const EdgeInsets.only(top: HlSpace.s3),
                child: Icon(tip.icon, size: 22, color: t.brand),
              ),
              Expanded(
                child: MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: HlSpace.s3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: HlSpace.s1,
                      children: [
                        Text(
                          tip.title(l10n),
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                        Text(
                          tip.body(l10n),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: t.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('tip-dismiss'),
                onPressed: onDismiss,
                tooltip: l10n.tipDismiss,
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
