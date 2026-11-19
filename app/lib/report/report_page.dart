import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/guides.dart';
import 'package:family_groceries/core/legal_links.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/hex_checkbox.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/feedback/annotator.dart';
import 'package:family_groceries/feedback/screen_capture.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/report/report_cubit.dart';
import 'package:family_groceries/report/report_picker.dart';
import 'package:family_groceries/report/report_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the report form over the whole app (job 281), with the places of
/// the household shown under [context]; Done or ✕ come back here.
Future<void> openReportForm(BuildContext context) {
  final places = ReportPlaces.of(context);
  final repository = context.read<ReportRepository>();
  final locale = Localizations.localeOf(context).languageCode;
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BlocProvider(
        create: (_) => ReportCubit(
          repository,
          locale: locale,
          reporter: repository.reporter(),
        ),
        child: ReportPage(places: places),
      ),
    ),
  );
}

/// „Inhalt melden“ with what it is for below: in Feedback & ideas under
/// „An Snacklist Support schreiben“, else on top of the feedback form.
class const ReportEntry({required final VoidCallback onPressed, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: HlSpace.s1,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('report-entry'),
          onPressed: onPressed,
          icon: const Icon(Icons.flag_outlined),
          label: Text(l10n.reportContent),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HlSpace.s2),
          child: Text(
            l10n.reportEntryHint,
            key: const ValueKey('report-entry-hint'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: t.textMuted),
          ),
        ),
      ],
    );
  }
}

/// The report form (Legal B.4), and once sent the confirmation with the
/// report's number.
class const ReportPage({required final ReportPlaces places, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = context.select<ReportCubit, ReportStatus>(
      (cubit) => cubit.state.status,
    );
    // Closed while sending, the report could arrive with its number unseen.
    return PopScope(
      canPop: status is! ReportSending,
      child: Scaffold(
        appBar: AppBar(
          // Sent, Done is the way back.
          automaticallyImplyLeading:
              status is! ReportSending && status is! ReportSent,
          title: Text(l10n.reportContent),
        ),
        body: switch (status) {
          final ReportSent sent => _Sent(sent),
          _ => _Form(places),
        },
      ),
    );
  }
}

class const _Form(final ReportPlaces places) extends StatefulWidget {
  @override
  State<_Form> createState() => _FormState();
}

class _FormState() extends State<_Form> {
  late final _cubit = context.read<ReportCubit>();
  late final _reason = TextEditingController(text: _cubit.state.reason);
  late final _name = TextEditingController(text: _cubit.state.name);
  late final _email = TextEditingController(text: _cubit.state.email);
  late final _elsewhere = TextEditingController();
  final _elsewhereFocus = FocusNode();

  /// The parts Send checks, to scroll the first missing one into view.
  final _fields = {for (final field in ReportField.values) field: GlobalKey()};

  @override
  void dispose() {
    _reason.dispose();
    _name.dispose();
    _email.dispose();
    _elsewhere.dispose();
    _elsewhereFocus.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final picked = await showReportPicker(context, widget.places);
    if (picked == null || !mounted) {
      return;
    }
    _cubit.place(picked);
    // Somewhere else again keeps its description; from a picked place it
    // starts empty.
    if (_cubit.state.target case ElsewhereTarget(:final text)) {
      _elsewhere.text = text;
      _elsewhereFocus.requestFocus();
    }
  }

  /// Marks up the screen shown before More, with the cover tool, and
  /// attaches it.
  Future<void> _attach(ui.Image image) async {
    final png = await annotateScreenshot(context, image, forReport: true);
    if (png != null) {
      _cubit.attach(png);
    }
  }

  Future<void> _send() async {
    final scroll = hlMotion(context, HlDuration.short);
    final sent = await _cubit.send();
    if (sent || !mounted) {
      return;
    }
    final first = _cubit.state.missing.firstOrNull;
    final field = _fields[first]?.currentContext;
    if (field != null && field.mounted) {
      await Scrollable.ensureVisible(
        field,
        duration: scroll,
        curve: HlEasing.standard,
        alignment: 0.1,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<ReportCubit>().state;
    final language = Localizations.localeOf(context).languageCode;
    final sending = state.status is ReportSending;
    final missing = state.tried ? state.missing : const <ReportField>[];
    String? problem(ReportField field) => !missing.contains(field)
        ? null
        : switch (field) {
            ReportField.category => l10n.reportErrorAbout,
            ReportField.where => l10n.reportErrorWhere,
            ReportField.reason when state.reasonLength > maxReportLength =>
              l10n.reportErrorLong,
            ReportField.reason => l10n.reportErrorShort(
              minReportLength - state.reasonLength,
            ),
            ReportField.email => l10n.reportErrorEmail,
            ReportField.goodFaith => l10n.reportErrorGoodFaith,
          };
    final help = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: t.textMuted);
    Widget helpText(String text) => Padding(
      padding: const EdgeInsets.only(bottom: HlSpace.s2),
      child: Text(text, style: help),
    );
    Widget error(ReportField field) => switch (problem(field)) {
      final message? => Padding(
        padding: const EdgeInsets.only(top: HlSpace.s1),
        child: Semantics(
          liveRegion: true,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: scheme.error, fontSize: 13),
            child: FieldError(
              message,
              key: ValueKey('report-error-${field.name}'),
            ),
          ),
        ),
      ),
      null => const SizedBox.shrink(),
    };
    final screenshot = state.screenshot;
    final capture =
        context.select<Flags?, bool>(
          (flags) => flags?.isOn(feedbackFb2Flag) ?? false,
        )
        ? context.read<ScreenCapture?>()?.beforeMore
        : null;
    final failure = switch (state.status) {
      ReportFailed(error: ReportRateLimited()) => l10n.reportFailedRateLimited,
      ReportFailed(error: ReportOffline()) => l10n.reportFailedOffline,
      ReportFailed(error: ReportRefused()) => l10n.reportFailedUnavailable,
      ReportFailed(error: ReportScreenshotTooLarge()) =>
        l10n.reportFailedScreenshotTooLarge,
      _ => null,
    };
    final privacy = privacyPolicyUrl(language)
        .replace(fragment: language == 'de' ? 'meldungen' : 'reports');
    // Every part built, so Send can scroll to the first one missing.
    return SingleChildScrollView(
      key: const ValueKey('report-form'),
      padding: EdgeInsets.fromLTRB(
        HlSpace.s4,
        HlSpace.s2,
        HlSpace.s4,
        HlSpace.s5 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.reportIntro,
            key: const ValueKey('report-intro'),
            style: HlType.body.copyWith(color: t.text, height: 1.45),
          ),
          _Section(
            key: _fields[ReportField.category],
            title: l10n.reportAbout,
            tag: l10n.reportRequired,
            children: [
              RadioGroup<ReportCategory>(
                groupValue: state.category,
                onChanged: (category) {
                  if (category != null && !sending) {
                    _cubit.pick(category);
                    // The kind can empty or prefill name and e-mail.
                    _name.text = _cubit.state.name;
                    _email.text = _cubit.state.email;
                  }
                },
                // The hexes in line with the questions, as the check box.
                child: ListTileTheme(
                  contentPadding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final category in ReportCategory.values)
                        HexRadioTile<ReportCategory>(
                          key: ValueKey('report-category-${category.wire}'),
                          value: category,
                          title: Text(_categoryLabel(l10n, category)),
                        ),
                    ],
                  ),
                ),
              ),
              error(ReportField.category),
            ],
          ),
          _Section(
            key: _fields[ReportField.where],
            title: l10n.reportWhere,
            tag: l10n.reportRequired,
            children: [
              helpText(switch (state.target) {
                null => l10n.reportWhereChooseHelp,
                ElsewhereTarget() => l10n.reportWhereElsewhereHelp,
                _ => l10n.reportWhereHelp,
              }),
              switch (state.target) {
                final ElsewhereTarget _ => RoundedFields(
                  child: Semantics(
                    label: l10n.reportWhere,
                    child: TextField(
                      key: const ValueKey('report-elsewhere'),
                      autofillHints: null,
                      controller: _elsewhere,
                      focusNode: _elsewhereFocus,
                      readOnly: sending,
                      minLines: 2,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: const [
                        _CodePointLimit(maxElsewhereLength),
                      ],
                      onChanged: _cubit.describe,
                    ),
                  ),
                ),
                final ReportTarget target? => _Picked(target),
                null => const SizedBox.shrink(),
              },
              Padding(
                padding: const EdgeInsets.only(top: HlSpace.s2),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    key: const ValueKey('report-where-choose'),
                    onPressed: sending ? null : () => unawaited(_choose()),
                    icon: Icon(
                      state.target == null ? Icons.search : Icons.swap_horiz,
                    ),
                    label: Text(
                      state.target == null
                          ? l10n.reportWhereChoose
                          : l10n.reportWhereChange,
                    ),
                  ),
                ),
              ),
              error(ReportField.where),
            ],
          ),
          _Section(
            key: _fields[ReportField.reason],
            title: l10n.reportWhy,
            tag: l10n.reportRequired,
            children: [
              helpText(l10n.reportWhyHelp),
              RoundedFields(
                child: Semantics(
                  label: l10n.reportWhy,
                  child: TextField(
                    key: const ValueKey('report-reason'),
                    autofillHints: null,
                    controller: _reason,
                    readOnly: sending,
                    minLines: 5,
                    maxLines: 12,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: _cubit.write,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: HlSpace.s1),
                child: Text(
                  l10n.reportCounter(state.reasonLength, maxReportLength),
                  key: const ValueKey('report-counter'),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    color: state.reasonLength > maxReportLength
                        ? scheme.error
                        : t.textMuted,
                  ),
                ),
              ),
              error(ReportField.reason),
            ],
          ),
          KeyedSubtree(
            key: _fields[ReportField.email],
            child: state.contactShown
                ? Padding(
                    padding: const EdgeInsets.only(top: HlSpace.s4),
                    child: Column(
                      key: const ValueKey('report-contact'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: HlSpace.s3,
                      children: [
                        LabeledField(
                          label:
                              '${l10n.reportName} (${l10n.reportRecommended})',
                          field: TextField(
                            key: const ValueKey('report-name'),
                            autofillHints: null,
                            controller: _name,
                            readOnly: sending,
                            textCapitalization: TextCapitalization.words,
                            inputFormatters: const [
                              _CodePointLimit(maxReporterNameLength),
                            ],
                            onChanged: _cubit.setName,
                          ),
                        ),
                        LabeledField(
                          label:
                              '${l10n.reportEmail} (${l10n.reportRecommended})',
                          field: Semantics(
                            hint: problem(ReportField.email) ?? '',
                            child: TextField(
                              key: const ValueKey('report-email'),
                              autofillHints: null,
                              controller: _email,
                              readOnly: sending,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: _cubit.setEmail,
                              decoration: InputDecoration(
                                error: switch (problem(ReportField.email)) {
                                  final message? => FieldError(message),
                                  null => null,
                                },
                              ),
                            ),
                          ),
                        ),
                        Text(
                          state.category == ReportCategory.csam
                              ? l10n.reportCsamNote
                              : l10n.reportContactHelp,
                          key: const ValueKey('report-contact-help'),
                          style: help,
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: HlSpace.s4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: HlSpace.s2,
                      children: [
                        Text(
                          l10n.reportCsamNote,
                          key: const ValueKey('report-csam-note'),
                          style: HlType.label.copyWith(color: t.text),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('report-csam-add'),
                          onPressed: sending ? null : _cubit.showContact,
                          icon: const Icon(Icons.person_outline),
                          label: Text(l10n.reportCsamAdd),
                        ),
                      ],
                    ),
                  ),
          ),
          // No screenshot of child sexual abuse material (Legal N-287).
          if (state.category != ReportCategory.csam &&
              (screenshot != null || capture != null))
            Padding(
              padding: const EdgeInsets.only(top: HlSpace.s4),
              child: Column(
                key: const ValueKey('report-screenshot'),
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: HlSpace.s2,
                children: [
                  if (screenshot != null)
                    _Shot(
                      png: screenshot,
                      onRemove: sending ? null : _cubit.removeScreenshot,
                    )
                  else
                    OutlinedButton.icon(
                      key: const ValueKey('report-screenshot-add'),
                      onPressed: sending
                          ? null
                          : () {
                              // Read now: leaving More disposes it.
                              final shot = context
                                  .read<ScreenCapture?>()
                                  ?.beforeMore;
                              if (shot != null) {
                                unawaited(_attach(shot));
                              }
                            },
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(l10n.reportScreenshot),
                    ),
                  Text(l10n.reportScreenshotHelp, style: help),
                ],
              ),
            ),
          Padding(
            key: _fields[ReportField.goodFaith],
            padding: const EdgeInsets.only(top: HlSpace.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HexCheckboxListTile(
                  key: const ValueKey('report-good-faith'),
                  contentPadding: EdgeInsets.zero,
                  title: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: l10n.reportGoodFaith),
                        const TextSpan(text: ' '),
                        TextSpan(
                          text: '(${l10n.reportRequired})',
                          style: HlType.label.copyWith(
                            fontSize: 13,
                            color: t.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  value: state.goodFaith,
                  onChanged: sending
                      ? null
                      : (on) => _cubit.confirm(goodFaith: on),
                ),
                error(ReportField.goodFaith),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: HlSpace.s3),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${l10n.reportPrivacyLead} ', style: help),
                LegalLink(
                  key: const ValueKey('report-privacy'),
                  url: privacy,
                  builder: (context, open) => InkWell(
                    onTap: open,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Align(
                        widthFactor: 1,
                        child: Text(
                          l10n.reportPrivacyLink,
                          style: help?.copyWith(
                            color: t.accent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(top: HlSpace.s3),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  failure,
                  key: const ValueKey('report-failed'),
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: HlSpace.s4),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const ValueKey('report-send'),
                style: _bigButton,
                onPressed: sending ? null : () => unawaited(_send()),
                child: sending
                    ? Semantics(
                        label: l10n.feedbackSending,
                        child: const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : Text(l10n.reportSend),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _bigButton = FilledButton.styleFrom(
  visualDensity: VisualDensity.standard,
  minimumSize: const Size(132, 52),
  padding: const EdgeInsets.symmetric(horizontal: 28),
  textStyle: const TextStyle(
    fontFamily: HlFont.sans,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  ),
);

String _categoryLabel(AppLocalizations l10n, ReportCategory category) =>
    switch (category) {
      ReportCategory.hate => l10n.reportCategoryHate,
      ReportCategory.personalRights => l10n.reportCategoryPersonalRights,
      ReportCategory.ip => l10n.reportCategoryIp,
      ReportCategory.csam => l10n.reportCategoryCsam,
      ReportCategory.danger => l10n.reportCategoryDanger,
      ReportCategory.other => l10n.reportCategoryOther,
    };

/// A question: its [title] with the [tag] („Pflicht“) after it, then
/// [children].
class const _Section({
  required final String title,
  required final String tag,
  required final List<Widget> children,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.only(top: HlSpace.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: HlSpace.s2),
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: HlType.label.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: '($tag)',
                      style: HlType.label.copyWith(
                        fontSize: 13,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// The picked item, list or household: its kind, its name in quotes and
/// where it is.
class const _Picked(final ReportTarget target) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final (kind, name, where) = switch (target) {
      ItemTarget(:final name, :final list?, :final household) => (
        l10n.reportKindItem,
        name,
        l10n.reportItemContext(list, household),
      ),
      ItemTarget(:final name, :final household) => (
        l10n.reportKindItem,
        name,
        household,
      ),
      ListTarget(:final name, :final household) => (
        l10n.reportKindList,
        name,
        household,
      ),
      HouseholdTarget(:final name) => (l10n.reportKindHousehold, name, null),
      ElsewhereTarget() => (l10n.reportPickerElsewhere, '', null),
    };
    return Container(
      key: const ValueKey('report-picked'),
      padding: const EdgeInsets.all(HlSpace.s3),
      decoration: BoxDecoration(
        color: t.accentSoft,
        border: Border.all(color: t.border, width: HlBorder.width),
        borderRadius: BorderRadius.circular(HlRadius.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(kind, style: TextStyle(fontSize: 13, color: t.textMuted)),
          Text(
            l10n.reportQuoted(name),
            style: HlType.label.copyWith(fontSize: 17, color: t.text),
          ),
          if (where != null)
            Text(where, style: TextStyle(fontSize: 13, color: t.textMuted)),
        ],
      ),
    );
  }
}

/// The attached screenshot: a preview, „Screenshot angehängt“ and Remove.
class const _Shot({
  required final Uint8List png,
  required final VoidCallback? onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Row(
      spacing: HlSpace.s3,
      children: [
        Semantics(
          image: true,
          label: l10n.feedbackScreenshotPreview,
          child: Container(
            key: const ValueKey('report-screenshot-preview'),
            constraints: const BoxConstraints(maxHeight: 120, maxWidth: 80),
            decoration: BoxDecoration(
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(HlRadius.s),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(
              png,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            ),
          ),
        ),
        Expanded(
          child: Text(
            l10n.reportScreenshotAttached,
            style: HlType.label.copyWith(color: t.text),
          ),
        ),
        OutlinedButton(
          key: const ValueKey('report-screenshot-remove'),
          onPressed: onRemove,
          child: Text(l10n.reportScreenshotRemove),
        ),
      ],
    );
  }
}

/// „Meldung gesendet“: the number to copy, Legal's confirmation, where the
/// confirmation mail goes, and Done back to where the report started.
class const _Sent(final ReportSent sent) extends StatefulWidget {
  @override
  State<_Sent> createState() => _SentState();
}

class _SentState() extends State<_Sent> {
  var _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.sent.ref));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final ReportSent(:ref, :email) = widget.sent;
    final help = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: t.textMuted);
    return ListView(
      key: const ValueKey('report-sent'),
      padding: EdgeInsets.fromLTRB(
        HlSpace.s4,
        HlSpace.s4,
        HlSpace.s4,
        HlSpace.s5 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Center(
          child: PointyHex(
            face: t.mintSoft,
            contour: t.border,
            size: 64,
            child: Icon(Icons.check_circle_outline, size: 32, color: t.text),
          ),
        ),
        const SizedBox(height: HlSpace.s3),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            l10n.reportSentTitle,
            textAlign: TextAlign.center,
            style: HlType.title.copyWith(color: t.text),
          ),
        ),
        const SizedBox(height: HlSpace.s4),
        Container(
          padding: const EdgeInsets.all(HlSpace.s4),
          decoration: BoxDecoration(
            border: Border.all(color: t.border, width: HlBorder.width),
            borderRadius: BorderRadius.circular(HlRadius.m),
          ),
          child: Column(
            spacing: HlSpace.s2,
            children: [
              Text(l10n.reportNumber, style: help),
              SelectableText(
                ref,
                key: const ValueKey('report-ref'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: HlFont.sans,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: t.text,
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('report-copy'),
                onPressed: () => unawaited(_copy()),
                icon: Icon(_copied ? Icons.check : Icons.content_copy),
                label: Text(
                  _copied ? l10n.reportCopied : l10n.reportCopyNumber,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HlSpace.s4),
        Text(
          l10n.reportThanks(ref),
          key: const ValueKey('report-thanks'),
          style: HlType.body.copyWith(color: t.text, height: 1.45),
        ),
        const SizedBox(height: HlSpace.s3),
        Text(
          switch (email) {
            final email? => l10n.reportMailed(email),
            null => l10n.reportNotMailed,
          },
          key: const ValueKey('report-mail'),
          style: help,
        ),
        const SizedBox(height: HlSpace.s3),
        Text(l10n.reportNotInNotes, style: help),
        const SizedBox(height: HlSpace.s4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: const ValueKey('report-done'),
            style: _bigButton,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.reportDone),
          ),
        ),
      ],
    );
  }
}

/// Stops a field at [max] code points, as the server counts; Flutter's
/// own limit counts characters, which may be several code points each.
class const _CodePointLimit(final int max) extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = firstCodePoints(newValue.text, max);
    if (text == newValue.text) {
      return newValue;
    }
    final selection = newValue.selection;
    return TextEditingValue(
      text: text,
      selection: selection.copyWith(
        baseOffset: math.min(selection.baseOffset, text.length),
        extentOffset: math.min(selection.extentOffset, text.length),
      ),
    );
  }
}
