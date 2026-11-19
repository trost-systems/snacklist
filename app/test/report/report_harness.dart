import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/report/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../feedback/fb2_harness.dart' show key, tapKey;
import '../list/fake_repository.dart';
import '../more/more_harness.dart';
import 'fakes.dart';

/// Shared by the report tests and their review screenshots (job 281).
const report = {reportContentEntryFlag};
const reportFb4 = {reportContentEntryFlag, feedbackFb4Flag};

const mia = Reporter(name: 'Mia Brandt', email: 'mia.brandt@example.com');

/// Zuhause's lists and items: oat milk on the weekly shop, soap on the
/// party list.
void seedHousehold(FakeRepository repo) {
  repo
    ..lists = const [
      HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0),
      HouseholdList(id: 'party', name: 'Party am Samstag', position: 1),
    ]
    ..remoteAdd('Hafermilch', listId: 'weekly')
    ..remoteAdd('Seife', listId: 'party');
}

String location(More more) =>
    more.router.routerDelegate.currentConfiguration.uri.toString();

/// Scrolls the innermost scroll view until [k] is built and on screen.
Future<void> show(WidgetTester tester, String k) async {
  await tester.scrollUntilVisible(
    key(k),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

Future<void> openRow(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    key('more-feedback'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tapKey(tester, 'more-feedback');
}

/// More, its feedback row, and the report form from the hub (FB4) or the
/// feedback form.
Future<More> openForm(
  WidgetTester tester, {
  Set<String> flags = report,
  FakeReportRepository? reports,
}) async {
  final more = await pumpMore(
    tester,
    flags: flags,
    report: reports,
    seed: seedHousehold,
  );
  await openRow(tester);
  await tapKey(tester, 'report-entry');
  expect(key('report-form'), findsOneWidget);
  return more;
}

/// The row's subtitle, if it has one.
Finder rowText(String text) =>
    find.descendant(of: key('more-feedback'), matching: find.text(text));

Future<void> pickItem(WidgetTester tester, String id) async {
  await show(tester, 'report-where-choose');
  await tapKey(tester, 'report-where-choose');
  expect(key('report-picker'), findsOneWidget);
  await tester.scrollUntilVisible(
    key('report-pick-item-$id'),
    100,
    scrollable: find
        .descendant(of: key('report-picker'), matching: find.byType(Scrollable))
        .last,
  );
  await tapKey(tester, 'report-pick-item-$id');
}

Future<void> pickElsewhere(WidgetTester tester) async {
  await show(tester, 'report-where-choose');
  await tapKey(tester, 'report-where-choose');
  await tester.scrollUntilVisible(
    key('report-pick-elsewhere'),
    100,
    scrollable: find
        .descendant(of: key('report-picker'), matching: find.byType(Scrollable))
        .last,
  );
  await tapKey(tester, 'report-pick-elsewhere');
}

/// Everything required, about [category]: the oat milk and a reason.
Future<void> fillIn(
  WidgetTester tester, {
  ReportCategory category = ReportCategory.hate,
}) async {
  await show(tester, 'report-category-${category.wire}');
  await tapKey(tester, 'report-category-${category.wire}');
  await pickItem(tester, 'remote-0');
  await show(tester, 'report-reason');
  await tester.enterText(
    key('report-reason'),
    '  Dieser Eintrag beleidigt meinen Nachbarn mit vollem Namen.  ',
  );
  await tester.pump();
  await show(tester, 'report-good-faith');
  await tapKey(tester, 'report-good-faith');
}

Future<void> send(WidgetTester tester) async {
  await show(tester, 'report-send');
  await tapKey(tester, 'report-send');
}

/// Empties the prefilled name and e-mail.
Future<void> clearContact(WidgetTester tester) async {
  for (final k in ['report-name', 'report-email']) {
    await show(tester, k);
    await tester.enterText(key(k), '');
    await tester.pump();
  }
}
