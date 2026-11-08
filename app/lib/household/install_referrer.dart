import 'package:family_groceries/analytics/events.dart' show JoinMethod;
import 'package:family_groceries/household/pending_invite.dart';
import 'package:flutter/services.dart';
import 'package:play_install_referrer/play_install_referrer.dart';

/// What the Play Store says about this install: the referrer of the store
/// link (`invite=<code>` from the join page) and when it was clicked.
typedef InstallReferrer = ({String? referrer, DateTime? clickedAt});

/// Takes an invite from the Play Store's install referrer (job 169b W2):
/// someone opened a join link, installed the app from the Play Store, and
/// now opens it. On the first start only ([android] builds); the code goes
/// into [pending] as if the link had been opened, dated by the store
/// click, so an old one lapses. Reads nothing but `invite`. A failure
/// counts as read, except the store's timeout, which the next start
/// retries.
Future<void> takeInstallReferrer(
  PendingInviteStore store,
  PendingInvite pending, {
  required bool android,
  Future<InstallReferrer> Function() read = _playStore,
}) async {
  if (!android || await store.installReferrerRead()) {
    return;
  }
  try {
    final (:referrer, :clickedAt) = await read();
    if (inviteInReferrer(referrer) case final code?) {
      pending.remember(code, via: JoinMethod.referrer, at: clickedAt);
    }
  } on PlatformException catch (e) {
    if (e.code == 'TIMEOUT') {
      return;
    }
  } on Object {
    // No Play services, a sideloaded build: nothing to take.
  }
  await store.saveInstallReferrerRead();
}

Future<InstallReferrer> _playStore() async {
  final details = await PlayInstallReferrer.installReferrer;
  final clicked = details.referrerClickTimestampSeconds;
  return (
    referrer: details.installReferrer,
    clickedAt: clicked > 0
        ? DateTime.fromMillisecondsSinceEpoch(clicked * 1000, isUtc: true)
        : null,
  );
}
