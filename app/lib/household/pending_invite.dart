import 'dart:async';

import 'package:family_groceries/analytics/events.dart' show JoinMethod;
import 'package:flutter/services.dart';

/// A kept invite: its code, since when, and how it reached the app.
typedef KeptInvite = ({String code, DateTime at, JoinMethod via});

/// Where a pending invite is kept on the device: `DeviceCache` in the app.
abstract interface class PendingInviteStore() {
  Future<KeptInvite?> pendingInvite();

  /// Null drops it.
  Future<void> savePendingInvite(KeptInvite? invite);
}

/// An invite code as the server compares it: upper case, letters and
/// digits only.
String normalizeInviteCode(String code) =>
    code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

/// The codes the server makes: 8 of A-Z and 2-9 without I, O, 0 and 1.
final _codePattern = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

/// A code as people write it: 8 letters and digits, a dash or space after
/// the fourth allowed.
final _writtenCode = RegExp(r'^[A-Za-z0-9]{4}[- ]?[A-Za-z0-9]{4}$');

/// A join link anywhere in a text (`…/join/<code>`) or one carrying the
/// code as `invite=` (`?invite=<code>`).
final _linkedCode = RegExp(
  '(?:/join/|[?&]invite=)([A-Za-z0-9]{4}-?[A-Za-z0-9]{4})(?![A-Za-z0-9])',
);

/// The invite code in [text] the user pasted: a join link (also inside a
/// whole shared message, which carries the link and the code) or a code
/// alone, with or without its dash. Null when there is none the server
/// could have made.
String? inviteCodeIn(String text) {
  final trimmed = text.trim();
  final candidate =
      _linkedCode.firstMatch(trimmed)?.group(1) ??
      (_writtenCode.hasMatch(trimmed) ? trimmed : null);
  final code = candidate == null ? null : normalizeInviteCode(candidate);
  return code != null && _codePattern.hasMatch(code) ? code : null;
}

/// The length of an invite code.
const inviteCodeLength = 8;

/// Keeps an invite code field to what a code can be: a pasted join link,
/// whole shared message or `ABCD-EFGH` becomes its code; otherwise upper
/// case, only the characters codes use (A-Z and 2-9 without I and O), at
/// most 8.
class const InviteCodeFormatter() extends TextInputFormatter {
  static final _outside = RegExp('[^A-HJ-NP-Z2-9]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final old = oldValue.text;
    // A paste into a field that held part of a code: the pasted part alone.
    final pasted = text.length > old.length && text.startsWith(old)
        ? text.substring(old.length)
        : text;
    final cleaned = text.toUpperCase().replaceAll(_outside, '');
    final code =
        inviteCodeIn(text) ??
        inviteCodeIn(pasted) ??
        cleaned.substring(0, cleaned.length.clamp(0, inviteCodeLength));
    return TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
  }
}

/// The invite of a `/join/<code>` link the user opened, kept on the device
/// so it survives sign-in (also the mobile apps' custom-scheme return,
/// which loses the location), an app kill, the analytics consent and the
/// onboarding steps. The router reads [code] synchronously; writes go to
/// the [PendingInviteStore] in the background. Like the link itself it
/// lasts 7 days. The code never leaves the device: it is not logged, not
/// sent to analytics and not part of a screen name.
class PendingInvite(
  final PendingInviteStore _store, {
  KeptInvite? initial,

  /// The clock; tests pass their own.
  final DateTime Function() now = DateTime.now,
}) {
  /// Loads what the store holds, before the first frame.
  static Future<PendingInvite> load(
    PendingInviteStore store, {
    DateTime Function() now = DateTime.now,
  }) async =>
      PendingInvite(store, initial: await store.pendingInvite(), now: now);

  static const lifetime = Duration(days: 7);

  var _invite = initial;

  /// The pending code, or null when there is none or it is older than
  /// [lifetime].
  String? get code => switch (_invite) {
    (:final code, :final at, via: _) when now().difference(at) < lifetime =>
      code,
    _ => null,
  };

  /// How [code] reached the app: a link or a paste.
  /// [JoinMethod.link] for any other code.
  JoinMethod methodOf(String code) => switch (_invite) {
    (code: final kept, at: _, :final via)
        when kept == normalizeInviteCode(code) && this.code != null =>
      via,
    _ => JoinMethod.link,
  };

  /// Codes answered since the app started (joined, cancelled, invalid):
  /// the router still sees them in the location for a moment (the join
  /// screen's `/join/<code>` while it hands over to the list) and must not
  /// keep them again.
  final _answered = <String>{};

  /// Keeps [code] from a link, or from where [via] says. A code the
  /// server could never have made is not kept (the join screen still says
  /// it is invalid), nor one answered already, unless the user typed it
  /// again (JH2's code step, job 271): no location carries that one. The
  /// same code again keeps its first time and way.
  void remember(String code, {JoinMethod via = JoinMethod.link}) {
    final normalized = normalizeInviteCode(code);
    if (via == JoinMethod.code) {
      _answered.remove(normalized);
    }
    if (!_codePattern.hasMatch(normalized) ||
        _answered.contains(normalized) ||
        this.code == normalized) {
      return;
    }
    _invite = (code: normalized, at: now(), via: via);
    unawaited(_store.savePendingInvite(_invite));
  }

  /// After a join, a cancel or an invalid code: the invite is answered.
  void clear() {
    if (_invite case (:final code, at: _, via: _)) {
      _answered.add(code);
      _invite = null;
      unawaited(_store.savePendingInvite(null));
    }
  }

  /// After the server refused [code]: answered if it is the pending one. A
  /// typo in the field does not drop the link the user came with.
  void refused(String code) {
    if (this.code == normalizeInviteCode(code)) {
      clear();
    }
  }

  /// After a sign-out: nothing pending, and a link opened again is kept
  /// again (for the next sign-in).
  void signedOut() {
    _answered.clear();
    if (_invite != null) {
      _invite = null;
      unawaited(_store.savePendingInvite(null));
    }
  }
}
