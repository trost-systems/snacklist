import 'dart:async';

import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_note.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart' show Uint8List;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bug, idea or other; none picked is null.
enum FeedbackCategory() {
  bug,
  idea,
  other,
}

/// One note as it goes to `public.feedback`.
@immutable
class const FeedbackSubmission({
  /// Made once per note: a retry with the same id stays one row.
  required final String id,

  /// Trimmed, 1 to [maxFeedbackLength] characters.
  required final String message,
  required final FeedbackCategory? category,
  required final bool contactOk,
  required final FeedbackContext context,

  /// The marked-up screenshot, a PNG; null sends none (job 267).
  final Uint8List? screenshot,
});

/// The note did not arrive (or the app could not tell): the form keeps it
/// and offers Retry.
sealed class const FeedbackError() implements Exception;

/// No answer: offline, a dropped connection or a timeout.
final class const FeedbackOffline() extends FeedbackError;

/// The server answered with an error.
final class const FeedbackRefused(final String code) extends FeedbackError;

/// The screenshot was turned down (job 267: the day's or the bucket's
/// quota, its size or type): sending without it works.
final class const FeedbackScreenshotRefused(final String code)
    extends FeedbackError;

/// Someone else's note has this id (it never happens with random ids);
/// the form takes a new one.
final class const FeedbackIdTaken() extends FeedbackError;

/// Sends notes (docs/FEEDBACK.md); a screenshot goes to the private bucket
/// first, then the row names it. Job 268 (FB4) reads the user's own notes
/// back with their status and reply, and the listed ideas with their +1s.
abstract interface class FeedbackRepository() {
  /// Completes once the server has the note; throws [FeedbackError]
  /// otherwise. Sending the same [FeedbackSubmission.id] again succeeds
  /// without a second row.
  Future<void> submit(FeedbackSubmission note);

  /// The signed-in user's own notes, newest first, at most 50; throws
  /// [FeedbackError].
  Future<List<FeedbackNote>> notes();

  /// Marks the user's own note [id] as opened since its last answer.
  Future<void> markSeen(String id);

  /// The listed ideas with every household's +1s and whether
  /// [householdId] gave one.
  Future<List<FeedbackIdea>> ideas(String householdId);

  /// Gives (or takes back) [householdId]'s +1 on [ideaId]; the idea's new
  /// total.
  Future<int> vote(String ideaId, String householdId, {required bool on});
}

class SupabaseFeedbackRepository(
  final SupabaseClient _client, {
  final Duration timeout = const Duration(seconds: 15),
}) implements FeedbackRepository {
  @override
  Future<void> submit(FeedbackSubmission note) async {
    final screenshot = switch (note.screenshot) {
      final png? => await _upload(note.id, png),
      null => null,
    };
    try {
      await _insert(note, screenshot);
    } on PostgrestException catch (e) {
      if (e.code != _duplicate) {
        throw FeedbackRefused(e.code ?? 'unknown');
      }
      // A request with this id was still being written when this one
      // arrived. Again, the database skips the user's own repeat; a
      // second duplicate is someone else's row.
      try {
        await _insert(note, screenshot);
      } on PostgrestException catch (e) {
        throw e.code == _duplicate
            ? const FeedbackIdTaken()
            : FeedbackRefused(e.code ?? 'unknown');
      }
    }
  }

  static const _duplicate = '23505';

  @override
  Future<List<FeedbackNote>> notes() async {
    final rows = await _read(
      _client.rest
          .from('feedback')
          .select(
            'id, created_at, message, category, status, fixed_in, reply, '
            'replied_at, answered_at, seen_at',
          )
          .order('created_at')
          .limit(50),
    );
    return switch (rows) {
      final List<Object?> rows => [for (final row in rows) parseNote(row)],
      _ => throw const FeedbackRefused('bad_response'),
    };
  }

  @override
  Future<void> markSeen(String id) => _read(
    _client.rest.rpc<Object?>('feedback_mark_seen', params: {'p_id': id}),
  );

  @override
  Future<List<FeedbackIdea>> ideas(String householdId) async {
    final rows = await _read(
      _client.rest.rpc<Object?>(
        'feedback_ideas',
        params: {'p_household': householdId},
      ),
    );
    return switch (rows) {
      final List<Object?> rows => [for (final row in rows) parseIdea(row)],
      _ => throw const FeedbackRefused('bad_response'),
    };
  }

  @override
  Future<int> vote(
    String ideaId,
    String householdId, {
    required bool on,
  }) async => switch (await _read(
    _client.rest.rpc<Object?>(
      'vote_feedback_idea',
      params: {'p_idea': ideaId, 'p_household': householdId, 'p_on': on},
    ),
  )) {
    final int total => total,
    _ => throw const FeedbackRefused('bad_response'),
  };

  /// [request]'s answer, its failures as [FeedbackError]s.
  Future<Object?> _read(Future<Object?> request) async {
    try {
      return await request.timeout(timeout);
    } on PostgrestException catch (e) {
      throw FeedbackRefused(e.code ?? 'unknown');
    } on Object {
      throw const FeedbackOffline();
    }
  }

  /// Has the `feedback-screenshots` function store [png] as
  /// `<user id>/<note id>.png` and returns that name. Only the function
  /// stores, under the quotas (docs/FEEDBACK.md); an image already there
  /// is this user's own earlier try of this note: uploaded.
  Future<String> _upload(String id, Uint8List png) async {
    final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke(
            'feedback-screenshots/upload/$id',
            headers: const {'Content-Type': 'image/png'},
            body: png,
            // Next to the database and the bucket, wherever the user is
            // (Legal N-267): Supabase runs it nearest the caller otherwise.
            // The query form only: `region:` adds an x-region header, which
            // the functions' CORS preflight refuses on the web.
            queryParameters: const {'forceFunctionRegion': 'eu-central-1'},
          )
          .timeout(timeout);
    } on FunctionException catch (e) {
      throw switch (e) {
        // No answer: no connection, the request never left.
        FunctionsFetchException() => const FeedbackOffline(),
        // The quota (by its code: a 403 also means a refused token), the
        // size or the type (a gateway may answer those without JSON).
        FunctionException(status: 403, details: {'error': 'quota'}) ||
        FunctionException(
          status: 413 || 415,
        ) => FeedbackScreenshotRefused('upload_${e.status}'),
        FunctionException(:final status) => FeedbackRefused('upload_$status'),
      };
    } on Object {
      // A timeout.
      throw const FeedbackOffline();
    }
    return switch (response.data) {
      {'name': final String name} => name,
      _ => throw const FeedbackRefused('upload_bad_response'),
    };
  }

  Future<void> _insert(FeedbackSubmission note, String? screenshot) async {
    final context = note.context;
    try {
      await _client.rest
          .from('feedback')
          .insert({
            'id': note.id,
            'message': note.message,
            'category': note.category?.name,
            'contact_ok': note.contactOk,
            'app_version': context.appVersion,
            'build': context.build,
            'platform': context.platform,
            'os_version': context.osVersion,
            'locale': context.locale,
            'screen': ?context.screen,
            'is_internal': context.isInternal,
            'household_id': ?context.householdId,
            'screenshot': ?screenshot,
          })
          .timeout(timeout);
    } on PostgrestException {
      rethrow;
    } on Object {
      // A timeout, a failed fetch (web) or socket (native): no answer.
      throw const FeedbackOffline();
    }
  }
}

/// The longest note, in characters (Unicode code points, as Postgres'
/// char_length counts them).
const maxFeedbackLength = 2000;

/// A note's length as the database checks it: trimmed, in code points.
int feedbackLength(String message) => message.trim().runes.length;
