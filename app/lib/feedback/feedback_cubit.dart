import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

enum FeedbackStatus() {
  editing,
  sending,

  /// The last send got no answer or an error; the note is still here.
  failed,

  /// The server has it. The next [FeedbackCubit.open] starts a new note.
  sent,
}

/// The note being written. It survives closing the form (until it is
/// sent or someone else signs in), so a closed form loses nothing.
@immutable
class const FeedbackState({
  final String message = '',
  final FeedbackCategory? category,
  final bool contactOk = false,
  final FeedbackStatus status = FeedbackStatus.editing,
}) {
  /// Characters as the database counts them.
  int get length => feedbackLength(message);

  bool get tooLong => length > maxFeedbackLength;

  bool get canSend =>
      length > 0 && !tooLong && status != FeedbackStatus.sending;

  FeedbackState copyWith({
    String? message,
    FeedbackCategory? Function()? category,
    bool? contactOk,
    FeedbackStatus? status,
  }) => FeedbackState(
    message: message ?? this.message,
    category: category == null ? this.category : category(),
    contactOk: contactOk ?? this.contactOk,
    status: status ?? this.status,
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

  /// The form opens for [userId]: a sent note, or one of another account,
  /// gives way to a blank one.
  void open({required String? userId}) {
    if (userId != _owner || state.status == FeedbackStatus.sent) {
      _owner = userId;
      _restart();
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

  /// Sends the note with [context]. True once the server has it.
  Future<bool> send(FeedbackContext context) async {
    if (!state.canSend || state.status == FeedbackStatus.sent) {
      return false;
    }
    final id = _id;
    final sending = state;
    emit(sending.copyWith(status: FeedbackStatus.sending));
    try {
      await _repository.submit(
        FeedbackSubmission(
          id: id,
          message: sending.message.trim(),
          category: sending.category,
          contactOk: sending.contactOk,
          context: context,
        ),
      );
    } on FeedbackIdTaken {
      _id = _newId();
      _fail();
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
      });
    }
    if (!isClosed) {
      emit(state.copyWith(status: FeedbackStatus.sent));
    }
    return true;
  }

  void _fail() {
    if (!isClosed) {
      emit(state.copyWith(status: FeedbackStatus.failed));
    }
  }

  /// A change after a failure is a different note: it gets its own id, so
  /// a first try that did arrive is not taken for it.
  void _change(FeedbackState next) {
    if (state.status == FeedbackStatus.sending ||
        state.status == FeedbackStatus.sent) {
      return;
    }
    if (state.status == FeedbackStatus.failed) {
      _id = _newId();
    }
    emit(next.copyWith(status: FeedbackStatus.editing));
  }

  void _restart() {
    _id = _newId();
    emit(const FeedbackState());
  }
}
