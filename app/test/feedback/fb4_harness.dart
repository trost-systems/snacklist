import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/feedback/feedback_note.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';

import 'fakes.dart';

/// Shared by the FB4 tests and their review screenshots (job 268).
const fb4 = {feedbackFb4Flag};

DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, day, hour, minute);

/// A fixed note with a reply nobody opened yet.
final fixedNote = FeedbackNote(
  id: 'n-fixed',
  createdAt: at(14, 17, 44),
  message: 'Hafermilch landet unter Vorrat statt im Kühlregal.',
  category: FeedbackCategory.bug,
  status: NoteStatus.fixed,
  fixedIn: '1.4.1',
  reply:
      'Danke, das war ein Fehler in der Sortierung. In 1.4.1 behoben; '
      'Hafermilch landet jetzt im Kühlregal.',
  repliedAt: at(15, 9, 2),
  answeredAt: at(15, 9, 2),
);

/// Read since the user last looked, without a reply: a new status.
final readNote = FeedbackNote(
  id: 'n-read',
  createdAt: at(13, 8),
  message: 'Die Summe springt, wenn ich einen Preis ändere.',
  category: FeedbackCategory.bug,
  status: NoteStatus.read,
  answeredAt: at(14, 8),
);

/// Planned, its answer already opened.
final plannedNote = FeedbackNote(
  id: 'n-planned',
  createdAt: at(12, 8),
  message: 'Könnte die Liste in der Reihenfolge der Gänge stehen?',
  category: FeedbackCategory.idea,
  status: NoteStatus.planned,
  answeredAt: at(12, 20),
  seenAt: at(12, 21),
);

final sentNote = FeedbackNote(
  id: 'n-sent',
  createdAt: at(11, 8),
  message: 'Das Häkchen bei Brot reagiert erst beim zweiten Tippen.',
  category: FeedbackCategory.bug,
  status: NoteStatus.sent,
);

/// Fixed without a version.
final fixedPlainNote = FeedbackNote(
  id: 'n-fixed-plain',
  createdAt: at(10, 8),
  message: 'Dunkles Design: Preise schwer lesbar.',
  category: FeedbackCategory.bug,
  status: NoteStatus.fixed,
  answeredAt: at(10, 9),
  seenAt: at(10, 10),
);

const aisleIdea = FeedbackIdea(
  id: 'i-aisle',
  titleDe: 'Liste in der Reihenfolge der Gänge',
  titleEn: 'List in aisle order',
  status: IdeaStatus.planned,
  votes: 14,
  voted: false,
);

const mealIdea = FeedbackIdea(
  id: 'i-meal',
  titleDe: 'Wochenplan für Essen',
  titleEn: 'Weekly meal plan',
  status: IdeaStatus.considering,
  votes: 9,
  voted: false,
);

/// The notes' texts as an English-speaking user would have written them.
const _english = {
  'n-fixed': (
    'Oat milk lands under Pantry instead of Chilled.',
    'Thanks, that was a sorting bug. Fixed in 1.4.1; oat milk now goes to '
        'Chilled.',
  ),
  'n-read': ('The total jumps when I change a price.', null),
  'n-planned': ('Could the list follow the aisle order?', null),
  'n-sent': ('Ticking off bread only works on the second tap.', null),
  'n-fixed-plain': ('Dark theme: prices hard to read.', null),
};

FeedbackNote _inEnglish(FeedbackNote note) => FeedbackNote(
  id: note.id,
  createdAt: note.createdAt,
  message: _english[note.id]?.$1 ?? note.message,
  category: note.category,
  status: note.status,
  fixedIn: note.fixedIn,
  reply: _english[note.id]?.$2 ?? note.reply,
  repliedAt: note.repliedAt,
  answeredAt: note.answeredAt,
  seenAt: note.seenAt,
);

/// A server with every kind of note (two answers unopened) and two ideas;
/// [english] notes for the English screenshots.
FakeFeedbackRepository fb4Server({bool english = false}) {
  final notes = [fixedNote, readNote, plannedNote, sentNote, fixedPlainNote];
  return FakeFeedbackRepository()
    ..serverNotes.addAll(english ? notes.map(_inEnglish) : notes)
    ..serverIdeas = [aisleIdea, mealIdea];
}
