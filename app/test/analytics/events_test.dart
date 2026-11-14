import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the catalog is the spec list, nothing more', () {
    expect(eventCatalog.keys.toSet(), {
      'first_open',
      'household_created',
      'household_switched',
      'invite_accepted',
      'invite_sent',
      'member_removed',
      'join_requested',
      'join_request_decided',
      'item_added',
      'item_ticked',
      'category_reordered',
      'store_reordered',
      'list_created',
      'list_switched',
      'item_claimed',
      'feedback_submitted',
      'item_categorized',
      'dedupe_hint_shown',
      'dedupe_hint_merged',
      'dedupe_hint_ignored',
      'paywall_viewed',
      'review_prompt_requested',
      'onboarding_completed',
      'hint_shown',
      'hint_dismissed',
      'hint_acted',
      'checklist_step_done',
      'checklist_dismissed',
      'shop_started',
      'shop_asked',
      'shop_ended',
      'price_entered',
      'trip_total_viewed',
      'scan_started',
      'off_miss',
      'trip_logged',
    });
  });

  const allowed = <(String, Map<String, Object>)>[
    ('first_open', {}),
    ('household_created', {}),
    ('household_created', {'default_stores': true}),
    ('household_created', {'default_stores': false}),
    ('household_created', {'store_count': 0}),
    ('household_created', {'store_count': 4}),
    ('household_created', {'store_count': 2, 'context': 'onboarding'}),
    ('household_created', {'context': 'switcher'}),
    ('household_switched', {}),
    ('invite_accepted', {'method': 'link'}),
    ('invite_sent', {'channel': 'share_sheet', 'context': 'onboarding'}),
    ('invite_sent', {'channel': 'copy_link', 'context': 'settings'}),
    ('invite_sent', {'channel': 'copy_code', 'context': 'onboarding'}),
    ('invite_accepted', {'method': 'code'}),
    ('invite_accepted', {'method': 'paste'}),
    (
      'invite_sent',
      {'channel': 'share_sheet', 'context': 'switcher', 'kind': 'group'},
    ),
    (
      'invite_sent',
      {'channel': 'copy_link', 'context': 'household', 'kind': 'person'},
    ),
    ('member_removed', {}),
    ('join_requested', {}),
    ('join_request_decided', {'approved': true}),
    ('join_request_decided', {'approved': false}),
    ('item_added', {'source': 'typed'}),
    ('item_added', {'source': 'spoken'}),
    (
      'item_added',
      {'source': 'suggestion', 'actor_role': 'member', 'household_size': 3},
    ),
    ('item_ticked', {'actor_role': 'owner', 'household_size': 2}),
    ('item_ticked', {'actor_role': 'admin', 'household_size': 2}),
    ('item_ticked', {}),
    (
      'onboarding_completed',
      {
        'kind': 'club',
        'kind_count': 2,
        'item_count': 12,
        'store_count': 3,
        'invited': true,
      },
    ),
    ('onboarding_completed', {'kind': 'skipped'}),
    ('category_reordered', {'scope': 'default'}),
    ('category_reordered', {'scope': 'store'}),
    ('store_reordered', {}),
    ('list_created', {}),
    ('list_switched', {}),
    ('item_claimed', {}),
    ('item_claimed', {'actor_role': 'member', 'household_size': 12}),
    ('review_prompt_requested', {}),
    ('paywall_viewed', {'entry_point': 'more'}),
    ('paywall_viewed', {'entry_point': 'integrations'}),
    ('paywall_viewed', {'entry_point': 'history'}),
    ('paywall_viewed', {'entry_point': 'trip'}),
    (
      'feedback_submitted',
      {
        'category': 'bug',
        'entry_point': 'settings',
        'screen': 'list',
        'contact_ok': true,
      },
    ),
    (
      'feedback_submitted',
      {
        'category': 'none',
        'entry_point': 'settings',
        'screen': 'account',
        'contact_ok': false,
      },
    ),
  ];
  final allowed32a = <(String, Map<String, Object>)>[
    for (final via in categorizedVia) ('item_categorized', {'via': via}),
    for (final hint in ['shown', 'merged', 'ignored']) ...[
      ('dedupe_hint_$hint', <String, Object>{}),
      ('dedupe_hint_$hint', {'actor_role': 'member', 'household_size': 2}),
    ],
  ];
  final allowed168b = <(String, Map<String, Object>)>[
    for (final event in ['hint_shown', 'hint_dismissed', 'hint_acted'])
      for (final id in HintId.values) (event, {'hint_id': id.wire}),
    for (final step in ['invite', 'first_shop', 'assistant'])
      ('checklist_step_done', {'step': step}),
    for (final open in [0, 3]) ('checklist_dismissed', {'open_steps': open}),
  ];
  const allowed195 = <(String, Map<String, Object>)>[
    ('shop_started', {}),
    ('shop_started', {'source': 'ask'}),
    ('shop_started', {'source': 'manual'}),
    ('shop_asked', {'answer': 'yes'}),
    ('shop_asked', {'answer': 'no'}),
    ('shop_asked', {'answer': 'take_back'}),
    ('shop_ended', {'reason': 'user', 'minutes': 'lt15'}),
    ('shop_ended', {'reason': 'auto', 'minutes': '15to30'}),
    ('shop_ended', {'reason': 'user', 'minutes': '30to60'}),
    ('shop_ended', {'reason': 'user', 'minutes': '60to120'}),
    ('shop_ended', {'reason': 'auto', 'minutes': 'gt120'}),
    ('price_entered', {'confirmed': false}),
    ('price_entered', {'confirmed': true}),
    ('trip_total_viewed', {'final': false}),
    ('trip_total_viewed', {'final': true}),
    ('scan_started', {}),
    ('off_miss', {}),
    ('trip_logged', {'source': 'manual'}),
    ('trip_logged', {'source': 'prompt'}),
    ('item_added', {'source': 'scan'}),
    (
      'item_added',
      {'source': 'scan', 'actor_role': 'owner', 'household_size': 2},
    ),
  ];
  for (final (event, properties) in [
    ...allowed,
    ...allowed32a,
    ...allowed168b,
    ...allowed195,
  ]) {
    test('allows $event $properties', () {
      expect(() => checkEvent(event, properties), returnsNormally);
    });
  }

  const refused = <(String, Map<String, Object>, String)>[
    ('household_joined', {}, 'the old name'),
    ('onboarding_completed', {'kind': 'Kegelclub'}, 'the Andere words'),
    ('onboarding_completed', {'name': 'Familie Trost'}, 'the household name'),
    ('onboarding_completed', {'item_count': 501}, 'over 500 items'),
    ('onboarding_completed', {'items': 'Milch'}, 'an item'),
    ('paywall_viewed', {'entry_point': 'list'}, 'an entry the page has not'),
    ('paywall_viewed', {'price': '9,99 €'}, 'a price'),
    ('integration_blocked', {}, 'server-only'),
    ('purchase_completed', {}, 'server-only'),
    ('item_added', {'source': 'Hafermilch'}, 'an item name as source'),
    ('item_added', {'name': 'Hafermilch'}, 'an item name property'),
    ('item_added', {'source': 'mcp'}, 'a source the app cannot know'),
    ('item_ticked', {'store': 'Lidl'}, 'a store name'),
    ('item_ticked', {'actor_role': 'Peter'}, 'a display name as role'),
    ('item_ticked', {'household_size': 0}, 'a size below 1'),
    ('item_ticked', {'household_size': 101}, 'a size above 100'),
    ('item_ticked', {'household_size': '2'}, 'a size as text'),
    ('invite_accepted', {'method': 'ABCD2345'}, 'an invite code'),
    ('household_created', {'name': 'Familie Trost'}, 'the household name'),
    ('household_created', {'default_stores': 'yes'}, 'stores as text'),
    ('household_created', {'store_count': 'REWE'}, 'a store name'),
    ('household_created', {'store_count': 51}, 'over 50 stores'),
    ('household_created', {'context': 'settings'}, 'a context not built'),
    ('household_switched', {'household': 'Zuhause'}, 'the household name'),
    ('household_switched', {'from': 'h1', 'to': 'h2'}, 'household ids'),
    ('invite_sent', {'code': 'ABCD2345'}, 'the code'),
    (
      'invite_sent',
      {'link': 'https://app.snacklist.app/join/ABCD2345'},
      'the link',
    ),
    ('invite_sent', {'channel': 'whatsapp'}, 'an app the sheet picked'),
    ('invite_sent', {'context': '/welcome/invite'}, 'a path as context'),
    ('invite_sent', {'kind': 'family'}, "the household's kind as kind"),
    ('member_removed', {'user': 'lea'}, 'who was removed'),
    ('member_removed', {'name': 'Lea'}, 'their name'),
    ('join_requested', {'household': 'Sommerfest'}, 'the household name'),
    ('join_request_decided', {'approved': 'yes'}, 'the answer as text'),
    ('join_request_decided', {'user': 'lea'}, 'who asked'),
    ('invite_accepted', {}, 'fine without method? no: see below'),
    ('category_reordered', {'scope': 'Obst & Gemüse'}, 'a category name'),
    ('store_reordered', {'ids': 'a,b'}, 'a list of ids'),
    ('list_created', {'name': 'Sommerfest'}, 'the list name'),
    ('list_switched', {'list': 'Baumarkt'}, 'the list name'),
    ('list_switched', {'list_id': 'l2'}, 'a list id'),
    ('item_claimed', {'quantity': '2 Kuchen'}, 'the amount brought'),
    ('item_claimed', {'item': 'Kuchen'}, 'the item name'),
    ('review_prompt_requested', {'shown': true}, 'whether it showed'),
    ('review_prompt_requested', {'items_added': 25}, 'a usage count'),
    ('first_open', {'email': 'peter@example.com'}, 'an e-mail'),
    ('feedback_submitted', {'message': 'Der Haken hängt'}, 'the note'),
    ('feedback_submitted', {'category': 'Bug'}, 'a label as category'),
    ('feedback_submitted', {'entry_point': 'shake'}, 'an entry not built'),
    ('feedback_submitted', {'screen': '/join/ABCD2345'}, 'a path as screen'),
    ('feedback_submitted', {'screen': 'Milch'}, 'an item as screen'),
    ('feedback_submitted', {'contact_ok': 'yes'}, 'contact as text'),
    ('item_categorized', {'via': 'Karotten'}, 'an item name as via'),
    ('item_categorized', {'name': 'Möhren'}, 'an item name property'),
    ('item_categorized', {'via': 'mor'}, 'a canonical key'),
    ('dedupe_hint_shown', {'item': 'Möhren'}, 'the matched item'),
    ('dedupe_hint_merged', {'quantity': '2'}, 'a quantity'),
    ('feedback_submitted', {'email': 'max@gmail.com'}, 'an e-mail'),
    ('hint_shown', {'hint_id': 'Halte einen Artikel'}, 'the hint text'),
    ('hint_shown', {'hint_id': 'tips'}, 'an id not in the catalogue'),
    ('hint_acted', {'target': '/more/invites'}, 'where it led'),
    ('checklist_step_done', {'step': 'started'}, 'the step done from start'),
    ('checklist_dismissed', {'open_steps': 4}, 'more steps than there are'),
    ('shop_started', {'store': 'Lidl'}, 'the store name'),
    ('shop_started', {'store_id': 's1'}, 'a store id'),
    ('shop_started', {'source': 'siri'}, 'a source the app has not'),
    ('shop_asked', {'answer': 'Ja, Einkauf starten'}, 'the button text'),
    ('shop_asked', {'item': 'Milch'}, 'the ticked item'),
    ('shop_ended', {'minutes': 25}, 'the exact minutes'),
    ('shop_ended', {'minutes': '25'}, 'minutes as text'),
    ('shop_ended', {'reason': 'timeout'}, 'a reason the app has not'),
    ('shop_ended', {'stores': 'Lidl, Rewe'}, 'the stores'),
    ('shop_ended', {'paid_cents': 2345}, 'the amount paid'),
    ('shop_ended', {'items': 6}, 'the item count'),
    ('price_entered', {'price': 1.99}, 'the price'),
    ('price_entered', {'price_cents': 199}, 'the price in cents'),
    ('price_entered', {'confirmed': 'yes'}, 'confirmed as text'),
    ('price_entered', {'item': 'Hafermilch'}, 'the item'),
    ('trip_total_viewed', {'total': 42.17}, 'the total'),
    ('trip_total_viewed', {'final': 1}, 'final as a number'),
    ('trip_total_viewed', {'currency': 'EUR'}, 'a currency'),
    ('scan_started', {'ean': '4006381333931'}, 'the EAN'),
    ('off_miss', {'ean': '4006381333931'}, 'the EAN'),
    ('off_miss', {'product': 'Hafermilch'}, 'a product name'),
    ('trip_logged', {'source': 'receipt'}, 'a source the app has not'),
    ('trip_logged', {'store': 'Lidl'}, 'the store'),
    ('trip_logged', {'items': 'Milch'}, 'the items'),
    ('item_added', {'source': 'barcode'}, 'the other word for scan'),
    ('item_added', {'ean': '4006381333931'}, 'the EAN of a scanned add'),
  ];
  for (final (event, properties, why) in refused) {
    if (event == 'invite_accepted' && properties.isEmpty) {
      continue;
    }
    test('refuses $event with $why', () {
      expect(() => checkEvent(event, properties), throwsA(isA<RefusedEvent>()));
    });
  }

  test("a trip's minutes go out as their bucket (job 234)", () {
    expect(
      [
        for (final m in [0, 14, 15, 29, 30, 59, 60, 119, 120, 600])
          ShopMinutes.of(Duration(minutes: m)).wire,
      ],
      [
        'lt15',
        'lt15',
        '15to30',
        '15to30',
        '30to60',
        '30to60',
        '60to120',
        '60to120',
        'gt120',
        'gt120',
      ],
    );
  });

  test('a refusal never repeats the value', () {
    try {
      checkEvent('item_added', {'source': 'Hafermilch'});
      fail('not refused');
    } on RefusedEvent catch (e) {
      expect('$e', isNot(contains('Hafermilch')));
    }
  });

  test('a free-text property can only be added as an explicit rule', () {
    for (final rules in eventCatalog.values) {
      for (final rule in rules.values) {
        expect(
          rule,
          isNot(isA<OneOf>().having((r) => r.values, 'values', isEmpty)),
        );
      }
    }
  });
}
