import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/guides.dart';
import 'package:family_groceries/core/legal_links.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/feedback/feedback_inbox.dart';
import 'package:family_groceries/feedback/feedback_note.dart';
import 'package:family_groceries/feedback/feedback_sheet.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/report/report_page.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Feedback & Ideen (job 268, FB4): write to Snacklist Support, report
/// content (job 281, flag `report-content-entry`), the user's own notes
/// with their status, and the listed ideas to +1.
class const FeedbackHubPage({super.key}) extends StatefulWidget {
  @override
  State<FeedbackHubPage> createState() => _FeedbackHubPageState();
}

class _FeedbackHubPageState() extends State<FeedbackHubPage> {
  Future<void> _write() async {
    final sent = await showFeedbackSheet(context);
    if (sent && mounted) {
      await refreshInbox(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final state = context.watch<FeedbackInbox>().state;
    final language = Localizations.localeOf(context).languageCode;
    final report = context.select<Flags?, bool>(
      (flags) => flags?.isOn(reportContentEntryFlag) ?? false,
    );
    const side = EdgeInsets.symmetric(horizontal: HlSpace.s4);
    return InboxLoader(
      child: ListView(
        key: const ValueKey('feedback-hub'),
        padding: EdgeInsets.only(
          top: HlSpace.s4,
          bottom: HlSpace.s5 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: side,
            child: FilledButton.icon(
              key: const ValueKey('feedback-write'),
              onPressed: () => unawaited(_write()),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.feedbackWrite),
            ),
          ),
          if (report)
            Padding(
              padding: side.copyWith(top: HlSpace.s3),
              child: ReportEntry(
                onPressed: () => unawaited(openReportForm(context)),
              ),
            ),
          HlSectionLabel(l10n.feedbackYourNotes),
          if (state.failed)
            _Retry(onRetry: () => unawaited(refreshInbox(context)))
          else if (state.notes == null)
            const Padding(
              padding: EdgeInsets.all(HlSpace.s5),
              child: Center(child: CircularProgressIndicator()),
            ),
          switch (state.notes) {
            null => const SizedBox.shrink(),
            [] => Padding(
              padding: const EdgeInsets.fromLTRB(
                HlSpace.s5,
                HlSpace.s2,
                HlSpace.s5,
                0,
              ),
              child: Text(
                l10n.feedbackNoNotes,
                key: const ValueKey('feedback-no-notes'),
                style: HlType.body.copyWith(color: t.textMuted),
              ),
            ),
            final notes => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      HlSpace.s4,
                      HlSpace.s2,
                      HlSpace.s4,
                      HlSpace.s1,
                    ),
                    child: _NoteCard(note),
                  ),
              ],
            ),
          },
          if (state.ideas.isNotEmpty) ...[
            HlSectionLabel(l10n.feedbackIdeas),
            HlGroup(
              top: HlSpace.s2,
              children: [
                for (final idea in state.ideas)
                  _IdeaRow(idea, title: idea.title(language)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HlSpace.s5,
                HlSpace.s3,
                HlSpace.s5,
                0,
              ),
              child: Text(
                l10n.feedbackIdeasNote,
                key: const ValueKey('feedback-ideas-note'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: t.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Konnte nicht geladen werden." with a retry.
class const _Retry({required final VoidCallback onRetry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(HlSpace.s5, 0, HlSpace.s4, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: HlSpace.s2,
        children: [
          Text(l10n.feedbackLoadFailed, key: const ValueKey('feedback-failed')),
          TextButton(
            key: const ValueKey('feedback-retry-load'),
            onPressed: onRetry,
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }
}

/// A note in the list: its status, a marker while an answer is unopened,
/// and the start of its text. Opens the note.
class const _NoteCard(final FeedbackNote note) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return HlSticker(
      key: ValueKey('feedback-note-${note.id}'),
      depth: StickerDepth.s,
      child: Material(
        type: MaterialType.transparency,
        child: FocusRingInkWell(
          outline: HlSticker.innerOutline,
          onTap: () => context.go(feedbackNotePath(note.id)),
          child: Padding(
            padding: const EdgeInsets.all(HlSpace.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: HlSpace.s2,
              children: [
                Wrap(
                  spacing: HlSpace.s2,
                  runSpacing: HlSpace.s1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    NoteStatusChip(note),
                    if (note.unread)
                      _NewMarker(
                        note.reply == null
                            ? l10n.feedbackNewStatus
                            : l10n.feedbackNewReply,
                      ),
                  ],
                ),
                Text(
                  note.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: HlType.body.copyWith(color: t.text, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A honey dot and "Neue Antwort".
class const _NewMarker(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Row(
      key: const ValueKey('feedback-note-new'),
      mainAxisSize: MainAxisSize.min,
      spacing: HlSpace.s1,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: ShapeDecoration(
            color: t.honey,
            shape: HexBorder(side: BorderSide(color: t.edge)),
          ),
        ),
        Flexible(
          child: Text(
            text,
            style: HlType.label.copyWith(color: t.text, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// Where a note stands, on a small hex.
class const NoteStatusChip(final FeedbackNote note, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final (text, icon, face) = switch (note) {
      FeedbackNote(status: NoteStatus.sent) => (
        l10n.feedbackStatusSent,
        Icons.schedule,
        t.surfaceSunken,
      ),
      FeedbackNote(status: NoteStatus.read) => (
        l10n.feedbackStatusRead,
        Icons.visibility_outlined,
        t.accentSoft,
      ),
      FeedbackNote(status: NoteStatus.planned) => (
        l10n.feedbackStatusPlanned,
        Icons.event_note_outlined,
        t.honeySoft,
      ),
      FeedbackNote(status: NoteStatus.fixed, fixedIn: final version?) => (
        l10n.feedbackStatusFixedIn(version),
        Icons.check_circle_outline,
        t.mintSoft,
      ),
      FeedbackNote(status: NoteStatus.fixed) => (
        l10n.feedbackStatusFixed,
        Icons.check_circle_outline,
        t.mintSoft,
      ),
    };
    const height = 28.0;
    return Container(
      key: const ValueKey('feedback-status'),
      constraints: const BoxConstraints(minHeight: height),
      padding: EdgeInsets.symmetric(
        horizontal: hexTextInset(height),
        vertical: 2,
      ),
      decoration: ShapeDecoration(
        color: face,
        shape: HexBorder(side: BorderSide(color: t.border)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: HlSpace.s1,
        children: [
          Icon(icon, size: 16, color: t.text),
          Flexible(
            child: Text(
              text,
              style: HlType.label.copyWith(color: t.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// An idea: its title and status, and the household's +1.
class const _IdeaRow(final FeedbackIdea idea, {required final String title})
    extends StatelessWidget {
  Future<void> _vote(BuildContext context) async {
    final notices = Notices.of(context);
    final failed = AppLocalizations.of(context).feedbackVoteFailed;
    final ok = await context.read<FeedbackInbox>().vote(idea, on: !idea.voted);
    if (!ok) {
      notices.showSnackBar(
        SnackBar(
          key: const ValueKey('feedback-vote-failed'),
          content: Text(failed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    void onPressed() => unawaited(_vote(context));
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(72, HlSize.target)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: hexTextInset(HlSize.target)),
      ),
    );
    final icon = Icon(
      idea.voted ? Icons.thumb_up : Icons.thumb_up_outlined,
      size: 18,
    );
    final count = Text('${idea.votes}');
    return Padding(
      key: ValueKey('feedback-idea-${idea.id}'),
      padding: const EdgeInsets.fromLTRB(
        HlSpace.s4,
        HlSpace.s3,
        HlSpace.s3,
        HlSpace.s3,
      ),
      child: Row(
        spacing: HlSpace.s3,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(title, style: HlType.label.copyWith(color: t.text)),
                Text(
                  switch (idea.status) {
                    IdeaStatus.considering => l10n.feedbackIdeaConsidering,
                    IdeaStatus.planned => l10n.feedbackStatusPlanned,
                  },
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
          Semantics(
            key: ValueKey('feedback-vote-${idea.id}'),
            container: true,
            button: true,
            toggled: idea.voted,
            label: l10n.feedbackVote(title, idea.votes),
            excludeSemantics: true,
            onTap: onPressed,
            child: idea.voted
                ? FilledButton.icon(
                    style: style,
                    onPressed: onPressed,
                    icon: icon,
                    label: count,
                  )
                : OutlinedButton.icon(
                    style: style,
                    onPressed: onPressed,
                    icon: icon,
                    label: count,
                  ),
          ),
        ],
      ),
    );
  }
}

/// One note (`/more/feedback/<id>`): its status, the user's text and,
/// once there is one, Snacklist Support's reply; a fixed note links to its
/// version's changelog. Opening it marks its answer seen.
class const FeedbackNotePage(final String id, {super.key})
    extends StatefulWidget {
  @override
  State<FeedbackNotePage> createState() => _FeedbackNotePageState();
}

class _FeedbackNotePageState() extends State<FeedbackNotePage> {
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final inbox = context.read<FeedbackInbox>();
    if (inbox.state.notes == null) {
      await refreshInbox(context);
    }
    final unread =
        inbox.state.notes?.any((n) => n.id == widget.id && n.unread) ?? false;
    if (unread && mounted) {
      await inbox.markSeen(widget.id);
      if (mounted) {
        await refreshInbox(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<FeedbackInbox>().state;
    final note = state.notes?.where((n) => n.id == widget.id).firstOrNull;
    return switch ((note, state.notes)) {
      (final note?, _) => _Thread(note),
      (null, null) when state.failed => Align(
        alignment: AlignmentDirectional.topStart,
        child: Padding(
          padding: const EdgeInsets.only(top: HlSpace.s4),
          child: _Retry(onRetry: () => unawaited(refreshInbox(context))),
        ),
      ),
      (null, null) => const Center(child: CircularProgressIndicator()),
      (null, _) => Padding(
        padding: const EdgeInsets.all(HlSpace.s5),
        child: Text(
          l10n.feedbackNoteMissing,
          key: const ValueKey('feedback-note-missing'),
        ),
      ),
    };
  }
}

class const _Thread(final FeedbackNote note) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    String when(DateTime time) =>
        l10n.feedbackWhen(time.toLocal(), time.toLocal());
    final written = when(note.createdAt);
    return ListView(
      key: ValueKey('feedback-thread-${note.id}'),
      padding: EdgeInsets.fromLTRB(
        HlSpace.s4,
        HlSpace.s4,
        HlSpace.s4,
        HlSpace.s5 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: NoteStatusChip(note),
        ),
        const SizedBox(height: HlSpace.s3),
        _Bubble(
          key: const ValueKey('feedback-note-message'),
          mine: true,
          text: note.message,
          footer: note.status == NoteStatus.sent
              ? written
              : l10n.feedbackWhenRead(written),
        ),
        if (note.reply case final reply?) ...[
          const SizedBox(height: HlSpace.s3),
          _Bubble(
            key: const ValueKey('feedback-note-reply'),
            mine: false,
            text: reply,
            footer: l10n.feedbackReplyFrom(
              when(note.repliedAt ?? note.answeredAt ?? note.createdAt),
            ),
          ),
        ],
        if (note case FeedbackNote(
          status: NoteStatus.fixed,
          fixedIn: final version?,
        )) ...[
          const SizedBox(height: HlSpace.s3),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: LegalLink(
              key: const ValueKey('feedback-whats-new'),
              url: changelogUrl(language, version),
              builder: (context, open) => TextButton.icon(
                onPressed: open,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(l10n.feedbackWhatsNew(version)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A message: the user's on the honey side, Snacklist Support's on the
/// raised surface; [footer] says when (and who).
class const _Bubble({
  required final bool mine,
  required final String text,
  required final String footer,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.85),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: mine ? t.honeySoft : t.surfaceRaised,
              border: Border.all(color: t.border, width: HlBorder.width),
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(HlRadius.m),
                topEnd: const Radius.circular(HlRadius.m),
                bottomStart: Radius.circular(
                  mine ? HlRadius.m : HlRadius.s / 3,
                ),
                bottomEnd: Radius.circular(mine ? HlRadius.s / 3 : HlRadius.m),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                HlSpace.s4,
                HlSpace.s3,
                HlSpace.s4,
                HlSpace.s3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: HlSpace.s1,
                children: [
                  Text(text, style: HlType.body.copyWith(color: t.text)),
                  Text(
                    footer,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: t.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
