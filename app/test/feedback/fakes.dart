import 'dart:async';

import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_note.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';

/// The server's feedback table: one row per id, like the database (a
/// repeat of an id is no second row). [failNext] makes the next sends
/// throw; [landThenFail] stores the note but loses the answer; [hold]
/// keeps a send waiting until it completes.
///
/// Job 268: a sent note shows in [serverNotes] as `sent` (the server's
/// own notes, newest first); [serverIdeas] are the listed ideas as the shown
/// household sees them. [failReads] and [failVotes] make the next reads
/// or +1s throw; [holdVote] keeps a +1 waiting.
class FakeFeedbackRepository() implements FeedbackRepository {
  final serverNotes = <FeedbackNote>[];
  var serverIdeas = <FeedbackIdea>[];
  final seen = <String>[];
  final votes = <({String idea, String household, bool on})>[];
  var reads = 0;
  var failReads = 0;
  var failVotes = 0;
  Completer<void>? holdVote;

  final rows = <String, FeedbackSubmission>{};
  final calls = <FeedbackSubmission>[];
  var failNext = 0;
  var landThenFail = 0;
  FeedbackError error = const FeedbackOffline();
  Completer<void>? hold;

  @override
  Future<void> submit(FeedbackSubmission note) async {
    calls.add(note);
    if (hold case final hold?) {
      await hold.future;
    }
    if (failNext > 0) {
      failNext--;
      throw error;
    }
    if (!rows.containsKey(note.id)) {
      serverNotes.insert(
        0,
        FeedbackNote(
          id: note.id,
          createdAt: DateTime.utc(2026, 11, 15, 12, rows.length),
          message: note.message,
          category: note.category,
          status: NoteStatus.sent,
        ),
      );
    }
    rows.putIfAbsent(note.id, () => note);
    if (landThenFail > 0) {
      landThenFail--;
      throw const FeedbackOffline();
    }
  }

  void _read() {
    reads++;
    if (failReads > 0) {
      failReads--;
      throw const FeedbackOffline();
    }
  }

  @override
  Future<List<FeedbackNote>> notes() async {
    _read();
    return List.of(serverNotes);
  }

  @override
  Future<void> markSeen(String id) async {
    seen.add(id);
    final i = serverNotes.indexWhere((n) => n.id == id);
    if (i >= 0) {
      serverNotes[i] = serverNotes[i].seen();
    }
  }

  @override
  Future<List<FeedbackIdea>> ideas(String householdId) async {
    _read();
    return List.of(serverIdeas);
  }

  @override
  Future<int> vote(
    String ideaId,
    String householdId, {
    required bool on,
  }) async {
    votes.add((idea: ideaId, household: householdId, on: on));
    if (holdVote case final hold?) {
      await hold.future;
    }
    if (failVotes > 0) {
      failVotes--;
      throw const FeedbackRefused('42501');
    }
    final i = serverIdeas.indexWhere((idea) => idea.id == ideaId);
    final idea = serverIdeas[i];
    final total = idea.voted == on ? idea.votes : idea.votes + (on ? 1 : -1);
    serverIdeas[i] = idea.withVote(voted: on, votes: total);
    return total;
  }
}

class FakeFeedbackDevice() implements FeedbackDevice {
  @override
  Future<DeviceFacts> read() async => const DeviceFacts(
    appVersion: '1.2.3',
    build: '45',
    platform: 'android',
    osVersion: 'Android 14 (SDK 34)',
  );
}

const sampleContext = FeedbackContext(
  appVersion: '1.2.3',
  build: '45',
  platform: 'android',
  osVersion: 'Android 14 (SDK 34)',
  locale: 'de',
  entryPoint: FeedbackEntryPoint.settings,
  isInternal: false,
);
