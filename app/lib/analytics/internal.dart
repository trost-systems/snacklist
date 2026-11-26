import 'package:flutter/foundation.dart';

/// Whether events from this install, user and household are ours (Peter's
/// family, test accounts, development builds) rather than a customer's.
/// Every gate insight filters `is_internal = true` out (docs/ANALYTICS.md).
///
/// The rules, each enough on its own:
/// - a debug or profile build ([releaseBuild] false);
/// - a user in the tester group `internal` ([internalTesterGroup], the
///   server's `tester_groups`, job 337);
/// - a household listed in the `ANALYTICS_INTERNAL_HOUSEHOLDS` define;
/// - a household with a RevenueCat promotional grant ([testerHousehold]:
///   testers', App and Play Review's free premium; their households never
///   count, as the server's `household_internal` says);
/// - a user whose e-mail domain is a test domain: the reserved top-level
///   domains `.test`, `.invalid`, `.example`, `.localhost` (the fixtures'
///   `fg.test`, `fg-test.invalid`, the e2e `example.test`) and the
///   reserved `example.com/.net/.org`, plus any domain in
///   `ANALYTICS_INTERNAL_EMAIL_DOMAINS`;
/// - a test account ([isTestAccount]).
///
/// To add a rule, add a parameter here and a case to
/// test/analytics/internal_test.dart. The e-mail is read on the device and
/// never sent.
bool isInternal({
  required bool releaseBuild,
  required Set<String> testerGroups,
  required String? householdId,
  required String? email,
  Set<String> providers = const {},
  Set<String> internalHouseholds = const {},
  Set<String> internalEmailDomains = const {},
  String? testerHousehold,
}) =>
    !releaseBuild ||
    testerGroups.contains(internalTesterGroup) ||
    (householdId != null && internalHouseholds.contains(householdId)) ||
    (householdId != null && householdId == testerHousehold) ||
    (email != null && _testDomain(email, internalEmailDomains)) ||
    isTestAccount(email: email, providers: providers);

/// Whether the signed-in account is a test account, whose installs send no
/// analytics at all in a release build (job 466): Play's pre-launch robots
/// and our fixtures, not people. Each rule is enough on its own:
/// - an e-mail on a reserved test domain (`.test`, `.invalid`, `.example`,
///   `.localhost`, `example.com/.net/.org`; not the
///   `ANALYTICS_INTERNAL_EMAIL_DOMAINS`, which are people);
/// - a Google-only account whose e-mail is the shape of Play's pre-launch
///   test accounts, `<letters>.<five digits>@gmail.com`, the pattern the
///   purge of Google test users (DEL-G1) matches.
///
/// [providers] are the account's sign-in providers (`app_metadata.providers`).
/// The e-mail is read on the device and never sent.
bool isTestAccount({required String? email, required Set<String> providers}) {
  if (email == null) {
    return false;
  }
  final address = email.trim().toLowerCase();
  return _testDomain(address, const {}) ||
      (setEquals(providers, const {'google'}) &&
          _playTestAccount.hasMatch(address));
}

final _playTestAccount = RegExp(r'^[a-z]+[a-z]+\.[0-9]{5}@gmail\.com$');

/// The tester group whose members count as internal (docs/ANALYTICS.md,
/// "Tester groups").
const internalTesterGroup = 'internal';

/// [groups] as the `tester_groups` flag property: sorted, comma-joined,
/// empty for none, so a flag can target `tester_groups icontains beta-de`.
String testerGroupsProperty(Set<String> groups) =>
    (groups.toList()..sort()).join(',');

const _reservedTopLevel = {'test', 'invalid', 'example', 'localhost'};
const _reservedDomains = {'example.com', 'example.net', 'example.org'};

bool _testDomain(String email, Set<String> extra) {
  final at = email.lastIndexOf('@');
  if (at < 0) {
    return false;
  }
  final domain = email.substring(at + 1).toLowerCase().trim();
  bool listed(String d) => domain == d || domain.endsWith('.$d');
  return _reservedTopLevel.contains(domain.split('.').last) ||
      _reservedDomains.any(listed) ||
      extra.any((d) => listed(d.toLowerCase()));
}

/// A comma-separated define as a set, blanks dropped.
Set<String> csvSet(String csv) => {
  for (final part in csv.split(','))
    if (part.trim().isNotEmpty) part.trim().toLowerCase(),
};
