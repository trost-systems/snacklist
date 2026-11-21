import 'package:family_groceries/analytics/internal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool internal({
    bool release = true,
    Set<String> groups = const {},
    String? household,
    String? email,
    Set<String> households = const {},
    Set<String> domains = const {},
    String? tester,
  }) => isInternal(
    releaseBuild: release,
    testerGroups: groups,
    householdId: household,
    email: email,
    internalHouseholds: households,
    internalEmailDomains: domains,
    testerHousehold: tester,
  );

  test('a customer is not internal', () {
    expect(internal(email: 'anna@gmail.com', household: 'h1'), isFalse);
    expect(internal(email: 'anna@test.de'), isFalse);
    expect(internal(email: 'anna@invalid.com'), isFalse);
    expect(internal(), isFalse);
  });

  test('debug and profile builds are internal', () {
    expect(internal(release: false, email: 'anna@gmail.com'), isTrue);
  });

  test('the tester group internal is internal; other groups are not', () {
    expect(internal(groups: {'internal'}), isTrue);
    expect(internal(groups: {'beta-de', 'internal'}), isTrue);
    expect(internal(groups: {'beta-de'}), isFalse);
    expect(internal(groups: {'internal-de'}), isFalse);
  });

  test('a release build alone is not internal: no mark on the device', () {
    expect(internal(email: 'lea@gmail.com', household: 'h1'), isFalse);
  });

  test('the tester_groups flag property is sorted and comma-joined', () {
    expect(testerGroupsProperty({}), '');
    expect(testerGroupsProperty({'internal'}), 'internal');
    expect(
      testerGroupsProperty({'internal', 'beta-de', 'alexa'}),
      'alexa,beta-de,internal',
    );
  });

  test('listed households are internal', () {
    expect(internal(household: 'h1', households: {'h1'}), isTrue);
    expect(internal(household: 'h2', households: {'h1'}), isFalse);
  });

  test(
    'a household with a RevenueCat promotional grant (testers) is internal',
    () {
      expect(internal(household: 'h1', tester: 'h1'), isTrue);
      expect(
        internal(household: 'h2', tester: 'h1'),
        isFalse,
        reason: 'moved on',
      );
      expect(internal(tester: 'h1'), isFalse, reason: 'no household');
    },
  );

  test('test domains are internal', () {
    for (final email in [
      'peter@fg.test',
      'Lea@FG-TEST.invalid',
      'e2e-1@example.test',
      'x@sub.example.com',
      'x@example.org',
      'x@localhost',
    ]) {
      expect(internal(email: email), isTrue, reason: email);
    }
  });

  test('extra domains count with their subdomains', () {
    expect(
      internal(email: 'p@petertrost.com', domains: {'petertrost.com'}),
      isTrue,
    );
    expect(
      internal(email: 'p@mail.petertrost.com', domains: {'petertrost.com'}),
      isTrue,
    );
    expect(
      internal(email: 'p@notpetertrost.com', domains: {'petertrost.com'}),
      isFalse,
    );
  });

  test('csvSet trims, lower-cases and drops blanks', () {
    expect(csvSet(' A, b ,,'), {'a', 'b'});
    expect(csvSet(''), isEmpty);
  });
}
