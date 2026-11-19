import 'package:family_groceries/report/report_repository.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart' show Uint8List;
import 'package:flutter_bloc/flutter_bloc.dart';

/// Where the report stands.
sealed class const ReportStatus();

final class const ReportEditing() extends ReportStatus;

final class const ReportSending() extends ReportStatus;

/// The last send failed with [error]; everything entered is still here.
final class const ReportFailed(final ReportError error) extends ReportStatus;

/// The server stored the report as [ref]; the confirmation goes to [email]
/// when one was sent.
final class const ReportSent(final String ref, {final String? email})
    extends ReportStatus;

/// The form's parts Send checks, top to bottom.
enum ReportField() {
  category,
  where,
  reason,
  email,
  goodFaith,
}

/// The report being written (Legal B.4): what it is about, where, why,
/// who reports it, an optional screenshot and the good-faith statement.
@immutable
class const ReportState({
  final ReportCategory? category,
  final ReportTarget? target,
  final String reason = '',
  final String name = '',
  final String email = '',

  /// Name and e-mail are on screen, and so sent. Child sexual abuse
  /// material hides them until the reporter adds them (N-228.4).
  final bool contactShown = true,
  final bool goodFaith = false,

  /// The marked-up screenshot, a PNG.
  final Uint8List? screenshot,

  /// Send was tapped: the missing parts say so.
  final bool tried = false,
  final ReportStatus status = const ReportEditing(),
}) {
  int get reasonLength => reportLength(reason);

  /// The name and address that go along: shown and filled in.
  String? get sentName => contactShown ? _filled(name) : null;
  String? get sentEmail => contactShown ? _filled(email) : null;

  /// What keeps the report from going, in the form's order. Name and
  /// e-mail are never required (N-228.4); an address must be one.
  List<ReportField> get missing => [
    if (category == null) ReportField.category,
    if (switch (target) {
      null => true,
      ElsewhereTarget(:final location) => location.isEmpty,
      _ => false,
    })
      ReportField.where,
    if (reasonLength < minReportLength || reasonLength > maxReportLength)
      ReportField.reason,
    if (sentEmail case final email? when !_isEmail(email)) ReportField.email,
    if (!goodFaith) ReportField.goodFaith,
  ];

  bool get busy => status is ReportSending || status is ReportSent;

  ReportState copyWith({
    ReportCategory? category,
    ReportTarget? target,
    String? reason,
    String? name,
    String? email,
    bool? contactShown,
    bool? goodFaith,
    Uint8List? Function()? screenshot,
    bool? tried,
    ReportStatus? status,
  }) => ReportState(
    category: category ?? this.category,
    target: target ?? this.target,
    reason: reason ?? this.reason,
    name: name ?? this.name,
    email: email ?? this.email,
    contactShown: contactShown ?? this.contactShown,
    goodFaith: goodFaith ?? this.goodFaith,
    screenshot: screenshot == null ? this.screenshot : screenshot(),
    tried: tried ?? this.tried,
    status: status ?? this.status,
  );
}

String? _filled(String text) => text.trim().isEmpty ? null : text.trim();

/// The `report` function's rule, so the app refuses what it would.
final _address = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

bool _isEmail(String email) =>
    email.runes.length <= 254 && _address.hasMatch(email);

/// The report form's state (job 281). Prefilled with the `reporter`; sent
/// at most once, Retry after a failure sends it again.
class ReportCubit(
  final ReportRepository _repository, {
  required final String locale,
  final Reporter reporter = const Reporter(),
}) extends Cubit<ReportState> {
  this
    : super(
        ReportState(
          name: _prefillOf(reporter).name,
          email: _prefillOf(reporter).email,
        ),
      );

  static ({String name, String email}) _prefillOf(Reporter reporter) => (
    name: firstCodePoints(reporter.name?.trim() ?? '', maxReporterNameLength),
    email: reporter.email ?? '',
  );

  /// Name and address as they were when child sexual abuse material was
  /// picked; null while it isn't.
  ({String name, String email})? _beforeCsam;

  /// Picks what the report is about. Child sexual abuse material hides the
  /// contact and empties it (PM addendum, N-228: unprefilled until Legal
  /// answers Q19), so only what the reporter types after "Add my name and
  /// e-mail address" goes. Leaving it for another kind brings back what the
  /// fields held before, where they are still empty; between two other
  /// kinds the fields stay as the reporter left them, cleared included.
  /// It also drops an attached screenshot: none goes with such a report
  /// (Legal N-287).
  void pick(ReportCategory category) {
    final csam = category == ReportCategory.csam;
    final wasCsam = state.category == ReportCategory.csam;
    final before = _beforeCsam;
    if (csam && !wasCsam) {
      _beforeCsam = (name: state.name, email: state.email);
    } else if (!csam) {
      _beforeCsam = null;
    }
    _change(
      state.copyWith(
        category: category,
        contactShown: !csam,
        screenshot: csam ? () => null : null,
        name: csam && !wasCsam
            ? ''
            : before != null && !csam && state.name.trim().isEmpty
            ? before.name
            : null,
        email: csam && !wasCsam
            ? ''
            : before != null && !csam && state.email.trim().isEmpty
            ? before.email
            : null,
      ),
    );
  }

  /// Picked in the picker. Somewhere else keeps the place already described.
  void place(ReportTarget target) => _change(
    state.copyWith(
      target: switch ((target, state.target)) {
        (ElsewhereTarget(), final ElsewhereTarget described) => described,
        _ => target,
      },
    ),
  );

  void describe(String text) =>
      _change(state.copyWith(target: ElsewhereTarget(text)));

  void write(String reason) => _change(state.copyWith(reason: reason));

  void setName(String name) => _change(state.copyWith(name: name));

  void setEmail(String email) => _change(state.copyWith(email: email));

  /// "Add my name and e-mail address" under child sexual abuse material.
  void showContact() => _change(state.copyWith(contactShown: true));

  void confirm({required bool goodFaith}) =>
      _change(state.copyWith(goodFaith: goodFaith));

  void attach(Uint8List png) => _change(state.copyWith(screenshot: () => png));

  void removeScreenshot() => _change(state.copyWith(screenshot: () => null));

  /// Sends the report once nothing is [ReportState.missing]; marks what is
  /// missing otherwise. True once the server has it.
  Future<bool> send() async {
    if (state.busy) {
      return false;
    }
    final sending = state.copyWith(tried: true);
    final category = sending.category;
    final target = sending.target;
    if (sending.missing.isNotEmpty || category == null || target == null) {
      emit(sending);
      return false;
    }
    if ((sending.screenshot?.length ?? 0) > maxScreenshotBytes) {
      emit(
        sending.copyWith(
          status: const ReportFailed(ReportScreenshotTooLarge()),
        ),
      );
      return false;
    }
    emit(sending.copyWith(status: const ReportSending()));
    try {
      final ref = await _repository.send(
        ReportSubmission(
          locale: locale,
          category: category,
          target: target,
          reason: sending.reason.trim(),
          name: sending.sentName,
          email: sending.sentEmail,
          screenshot: sending.screenshot,
        ),
      );
      if (!isClosed) {
        emit(state.copyWith(status: ReportSent(ref, email: sending.sentEmail)));
      }
      return true;
    } on ReportError catch (error) {
      if (!isClosed) {
        emit(state.copyWith(status: ReportFailed(error)));
      }
      return false;
    }
  }

  void _change(ReportState next) {
    if (state.busy) {
      return;
    }
    emit(next.copyWith(status: const ReportEditing()));
  }
}
