import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart' show Uint8List;
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a report is about (Legal B.4, question 1), with the name the
/// `report` function takes.
enum ReportCategory(final String wire) {
  hate('hate'),
  personalRights('personal_rights'),
  ip('ip'),
  csam('csam'),
  danger('danger'),
  other('other'),
}

/// Where the reported content is: a part of the shown household picked in
/// the app, or a place the reporter describes. [location] is the place as
/// the moderator reads it, in English.
sealed class const ReportTarget() {
  String get location;
}

final class const HouseholdTarget({
  required final String id,
  required final String name,
}) extends ReportTarget {
  @override
  String get location => 'household "$name"';
}

final class const ListTarget({
  required final String id,
  required final String name,
  required final String household,
}) extends ReportTarget {
  @override
  String get location => 'list "$name", household "$household"';
}

final class const ItemTarget({
  required final String id,
  required final String name,

  /// The list it is on; null while the household's lists are unknown.
  required final String? list,
  required final String household,
}) extends ReportTarget {
  @override
  String get location => switch (list) {
    final list? => 'item "$name" in list "$list", household "$household"',
    null => 'item "$name", household "$household"',
  };
}

/// Somewhere the picker does not list, in the reporter's own [text].
final class const ElsewhereTarget([final String text = ''])
    extends ReportTarget {
  @override
  String get location => text.trim();
}

/// One report as it goes to `POST /functions/v1/report/app`.
@immutable
class const ReportSubmission({
  /// The app's language, `de` or `en`: the confirmation mail's.
  required final String locale,
  required final ReportCategory category,
  required final ReportTarget target,

  /// Trimmed, [minReportLength] to [maxReportLength] code points.
  required final String reason,

  /// Trimmed; null sends none.
  final String? name,
  final String? email,

  /// The PNG the reporter marked up; null sends none.
  final Uint8List? screenshot,
}) {
  /// The request body, as the function parses it.
  Map<String, Object> get body => {
    'locale': locale,
    'category': category.wire,
    'target': switch (target) {
      HouseholdTarget(:final id) => {'kind': 'household', 'id': id},
      ListTarget(:final id) => {'kind': 'list', 'id': id},
      ItemTarget(:final id) => {'kind': 'item', 'id': id},
      ElsewhereTarget() => {'kind': 'elsewhere'},
    },
    'location': target.location,
    'reason': reason,
    'name': ?name,
    'email': ?email,
    'good_faith': true,
    'screenshot': ?switch (screenshot) {
      final png? => base64Encode(png),
      null => null,
    },
  };
}

/// The report did not arrive (or the app could not tell): the form keeps
/// everything and says why.
sealed class const ReportError() implements Exception;

/// No answer: offline, a dropped connection or a timeout.
final class const ReportOffline() extends ReportError;

/// Too many reports, the user's or everyone's, this hour.
final class const ReportRateLimited() extends ReportError;

/// The screenshot is over [maxScreenshotBytes]: refused before sending, or
/// by the function (413).
final class const ReportScreenshotTooLarge() extends ReportError;

/// The function answered with another error, or with no number.
final class const ReportRefused(final String code) extends ReportError;

/// Who is reporting, as the sign-in knows them: the form's prefill.
@immutable
class const Reporter({final String? name, final String? email});

/// Sends reports of illegal content (job 281) to the `report` function,
/// which keeps them apart from feedback: they never show under the user's
/// notes.
abstract interface class ReportRepository() {
  /// The signed-in user's e-mail address and, from Google or Apple, name.
  Reporter reporter();

  /// The report's number once the server stored it; throws [ReportError].
  Future<String> send(ReportSubmission report);
}

class SupabaseReportRepository(
  final SupabaseClient _client, {
  final Duration timeout = const Duration(seconds: 30),
}) implements ReportRepository {
  @override
  Reporter reporter() {
    final user = _client.auth.currentUser;
    // The name a provider gave (Google; Apple at the first sign-in). The
    // app asks for none of its own.
    final name = switch (user?.userMetadata) {
      {'full_name': final String name} when name.trim().isNotEmpty => name,
      {'name': final String name} when name.trim().isNotEmpty => name,
      _ => null,
    };
    return Reporter(name: name?.trim(), email: user?.email);
  }

  @override
  Future<String> send(ReportSubmission report) async {
    final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke(
            'report/app',
            body: report.body,
            // Legal N-285: the report is handled in Frankfurt, like the
            // feedback upload (job 290).
            queryParameters: const {'forceFunctionRegion': 'eu-central-1'},
          )
          .timeout(timeout);
    } on FunctionException catch (e) {
      throw switch (e) {
        FunctionsFetchException() => const ReportOffline(),
        FunctionException(status: 429) => const ReportRateLimited(),
        FunctionException(status: 413) => const ReportScreenshotTooLarge(),
        FunctionException(:final status) => ReportRefused('$status'),
      };
    } on Object {
      // A timeout.
      throw const ReportOffline();
    }
    return switch (response.data) {
      {'ref': final String ref} => ref,
      _ => throw const ReportRefused('bad_response'),
    };
  }
}

/// The shortest and longest reason, in code points as the server counts.
const minReportLength = 20;
const maxReportLength = 5000;

/// The longest name and place description the server takes.
const maxReporterNameLength = 200;
const maxElsewhereLength = 2000;

/// The largest screenshot the server takes, in bytes of PNG.
const maxScreenshotBytes = 2 * 1024 * 1024;

/// A text's length as the server checks it: trimmed, in code points.
int reportLength(String text) => text.trim().runes.length;

/// [text]'s first [max] code points.
String firstCodePoints(String text, int max) => text.runes.length <= max
    ? text
    : String.fromCharCodes(text.runes.take(max));
