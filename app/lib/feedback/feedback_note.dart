import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:flutter/foundation.dart' show immutable;

/// Where a note stands (job 268, FB4). Snacklist Support sets it by hand in
/// the dashboard (docs/FEEDBACK.md); every note starts [sent].
enum NoteStatus() {
  sent,
  read,
  planned,
  fixed;

  /// The column's value; one this app does not know yet reads as [sent].
  static NoteStatus parse(Object? value) => values.asNameMap()[value] ?? sent;
}

/// One of the user's own notes as `public.feedback` has it now.
@immutable
class const FeedbackNote({
  required final String id,
  required final DateTime createdAt,
  required final String message,
  required final FeedbackCategory? category,
  required final NoteStatus status,

  /// The version that fixed it, `1.4.1`; only with [NoteStatus.fixed].
  final String? fixedIn,

  /// Snacklist Support's answer.
  final String? reply,
  final DateTime? repliedAt,

  /// When the status, the version or the reply last changed.
  final DateTime? answeredAt,

  /// When the user last opened the note after an answer.
  final DateTime? seenAt,
}) {
  /// Answered since the user last opened it: the More row counts these.
  bool get unread => switch ((answeredAt, seenAt)) {
    (null, _) => false,
    (_, null) => true,
    (final answered?, final seen?) => seen.isBefore(answered),
  };

  /// This note as opened: its last answer seen.
  FeedbackNote seen() => FeedbackNote(
    id: id,
    createdAt: createdAt,
    message: message,
    category: category,
    status: status,
    fixedIn: fixedIn,
    reply: reply,
    repliedAt: repliedAt,
    answeredAt: answeredAt,
    seenAt: answeredAt ?? seenAt,
  );
}

/// Whether an idea is still weighed or already planned.
enum IdeaStatus() {
  considering,
  planned;

  /// The column's value; an unknown one reads as [considering].
  static IdeaStatus parse(Object? value) =>
      values.asNameMap()[value] ?? considering;
}

/// An idea Snacklist Support listed, with the +1s of every household. Who
/// gave them is never known to the app.
@immutable
class const FeedbackIdea({
  required final String id,
  required final String titleDe,
  required final String titleEn,
  required final IdeaStatus status,

  /// How many households gave it a +1.
  required final int votes,

  /// Whether the shown household gave one.
  required final bool voted,
}) {
  /// The title in the UI language: German for `de`, English otherwise.
  String title(String languageCode) => languageCode == 'de' ? titleDe : titleEn;

  FeedbackIdea withVote({required bool voted, required int votes}) =>
      FeedbackIdea(
        id: id,
        titleDe: titleDe,
        titleEn: titleEn,
        status: status,
        votes: votes,
        voted: voted,
      );
}

/// A `feedback` row as PostgREST sends it.
FeedbackNote parseNote(Object? row) => switch (row) {
  {
    'id': final String id,
    'created_at': final String created,
    'message': final String message,
  } =>
    FeedbackNote(
      id: id,
      createdAt: _time(created) ?? (throw const FeedbackRefused('bad_note')),
      message: message,
      category: FeedbackCategory.values.asNameMap()[row['category']],
      status: NoteStatus.parse(row['status']),
      fixedIn: _text(row['fixed_in']),
      reply: _text(row['reply']),
      repliedAt: _time(row['replied_at']),
      answeredAt: _time(row['answered_at']),
      seenAt: _time(row['seen_at']),
    ),
  _ => throw const FeedbackRefused('bad_note'),
};

/// A row of `feedback_ideas()`.
FeedbackIdea parseIdea(Object? row) => switch (row) {
  {
    'id': final String id,
    'title_de': final String titleDe,
    'title_en': final String titleEn,
    'votes': final int votes,
    'voted': final bool voted,
  } =>
    FeedbackIdea(
      id: id,
      titleDe: titleDe,
      titleEn: titleEn,
      status: IdeaStatus.parse(row['status']),
      votes: votes,
      voted: voted,
    ),
  _ => throw const FeedbackRefused('bad_idea'),
};

String? _text(Object? value) => value is String ? value : null;

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
