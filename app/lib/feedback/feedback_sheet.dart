import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/hex_checkbox.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/feedback/annotator.dart';
import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_cubit.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:family_groceries/feedback/screen_capture.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// From this many characters on, the form shows how many are used.
const _counterFrom = 1800;

/// Opens the feedback form over the whole app (More's row, or the shake
/// entry with [entryPoint] `shake`, the [screen] it was made on and the
/// marked-up [screenshot], job 267). The note waiting in [FeedbackCubit]
/// comes back; after a send the form closes and says thanks. True once
/// the note arrived.
Future<bool> showFeedbackSheet(
  BuildContext context, {
  FeedbackEntryPoint entryPoint = FeedbackEntryPoint.settings,
  String? screen,
  Uint8List? screenshot,
}) async {
  final cubit = context.read<FeedbackCubit>();
  final session = context.read<SessionCubit>().state;
  cubit.open(
    userId: switch (session) {
      InHousehold(:final userId) || NeedsHousehold(:final userId) => userId,
      _ => null,
    },
    screen: screen,
    screenshot: screenshot,
  );
  final messenger = Notices.of(context);
  final l10n = AppLocalizations.of(context);
  final sent = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    sheetAnimationStyle: AnimationStyle(
      curve: HlEasing.standard,
      reverseCurve: HlEasing.exit,
      duration: hlMotion(context, HlDuration.medium),
      reverseDuration: hlMotion(context, HlDuration.short),
    ),
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: FeedbackForm(entryPoint: entryPoint),
    ),
  );
  if (sent ?? false) {
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('feedback-thanks'),
        content: Text(l10n.feedbackThanks),
      ),
    );
  }
  return sent ?? false;
}

/// The form: the note, the optional kind and contact, what is attached,
/// Send (Retry after a failure). Pops `true` once the note arrived.
class const FeedbackForm({
  required final FeedbackEntryPoint entryPoint,
  super.key,
}) extends StatefulWidget {
  @override
  State<FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState() extends State<FeedbackForm> {
  late final _message = TextEditingController(
    text: context.read<FeedbackCubit>().state.message,
  );

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final cubit = context.read<FeedbackCubit>();
    final device = context.read<FeedbackDevice>();
    final analytics = context.read<Analytics>();
    final locale = Localizations.localeOf(context).languageCode;
    final householdId = switch (context.read<SessionCubit>().state) {
      InHousehold(:final household) => household.id,
      _ => null,
    };
    // The status changes at once, so a second tap meets a disabled button.
    if (!cubit.state.canSend) {
      return;
    }
    final facts = await device.read();
    final ok = await cubit.send(
      FeedbackContext(
        appVersion: facts.appVersion,
        build: facts.build,
        platform: facts.platform,
        osVersion: facts.osVersion,
        locale: locale,
        entryPoint: widget.entryPoint,
        isInternal: analytics.internalNow,
        householdId: householdId,
      ),
    );
    if (ok && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  /// Marks up the screen shown before More and attaches it.
  Future<void> _addScreenshot(ui.Image image) async {
    final cubit = context.read<FeedbackCubit>();
    final png = await annotateScreenshot(context, image);
    if (png != null) {
      cubit.attach(png);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final state = context.watch<FeedbackCubit>().state;
    // "No list items" holds unless a screenshot goes along: it can show
    // them. A screen name shows none.
    final attached = state.screenshot != null && state.sendScreenshot
        ? l10n.feedbackAttachedBasics
        : l10n.feedbackAttached;
    final fb2 = context.select<Flags?, bool>(
      (flags) => flags?.isOn(feedbackFb2Flag) ?? false,
    );
    final sending = state.status == FeedbackStatus.sending;
    final refused = state.status == FeedbackStatus.screenshotRefused;
    final failed = refused || state.status == FeedbackStatus.failed;
    final tooLong = state.tooLong
        ? l10n.feedbackTooLong(maxFeedbackLength)
        : null;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: l10n.feedbackRow,
        child: SingleChildScrollView(
          child: Column(
            key: const ValueKey('feedback-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 16,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(HlRadius.full),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          l10n.feedbackRow,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('feedback-close'),
                      tooltip: l10n.feedbackClose,
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: RoundedFields(
                  child: Semantics(
                    hint: tooLong ?? '',
                    child: TextField(
                      autofillHints: null,
                      key: const ValueKey('feedback-message'),
                      controller: _message,
                      autofocus: true,
                      readOnly: sending,
                      minLines: 4,
                      maxLines: 8,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: context.read<FeedbackCubit>().edit,
                      decoration: InputDecoration(
                        labelText: l10n.feedbackMessage,
                        hintText: l10n.feedbackMessageHint,
                        alignLabelWithHint: true,
                        error: tooLong == null ? null : FieldError(tooLong),
                      ),
                    ),
                  ),
                ),
              ),
              if (state.length >= _counterFrom)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text(
                    l10n.feedbackCounter(state.length, maxFeedbackLength),
                    key: const ValueKey('feedback-counter'),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      color: state.tooLong
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Text(
                  l10n.feedbackCategories,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (category, label) in [
                      (FeedbackCategory.bug, l10n.feedbackCategoryBug),
                      (FeedbackCategory.idea, l10n.feedbackCategoryIdea),
                      (FeedbackCategory.other, l10n.feedbackCategoryOther),
                    ])
                      ChoiceChip(
                        key: ValueKey('feedback-category-${category.name}'),
                        label: Text(label),
                        selected: state.category == category,
                        onSelected: sending
                            ? null
                            : (_) =>
                                  context.read<FeedbackCubit>().pick(category),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: HexCheckboxListTile(
                  key: const ValueKey('feedback-contact'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(l10n.feedbackContact),
                  value: state.contactOk,
                  onChanged: sending
                      ? null
                      : (on) =>
                            context.read<FeedbackCubit>().setContact(ok: on),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  '${l10n.feedbackAttachedTitle} $attached',
                  key: const ValueKey('feedback-attached'),
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (state.screen case final screen?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                  child: HexSwitchTile(
                    key: const ValueKey('feedback-send-screen'),
                    title: Text(l10n.feedbackScreenName),
                    subtitle: Text(screen),
                    value: state.sendScreen,
                    onChanged: sending
                        ? null
                        : (on) => context.read<FeedbackCubit>().setSendScreen(
                            on: on,
                          ),
                  ),
                ),
              if (state.screenshot case final png?) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                  child: HexSwitchTile(
                    key: const ValueKey('feedback-send-screenshot'),
                    title: Text(l10n.feedbackScreenshot),
                    subtitle: Text(l10n.feedbackScreenshotNote),
                    isThreeLine: true,
                    value: state.sendScreenshot,
                    onChanged: sending
                        ? null
                        : (on) => context
                              .read<FeedbackCubit>()
                              .setSendScreenshot(on: on),
                  ),
                ),
                _Preview(png: png, sent: state.sendScreenshot),
              ] else if (fb2 &&
                  widget.entryPoint == FeedbackEntryPoint.settings &&
                  context.read<ScreenCapture?>()?.beforeMore != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: const ValueKey('feedback-add-screenshot'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: sending
                          ? null
                          : () {
                              // Read now: leaving More disposes it.
                              final shot = context
                                  .read<ScreenCapture?>()
                                  ?.beforeMore;
                              if (shot != null) {
                                unawaited(_addScreenshot(shot));
                              }
                            },
                      icon: const Icon(Icons.screenshot_outlined),
                      label: Text(l10n.feedbackAddScreenshot),
                    ),
                  ),
                ),
              if (failed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      refused
                          ? l10n.feedbackScreenshotRefused
                          : l10n.feedbackFailed,
                      key: const ValueKey('feedback-error'),
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  14,
                  20,
                  16 + math.max(0, media.padding.bottom - keyboard),
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton(
                    key: ValueKey(failed ? 'feedback-retry' : 'feedback-send'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.standard,
                      minimumSize: const Size(132, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      textStyle: const TextStyle(
                        fontFamily: HlFont.sans,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: state.canSend ? () => unawaited(_send()) : null,
                    child: sending
                        ? Semantics(
                            label: l10n.feedbackSending,
                            child: const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                          )
                        : Text(failed ? l10n.feedbackRetry : l10n.feedbackSend),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The screenshot exactly as it would be stored; faded while switched off.
class const _Preview({required final Uint8List png, required final bool sent})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: AnimatedOpacity(
          opacity: sent ? 1 : 0.35,
          duration: hlMotion(context, HlDuration.short),
          child: Semantics(
            image: true,
            label: l10n.feedbackScreenshotPreview,
            child: Container(
              key: const ValueKey('feedback-screenshot-preview'),
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 200),
              decoration: BoxDecoration(
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(HlRadius.s),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(
                png,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                // Named once, by the Semantics around it.
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
