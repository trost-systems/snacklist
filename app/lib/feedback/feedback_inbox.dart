import 'dart:async';

import 'package:family_groceries/feedback/feedback_note.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

@immutable
class const InboxState({
  /// The user's notes, newest first; null until the first load arrived.
  final List<FeedbackNote>? notes,
  final List<FeedbackIdea> ideas = const [],

  /// The last load failed; what an earlier one brought stays.
  final bool failed = false,
}) {
  /// Notes answered since they were last opened: More's badge.
  int get unread => notes?.where((note) => note.unread).length ?? 0;
}

/// Feedback & ideas (job 268, FB4): the user's own notes with their status
/// and reply, and the listed ideas with the shown household's +1. A load
/// for another user starts empty; the newest load wins.
class FeedbackInbox(final FeedbackRepository _repository)
    extends Cubit<InboxState> {
  this : super(const InboxState());

  String? _owner;
  String? _household;
  var _generation = 0;

  /// Ideas whose +1 is on its way, each with its own token: a load that
  /// arrives meanwhile keeps what the tap showed, and an answer whose token
  /// is gone (another user or household since) changes nothing.
  final _voting = <String, Object>{};

  Future<void> load({
    required String userId,
    required String? householdId,
  }) async {
    if (userId != _owner) {
      _owner = userId;
      _voting.clear();
      emit(const InboxState());
    } else if (householdId != _household) {
      _voting.clear();
      emit(InboxState(notes: state.notes, failed: state.failed));
    }
    _household = householdId;
    final generation = ++_generation;
    try {
      final (notes, ideas) = await (
        _repository.notes(),
        switch (householdId) {
          final household? => _repository.ideas(household),
          null => Future.value(const <FeedbackIdea>[]),
        },
      ).wait;
      if (generation == _generation && !isClosed) {
        final shown = {for (final idea in state.ideas) idea.id: idea};
        emit(
          InboxState(
            notes: notes,
            ideas: [
              for (final idea in ideas)
                if (_voting.containsKey(idea.id))
                  shown[idea.id] ?? idea
                else
                  idea,
            ],
          ),
        );
      }
    } on Object {
      if (generation == _generation && !isClosed) {
        emit(InboxState(notes: state.notes, ideas: state.ideas, failed: true));
      }
    }
  }

  /// Marks note [id] opened, at once here and then on the server. A failed
  /// mark shows as unread again with the next load.
  Future<void> markSeen(String id) async {
    final notes = state.notes;
    if (notes == null || !notes.any((note) => note.id == id && note.unread)) {
      return;
    }
    emit(
      InboxState(
        notes: [
          for (final n in notes)
            if (n.id == id) n.seen() else n,
        ],
        ideas: state.ideas,
        failed: state.failed,
      ),
    );
    try {
      await _repository.markSeen(id);
    } on FeedbackError {
      return;
    }
  }

  /// Gives (or takes back) the household's +1 on [idea]: shown at once,
  /// undone when the server refuses. False then. A tap while the idea's
  /// last one is on its way is ignored.
  Future<bool> vote(FeedbackIdea idea, {required bool on}) async {
    final household = _household;
    if (household == null) {
      return false;
    }
    if (idea.voted == on || _voting.containsKey(idea.id)) {
      return true;
    }
    final token = Object();
    _voting[idea.id] = token;
    bool current() => identical(_voting[idea.id], token);
    _replace(idea.withVote(voted: on, votes: idea.votes + (on ? 1 : -1)));
    try {
      final total = await _repository.vote(idea.id, household, on: on);
      if (current()) {
        _replace(idea.withVote(voted: on, votes: total));
      }
      return true;
    } on Object {
      if (current()) {
        _replace(idea);
      }
      return false;
    } finally {
      if (current()) {
        _voting.remove(idea.id);
      }
    }
  }

  void _replace(FeedbackIdea next) {
    if (!isClosed) {
      emit(
        InboxState(
          notes: state.notes,
          ideas: [
            for (final idea in state.ideas)
              if (idea.id == next.id) next else idea,
          ],
          failed: state.failed,
        ),
      );
    }
  }
}

/// Loads the inbox for the signed-in user and the shown household; nothing
/// while signed out.
Future<void> refreshInbox(BuildContext context) =>
    switch (_shownTo(context.read<SessionCubit>().state)) {
      (final userId, final householdId)? => context.read<FeedbackInbox>().load(
        userId: userId,
        householdId: householdId,
      ),
      null => Future.value(),
    };

/// The user and household the inbox is loaded for; null signed out.
(String, String?)? _shownTo(Session session) => switch (session) {
  InHousehold(:final userId, :final household) => (userId, household.id),
  NeedsHousehold(:final userId) => (userId, null),
  _ => null,
};

/// Loads the inbox when [child] comes up and again whenever the session
/// shows another user or household: the shell keeps its pages through a
/// household switch. With [onResume], also when the app comes back.
class const InboxLoader({
  required final Widget child,
  final bool onResume = false,
  super.key,
}) extends StatefulWidget {
  @override
  State<InboxLoader> createState() => _InboxLoaderState();
}

class _InboxLoaderState() extends State<InboxLoader> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    unawaited(refreshInbox(context));
    if (widget.onResume) {
      _lifecycle = AppLifecycleListener(
        onResume: () => unawaited(refreshInbox(context)),
      );
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<SessionCubit, Session>(
    listenWhen: (before, now) => _shownTo(before) != _shownTo(now),
    listener: (context, _) => unawaited(refreshInbox(context)),
    child: widget.child,
  );
}
