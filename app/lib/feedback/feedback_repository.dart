import 'dart:async';

import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:flutter/foundation.dart' show immutable;
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
});

/// The note did not arrive (or the app could not tell): the form keeps it
/// and offers Retry.
sealed class const FeedbackError() implements Exception;

/// No answer: offline, a dropped connection or a timeout.
final class const FeedbackOffline() extends FeedbackError;

/// The server answered with an error.
final class const FeedbackRefused(final String code) extends FeedbackError;

/// Someone else's note has this id (it never happens with random ids);
/// the form takes a new one.
final class const FeedbackIdTaken() extends FeedbackError;

/// Sends notes; insert only, nothing is read back (docs/FEEDBACK.md).
abstract interface class FeedbackRepository() {
  /// Completes once the server has the note; throws [FeedbackError]
  /// otherwise. Sending the same [FeedbackSubmission.id] again succeeds
  /// without a second row.
  Future<void> submit(FeedbackSubmission note);
}

class SupabaseFeedbackRepository(
  final SupabaseClient _client, {
  final Duration timeout = const Duration(seconds: 15),
}) implements FeedbackRepository {
  @override
  Future<void> submit(FeedbackSubmission note) async {
    try {
      await _insert(note);
    } on PostgrestException catch (e) {
      if (e.code != _duplicate) {
        throw FeedbackRefused(e.code ?? 'unknown');
      }
      // A request with this id was still being written when this one
      // arrived. Again, the database skips the user's own repeat; a
      // second duplicate is someone else's row.
      try {
        await _insert(note);
      } on PostgrestException catch (e) {
        throw e.code == _duplicate
            ? const FeedbackIdTaken()
            : FeedbackRefused(e.code ?? 'unknown');
      }
    }
  }

  static const _duplicate = '23505';

  Future<void> _insert(FeedbackSubmission note) async {
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
            'screen': context.screen,
            'is_internal': context.isInternal,
            'household_id': ?context.householdId,
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
