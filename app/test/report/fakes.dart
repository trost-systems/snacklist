import 'dart:async';

import 'package:family_groceries/report/report_repository.dart';

/// The `report` function: [sent] holds every report it got, [ref] is the
/// number it answers; [failNext] makes the next sends throw [error];
/// [hold] keeps a send waiting until it completes.
class FakeReportRepository({
  /// Who the sign-in says is reporting.
  final Reporter who = const Reporter(),
}) implements ReportRepository {
  final sent = <ReportSubmission>[];
  var ref = 'M-7K2M-4Q9P';
  var failNext = 0;
  ReportError error = const ReportOffline();
  Completer<void>? hold;

  @override
  Reporter reporter() => who;

  @override
  Future<String> send(ReportSubmission report) async {
    sent.add(report);
    if (hold case final hold?) {
      await hold.future;
    }
    if (failNext > 0) {
      failNext--;
      throw error;
    }
    return ref;
  }
}
