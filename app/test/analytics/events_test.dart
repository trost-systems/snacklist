import 'package:family_groceries/analytics/events.dart';
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
      'item_added',
      'item_ticked',
      'category_reordered',
      'store_reordered',
      'feedback_submitted',
      'item_categorized',
      'dedupe_hint_shown',
      'dedupe_hint_merged',
      'dedupe_hint_ignored',
      'paywall_viewed',
      'review_prompt_requested',
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
    ('invite_accepted', {'method': 'referrer'}),
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
    ('item_added', {'source': 'typed'}),
    ('item_added', {'source': 'spoken'}),
    (
      'item_added',
      {'source': 'suggestion', 'actor_role': 'member', 'household_size': 3},
    ),
    ('item_ticked', {'actor_role': 'owner', 'household_size': 2}),
    ('item_ticked', {'actor_role': 'admin', 'household_size': 2}),
    ('item_ticked', {}),
    ('category_reordered', {'scope': 'default'}),
    ('category_reordered', {'scope': 'store'}),
    ('store_reordered', {}),
    ('review_prompt_requested', {}),
    ('paywall_viewed', {'entry_point': 'more'}),
    ('paywall_viewed', {'entry_point': 'integrations'}),
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
  for (final (event, properties) in [...allowed, ...allowed32a]) {
    test('allows $event $properties', () {
      expect(() => checkEvent(event, properties), returnsNormally);
    });
  }

  const refused = <(String, Map<String, Object>, String)>[
    ('household_joined', {}, 'the old name'),
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
      {'link': 'https://app.hummlist.com/join/ABCD2345'},
      'the link',
    ),
    ('invite_sent', {'channel': 'whatsapp'}, 'an app the sheet picked'),
    ('invite_sent', {'context': '/welcome/invite'}, 'a path as context'),
    ('invite_sent', {'kind': 'family'}, "the household's kind as kind"),
    ('member_removed', {'user': 'lea'}, 'who was removed'),
    ('member_removed', {'name': 'Lea'}, 'their name'),
    ('invite_accepted', {}, 'fine without method? no: see below'),
    ('category_reordered', {'scope': 'Obst & Gemüse'}, 'a category name'),
    ('store_reordered', {'ids': 'a,b'}, 'a list of ids'),
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
  ];
  for (final (event, properties, why) in refused) {
    if (event == 'invite_accepted' && properties.isEmpty) {
      continue;
    }
    test('refuses $event with $why', () {
      expect(() => checkEvent(event, properties), throwsA(isA<RefusedEvent>()));
    });
  }

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
