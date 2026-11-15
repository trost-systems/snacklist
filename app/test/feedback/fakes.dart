import 'dart:async';

import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';

/// The server's feedback table: one row per id, like the database (a
/// repeat of an id is no second row). [failNext] makes the next sends
/// throw; [landThenFail] stores the note but loses the answer; [hold]
/// keeps a send waiting until it completes.
class FakeFeedbackRepository() implements FeedbackRepository {
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
    rows.putIfAbsent(note.id, () => note);
    if (landThenFail > 0) {
      landThenFail--;
      throw const FeedbackOffline();
    }
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
