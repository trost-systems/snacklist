import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart' show Uint8List;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

enum FeedbackStatus() {
  editing,
  sending,

  /// The last send got no answer or an error; the note is still here.
  failed,

  /// Storage turned the screenshot down; the note is still here, and
  /// switching the screenshot off sends it.
  screenshotRefused,

  /// The server has it. The next [FeedbackCubit.open] starts a new note.
  sent,
}

/// The note being written. Its text, kind and contact survive closing the
/// form (until it is sent or someone else signs in), so a closed form loses
/// nothing. The attachments belong to one opening (job 267): a shake offers
/// its [screen], a screenshot comes from the annotator.
@immutable
class const FeedbackState({
  final String message = '',
  final FeedbackCategory? category,
  final bool contactOk = false,
  final FeedbackStatus status = FeedbackStatus.editing,

  /// The screen's name a shake offers; null from More's row.
  final String? screen,
  final bool sendScreen = true,

  /// The marked-up screenshot, a PNG; null when none is attached.
  final Uint8List? screenshot,
  final bool sendScreenshot = true,
}) {
  /// Characters as the database counts them.
  int get length => feedbackLength(message);

  bool get tooLong => length > maxFeedbackLength;

  bool get canSend =>
      length > 0 && !tooLong && status != FeedbackStatus.sending;

  /// The screen name that goes along: offered and switched on.
  String? get sentScreen => sendScreen ? screen : null;

  /// The screenshot that goes along: attached and switched on.
  Uint8List? get sentScreenshot => sendScreenshot ? screenshot : null;

  FeedbackState copyWith({
    String? message,
    FeedbackCategory? Function()? category,
    bool? contactOk,
    FeedbackStatus? status,
    Uint8List? screenshot,
    bool? sendScreen,
    bool? sendScreenshot,
  }) => FeedbackState(
    message: message ?? this.message,
    category: category == null ? this.category : category(),
    contactOk: contactOk ?? this.contactOk,
    status: status ?? this.status,
    screen: screen,
    sendScreen: sendScreen ?? this.sendScreen,
    screenshot: screenshot ?? this.screenshot,
    sendScreenshot: sendScreenshot ?? this.sendScreenshot,
  );
}

/// The feedback form's state (job 21): one note, one id, sent at most
/// once. A double tap sends once; Retry after a failure sends the same id,
/// so a note whose answer was lost is still one row; changing the note
/// after a failure makes it a new one. `feedback_submitted` goes out
/// only after the server has the note, once per id.
class FeedbackCubit(
  final FeedbackRepository _repository, {
  final Analytics? analytics,
  String Function()? newId,
}) extends Cubit<FeedbackState> {
  this : super(const FeedbackState());

  final String Function() _newId = newId ?? const Uuid().v4;
  late String _id = _newId();
  String? _owner;
  final _tracked = <String>{};

  /// The id the next send uses; for tests.
  String get id => _id;

  /// The form opens for [userId] with this opening's attachments: the
  /// [screen] a shake offers and the marked-up [screenshot]. A sent note,
  /// or one of another account, gives way to a blank one.
  void open({required String? userId, String? screen, Uint8List? screenshot}) {
    if (userId != _owner || state.status == FeedbackStatus.sent) {
      _owner = userId;
      _id = _newId();
      emit(FeedbackState(screen: screen, screenshot: screenshot));
    } else if (screen != state.screen ||
        !identical(screenshot, state.screenshot) ||
        !state.sendScreen ||
        !state.sendScreenshot) {
      _change(
        FeedbackState(
          message: state.message,
          category: state.category,
          contactOk: state.contactOk,
          screen: screen,
          screenshot: screenshot,
        ),
      );
    }
  }

  /// Attaches [png], the marked-up screenshot, and switches it on.
  void attach(Uint8List png) =>
      _change(state.copyWith(screenshot: png, sendScreenshot: true));

  void setSendScreen({required bool on}) {
    if (on != state.sendScreen) {
      _change(state.copyWith(sendScreen: on));
    }
  }

  void setSendScreenshot({required bool on}) {
    if (on != state.sendScreenshot) {
      _change(state.copyWith(sendScreenshot: on));
    }
  }

  void edit(String message) {
    if (message != state.message) {
      _change(state.copyWith(message: message));
    }
  }

  /// Picks [category], or clears it when it is the one picked.
  void pick(FeedbackCategory category) => _change(
    state.copyWith(
      category: () => state.category == category ? null : category,
    ),
  );

  void setContact({required bool ok}) {
    if (ok != state.contactOk) {
      _change(state.copyWith(contactOk: ok));
    }
  }

  /// Sends the note with [facts], the screen name and the screenshot when
  /// they are switched on. True once the server has it.
  Future<bool> send(FeedbackContext facts) async {
    if (!state.canSend || state.status == FeedbackStatus.sent) {
      return false;
    }
    final id = _id;
    final sending = state;
    final context = facts.screen == sending.sentScreen
        ? facts
        : facts.withScreen(sending.sentScreen);
    final screenshot = sending.sentScreenshot;
    emit(sending.copyWith(status: FeedbackStatus.sending));
    try {
      await _repository.submit(
        FeedbackSubmission(
          id: id,
          message: sending.message.trim(),
          category: sending.category,
          contactOk: sending.contactOk,
          context: context,
          screenshot: screenshot,
        ),
      );
    } on FeedbackIdTaken {
      _id = _newId();
      _fail();
      return false;
    } on FeedbackScreenshotRefused {
      _fail(FeedbackStatus.screenshotRefused);
      return false;
    } on Object {
      _fail();
      return false;
    }
    if (_tracked.add(id)) {
      analytics?.track('feedback_submitted', {
        'category': sending.category?.name ?? 'none',
        'entry_point': context.entryPoint.name,
        'screen': ?context.screen,
        'contact_ok': sending.contactOk,
        'screenshot': screenshot != null,
      });
    }
    if (!isClosed) {
      emit(state.copyWith(status: FeedbackStatus.sent));
    }
    return true;
  }

  void _fail([FeedbackStatus status = FeedbackStatus.failed]) {
    if (!isClosed) {
      emit(state.copyWith(status: status));
    }
  }

  /// A change after a failure is a different note: it gets its own id, so
  /// a first try that did arrive is not taken for it.
  void _change(FeedbackState next) {
    if (state.status == FeedbackStatus.sending ||
        state.status == FeedbackStatus.sent) {
      return;
    }
    if (state.status
        case FeedbackStatus.failed || FeedbackStatus.screenshotRefused) {
      _id = _newId();
    }
    emit(next.copyWith(status: FeedbackStatus.editing));
  }
}
