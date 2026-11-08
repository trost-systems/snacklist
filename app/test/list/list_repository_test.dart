import 'dart:convert';

import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  /// A repository whose PostgREST answers every write with [status] and [body].
  SupabaseListRepository answering(int status, Object body) =>
      SupabaseListRepository(
        SupabaseClient(
          'http://127.0.0.1:1',
          'sb_publishable_test',
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode(body),
              status,
              headers: {'content-type': 'application/json'},
              request: request,
            ),
          ),
        ),
        'household',
      );

  final add = AddItem(
    Item(
      id: 'item-1',
      name: 'Brot',
      status: ItemStatus.active,
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
    ),
  );

  test('a write refused by the database is a rejection', () async {
    final repo = answering(409, {
      'code': '23505',
      'message': 'duplicate key value violates unique constraint',
    });
    await expectLater(
      repo.send(add),
      throwsA(isA<RejectedOp>().having((e) => e.nameTaken, 'nameTaken', true)),
    );
  });

  group('the server in trouble is no rejection, so the op stays queued '
      '(job 161)', () {
    /// A repository whose every answer is [status] with a plain [body].
    SupabaseListRepository plain(int status, String body) =>
        SupabaseListRepository(
          SupabaseClient(
            'http://127.0.0.1:1',
            'sb_publishable_test',
            httpClient: MockClient(
              (request) async => http.Response(
                body,
                status,
                headers: {'content-type': 'text/plain'},
                request: request,
              ),
            ),
          ),
          'household',
        );

    const trouble = {
      'PGRST301': 401, // JWT expired
      'PGRST303': 401,
      'PGRST000': 503, // no database connection
      'PGRST002': 503,
      '08006': 503, // connection failure
      '40001': 500, // serialization failure
      '40P01': 500, // deadlock
      '53300': 503, // too many connections
      '57014': 500, // statement timeout
      '57P01': 503, // admin shutdown
      '58030': 500, // io error
      'XX000': 500, // internal error
    };
    const refusals = {
      '23505': 409, // unique violation
      '42501': 403, // row-level security
      'P0001': 400, // raised by a function
      '22001': 400, // value too long
      'PGRST116': 406, // not one row
      'PGRST204': 400, // unknown column
    };

    test('PostgREST codes and SQLSTATEs', () async {
      for (final MapEntry(key: code, value: status) in trouble.entries) {
        await expectLater(
          answering(status, {'code': code, 'message': 'trouble'}).send(add),
          throwsA(isA<ServerTrouble>()),
          reason: code,
        );
      }
      for (final MapEntry(key: code, value: status) in refusals.entries) {
        await expectLater(
          answering(status, {'code': code, 'message': 'no'}).send(add),
          throwsA(isA<RejectedOp>()),
          reason: code,
        );
      }
    });

    test('a 5xx with no PostgREST body, as a gateway sends', () async {
      for (final status in [500, 502, 503, 504]) {
        await expectLater(
          plain(status, 'Service Unavailable').send(add),
          throwsA(isA<ServerTrouble>()),
          reason: '$status',
        );
      }
      await expectLater(
        plain(404, 'Not Found').send(add),
        throwsA(isA<RejectedOp>()),
      );
    });

    test('reads map the same way, and a refused read stays an error, not '
        'trouble', () async {
      final down = plain(503, 'Service Unavailable');
      await expectLater(down.fetchItems(), throwsA(isA<ServerTrouble>()));
      await expectLater(down.fetchCatalog(), throwsA(isA<ServerTrouble>()));
      await expectLater(down.parse('Milch'), throwsA(isA<ServerTrouble>()));
      await expectLater(
        answering(403, {'code': '42501', 'message': 'no'}).fetchItems(),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('no answer at all is neither: the list is offline', () async {
      final repo = SupabaseListRepository(
        SupabaseClient(
          'http://127.0.0.1:1',
          'sb_publishable_test',
          httpClient: MockClient(
            (request) async => throw http.ClientException('refused'),
          ),
        ),
        'household',
      );
      await expectLater(
        repo.send(add),
        throwsA(allOf(isNot(isA<ServerTrouble>()), isNot(isA<RejectedOp>()))),
      );
      await expectLater(
        repo.fetchItems(),
        throwsA(isNot(isA<ServerTrouble>())),
      );
    });
  });

  group('an add answers with the row it is (put_item, job 64b)', () {
    Map<String, Object?> row(String id) => {
      'id': id,
      'name': 'Brot',
      'quantity': '1',
      'category_id': 'bakery',
      'store_id': 'bakery-store',
      'status': 'active',
      'created_at': '2026-10-28T00:00:00Z',
      'updated_at': '2026-10-28T00:00:00Z',
    };

    test('its own row', () async {
      final rows = await answering(200, [row('item-1')]).send(add);
      expect(rows.keys, ['item-1']);
      expect(rows['item-1']!.categoryId, 'bakery');
    });

    test(
      'the open item it already is: this id is gone, that row is there',
      () async {
        final rows = await answering(200, [row('leas-brot')]).send(add);
        expect(rows['item-1'], isNull);
        expect(rows.containsKey('item-1'), isTrue);
        expect(rows['leas-brot']!.storeId, 'bakery-store');
      },
    );

    test('no row: the item is gone', () async {
      expect(await answering(200, <Object>[]).send(add), {'item-1': null});
    });

    test(
      'a guessed category is left to the server, a picked one sent',
      () async {
        final sent = <Object?>[];
        final repo = SupabaseListRepository(
          SupabaseClient(
            'http://127.0.0.1:1',
            'sb_publishable_test',
            httpClient: MockClient((request) async {
              sent.add((jsonDecode(request.body) as Map)['p_category']);
              return http.Response(
                jsonEncode([row('item-1')]),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }),
          ),
          'household',
        );
        final guessed = add.item.copyWith(categoryId: 'bakery');
        await repo.send(AddItem(guessed, autoCategory: true));
        await repo.send(AddItem(guessed));
        expect(sent, [null, 'bakery']);
      },
    );
  });

  test('a dictated item keeps the brand and details the server split off '
      '(job 111)', () async {
    final repo = answering(200, {
      'speech': 'Verstanden: Windeln Pampers Größe 3, 2 l Milch.',
      'items': [
        {
          'name': 'Windeln',
          'brand': 'Pampers',
          'properties': 'Größe 3, Big Pack',
          'quantity': null,
          'storeId': 'dm',
        },
        {
          'name': 'Milch',
          'brand': null,
          'properties': null,
          'quantity': '2 l',
          'storeId': null,
        },
      ],
      'truncated': false,
    });
    final (:entries, :truncated) = await repo.splitSpoken(
      'Windeln Pampers Größe 3 Big Pack',
    );
    expect(truncated, isFalse);
    expect(
      entries.map(
        (e) => (e.name, e.brand, e.properties, e.quantity, e.storeId),
      ),
      [
        ('Windeln', 'Pampers', 'Größe 3, Big Pack', null, 'dm'),
        ('Milch', null, null, '2 l', null),
      ],
    );
  });

  test(
    'a dictated item shows in the category the server will give it, '
    'and an older voice function leaves it to the server (job 150)',
    () async {
      final repo = answering(200, {
        'speech': 'Verstanden: Pizza, Orangensaft.',
        'items': [
          {
            'name': 'Pizza',
            'brand': null,
            'properties': null,
            'quantity': null,
            'storeId': null,
            'categoryId': 'frozen',
          },
          {
            'name': 'Orangensaft',
            'brand': null,
            'properties': null,
            'quantity': null,
            'storeId': null,
          },
        ],
        'truncated': false,
      });
      final (:entries, truncated: _) = await repo.splitSpoken(
        'Pizza und Orangensaft',
      );
      expect(entries.map((e) => (e.name, e.categoryId)), [
        ('Pizza', 'frozen'),
        ('Orangensaft', null),
      ]);
    },
  );

  test('dictation asks the voice function for the split, in the shown '
      'household (job 169b)', () async {
    Object? sent;
    final repo = SupabaseListRepository(
      SupabaseClient(
        'http://127.0.0.1:1',
        'sb_publishable_test',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body);
          return http.Response(
            jsonEncode({'items': <Object>[], 'truncated': false}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      ),
      'household-b',
    );
    await repo.splitSpoken('Milch');
    expect(sent, {
      'text': 'Milch',
      'mode': 'parse',
      'split': true,
      'household': 'household-b',
    });
  });

  test('a dictated list cut at 30 items says so (job 111)', () async {
    final repo = answering(200, {
      'speech': 'Verstanden: …',
      'items': [
        for (var i = 0; i < 30; i++)
          {
            'name': 'Ding $i',
            'brand': null,
            'properties': null,
            'quantity': null,
          },
      ],
      'truncated': true,
    });
    final (:entries, :truncated) = await repo.splitSpoken('Ding 0, …');
    expect(entries, hasLength(30));
    expect(truncated, isTrue);
  });

  test('an add typed offline is split by parse_item when it syncs, as '
      'online (job 111)', () async {
    final calls = <String, Map<String, Object?>>{};
    final repo = SupabaseListRepository(
      SupabaseClient(
        'http://127.0.0.1:1',
        'sb_publishable_test',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final function = request.url.pathSegments.last;
          calls[function] = body;
          final answer = switch (function) {
            'parse_item' => [
              {
                'name': 'Windeln',
                'brand': 'Pampers',
                'properties': 'Größe 3',
                'quantity': null,
                'store_id': 'dm',
                'category_id': 'baby',
              },
            ],
            _ => [
              {
                'id': body['p_id'],
                'name': body['p_name'],
                'quantity': body['p_quantity'],
                'brand': body['p_brand'],
                'properties': body['p_properties'],
                'category_id': body['p_category'],
                'store_id': body['p_store'],
                'status': 'active',
                'created_at': '2026-11-05T00:00:00Z',
                'updated_at': '2026-11-05T00:00:00Z',
              },
            ],
          };
          return http.Response(
            jsonEncode(answer),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request,
          );
        }),
      ),
      'household',
    );
    final typed = Item(
      id: 'item-2',
      name: 'Windeln Pampers Größe 3',
      quantity: '2',
      status: ItemStatus.active,
      createdAt: DateTime.utc(2026, 11, 5),
      updatedAt: DateTime.utc(2026, 11, 5),
    );

    final rows = await repo.send(AddItem(typed, deviceParsed: true));

    expect(calls['parse_item'], {
      'p_household': 'household',
      'p_text': 'Windeln Pampers Größe 3',
    });
    final row = rows['item-2']!;
    expect(
      (row.name, row.brand, row.properties, row.quantity, row.storeId),
      ('Windeln', 'Pampers', 'Größe 3', '2', 'dm'),
    );
    expect(row.categoryId, 'baby');

    // „Ohne Laden“ picked offline: the parsed store is not taken.
    await repo.send(
      AddItem(typed.copyWith(), noStore: true, deviceParsed: true),
    );
    expect(calls['put_item']!['p_store'], isNull);
    expect(calls['put_item']!['p_no_store'], isTrue);
    expect(calls['put_item']!['p_brand'], 'Pampers');
  });

  test('an add the server parsed already goes to put_item as it is', () async {
    final paths = <String>[];
    final repo = SupabaseListRepository(
      SupabaseClient(
        'http://127.0.0.1:1',
        'sb_publishable_test',
        httpClient: MockClient((request) async {
          paths.add(request.url.pathSegments.last);
          return http.Response('[]', 200, request: request);
        }),
      ),
      'household',
    );
    await repo.send(add);
    expect(paths, ['put_item']);
  });

  test('a voice function without the split still adds the items', () async {
    final repo = answering(200, {
      'speech': 'Verstanden: Milch.',
      'items': [
        {'name': 'Milch', 'quantity': null},
      ],
      'truncated': false,
    });
    final (:entries, truncated: _) = await repo.splitSpoken('Milch');
    expect(entries.map((e) => (e.name, e.brand)), [('Milch', null)]);
  });

  test('a rename of an add typed offline is split by parse_item too '
      '(job 111)', () async {
    final calls = <String, Object?>{};
    final repo = SupabaseListRepository(
      SupabaseClient(
        'http://127.0.0.1:1',
        'sb_publishable_test',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body);
          calls[request.url.pathSegments.last] = body;
          final answer = request.url.pathSegments.last == 'parse_item'
              ? [
                  {
                    'name': 'Windeln',
                    'brand': 'Pampers',
                    'properties': 'Größe 4',
                    'quantity': null,
                  },
                ]
              : [
                  {
                    'id': 'item-3',
                    'name': 'Windeln',
                    'brand': 'Pampers',
                    'properties': 'Größe 4',
                    'status': 'active',
                    'created_at': '2026-11-05T00:00:00Z',
                    'updated_at': '2026-11-05T00:00:00Z',
                  },
                ];
          return http.Response(
            jsonEncode(answer),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request,
          );
        }),
      ),
      'household',
    );

    await repo.send(
      const EditItem(
        'item-3',
        ItemChanges(name: 'Windeln Pampers Größe 4'),
        deviceParsed: true,
      ),
    );

    expect(calls['parse_item'], {
      'p_household': 'household',
      'p_text': 'Windeln Pampers Größe 4',
    });
    expect(calls['items'], {
      'name': 'Windeln',
      'brand': 'Pampers',
      'properties': 'Größe 4',
    });
  });

  group('what each call asks the server and how it reads the answer', () {
    late List<http.Request> sent;

    /// A repository whose server answers each request with [answer]'s
    /// (status, body); the requests land in [sent].
    SupabaseListRepository server(
      (int, Object?) Function(http.Request request) answer,
    ) {
      sent = [];
      return SupabaseListRepository(
        SupabaseClient(
          'http://127.0.0.1:1',
          'sb_publishable_test',
          httpClient: MockClient((request) async {
            sent.add(request);
            final (status, body) = answer(request);
            return http.Response(
              jsonEncode(body),
              status,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        ),
        'household',
      );
    }

    String route(http.Request r) => '${r.method} ${r.url.path}';
    Object? params(http.Request r) => jsonDecode(r.body);

    Map<String, Object?> row(String id, {String status = 'active'}) => {
      'id': id,
      'name': 'Brot',
      'status': status,
      'created_at': '2026-10-28T00:00:00Z',
      'updated_at': '2026-10-28T00:00:00Z',
    };

    test(
      'the catalog is the household’s, members only with their role',
      () async {
        final repo = server(
          (r) => switch (r.url.pathSegments.last) {
            'categories' => (
              200,
              [
                {
                  'id': 'c1',
                  'name': 'Obst',
                  'sort_order': 1,
                  'seed_key': 'fruit',
                },
              ],
            ),
            'stores' => (
              200,
              [
                {'id': 's1', 'name': 'Lidl', 'sort_order': 1, 'seed_key': null},
              ],
            ),
            'store_category_order' => (
              200,
              [
                {
                  'store_id': 's1',
                  'category_id': 'c1',
                  'sort_order': 3,
                  'hidden': true,
                },
              ],
            ),
            'household_members_of' => (
              200,
              [
                {'user_id': 'peter', 'display_name': 'Peter', 'role': 'owner'},
                {'user_id': 'lea', 'display_name': 'Lea', 'role': 'member'},
              ],
            ),
            _ => (404, null),
          },
        );
        final catalog = await repo.fetchCatalog();
        expect(catalog.categories.single.seedKey, 'fruit');
        expect(catalog.stores.single.name, 'Lidl');
        expect(catalog.layout.single.hidden, isTrue);
        expect(
          [for (final m in catalog.members) '${m.displayName}:${m.role}'],
          ['Peter:owner', 'Lea:member'],
        );
        expect(
          jsonDecode(
            sent
                .singleWhere(
                  (r) => r.url.pathSegments.last == 'household_members_of',
                )
                .body,
          ),
          {'p_household': 'household'},
        );
        for (final table in ['categories', 'stores', 'store_category_order']) {
          final request = sent.singleWhere(
            (r) => r.url.pathSegments.last == table,
          );
          expect(
            request.url.queryParameters['household_id'],
            'eq.household',
            reason: table,
          );
        }
        for (final table in ['categories', 'stores']) {
          expect(
            sent
                .singleWhere((r) => r.url.pathSegments.last == table)
                .url
                .queryParameters['order'],
            'sort_order.asc.nullslast',
            reason: table,
          );
        }
      },
    );

    test(
      'the list is the active items, then the 50 newest bought ones',
      () async {
        final repo = server(
          (r) => r.url.queryParameters['status'] == 'eq.active'
              ? (200, [row('a')])
              : (200, [row('b', status: 'bought')]),
        );
        final items = await repo.fetchItems();
        expect([for (final i in items) i.id], ['a', 'b']);
        final bought = sent.singleWhere(
          (r) => r.url.queryParameters['status'] == 'eq.bought',
        );
        expect(bought.url.queryParameters['household_id'], 'eq.household');
        expect(bought.url.queryParameters['order'], 'bought_at.desc.nullslast');
        expect(bought.url.queryParameters['limit'], '50');
      },
    );

    test(
      'the usuals are every suggestion, with when they were last used',
      () async {
        final repo = server(
          (_) => (
            200,
            [
              {
                'name': 'Milch',
                'quantity': '2 l',
                'due': true,
                'last_used': '2026-10-01T08:00:00Z',
              },
              {
                'name': 'Salz',
                'quantity': null,
                'due': false,
                'last_used': null,
              },
            ],
          ),
        );
        final usuals = await repo.fetchUsuals();
        expect(route(sent.single), 'POST /rest/v1/rpc/suggest_items');
        expect(params(sent.single), {
          'p_household': 'household',
          'p_prefix': '',
          'p_limit': 200,
        });
        expect(usuals.first.due, isTrue);
        expect(usuals.first.lastUsed, DateTime.utc(2026, 10, 1, 8));
        expect(usuals.last.lastUsed, isNull);
      },
    );

    test('catalog edits call their function with the household', () async {
      final repo = server((_) => (200, null));
      final calls = <(Future<void> Function(), String, Object?)>[
        (
          () => repo.createCategory('Tiefkühl'),
          'create_category',
          {'p_household': 'household', 'p_name': 'Tiefkühl'},
        ),
        (
          () => repo.reorderCategories(['c2', 'c1']),
          'reorder_categories',
          {
            'p_household': 'household',
            'p_ids': ['c2', 'c1'],
          },
        ),
        (
          () => repo.reorderStores(['s2', 's1']),
          'reorder_stores',
          {
            'p_household': 'household',
            'p_ids': ['s2', 's1'],
          },
        ),
        (
          () => repo.renameStore('s1', 'Aldi'),
          'rename_store',
          {'p_store': 's1', 'p_name': 'Aldi'},
        ),
        (() => repo.deleteStore('s1'), 'delete_store', {'p_store': 's1'}),
        (
          () => repo.deleteCategory('c1'),
          'delete_category',
          {'p_category': 'c1', 'p_reassign_to': null},
        ),
        (
          () => repo.deleteCategory('c1', reassignTo: 'c2'),
          'delete_category',
          {'p_category': 'c1', 'p_reassign_to': 'c2'},
        ),
        (
          () => repo.setStoreLayout('s1', ['c2', 'c1'], {'c2'}),
          'set_store_layout',
          {
            'p_store': 's1',
            'p_categories': ['c2', 'c1'],
            'p_hidden': ['c2'],
          },
        ),
      ];
      for (final (call, function, expected) in calls) {
        await call();
        expect(route(sent.last), 'POST /rest/v1/rpc/$function');
        expect(params(sent.last), expected, reason: function);
      }
    });

    test('renaming a category writes its name', () async {
      final repo = server((_) => (204, null));
      await repo.renameCategory('c1', 'Backwaren');
      expect(route(sent.single), 'PATCH /rest/v1/categories');
      expect(sent.single.url.queryParameters['id'], 'eq.c1');
      expect(params(sent.single), {'name': 'Backwaren'});
    });

    test('a store name the household has is refused as taken', () async {
      final repo = server(
        (_) => (409, {'code': '23505', 'message': 'duplicate key'}),
      );
      await expectLater(
        repo.renameStore('s1', 'Lidl'),
        throwsA(
          isA<RejectedOp>().having((e) => e.nameTaken, 'nameTaken', true),
        ),
      );
      await expectLater(
        repo.createCategory('Obst'),
        throwsA(
          isA<RejectedOp>().having((e) => e.nameTaken, 'nameTaken', true),
        ),
      );
    });

    test('a refusal other than a taken name is no name clash', () async {
      final repo = server(
        (_) => (403, {'code': '42501', 'message': 'row-level security'}),
      );
      await expectLater(
        repo.reorderStores(['s1']),
        throwsA(
          isA<RejectedOp>()
              .having((e) => e.nameTaken, 'nameTaken', false)
              .having((e) => e.message, 'message', 'row-level security'),
        ),
      );
    });

    test('adding a store answers with its id', () async {
      final repo = server((_) => (200, 'store-9'));
      expect(await repo.addStore('Edeka'), 'store-9');
      expect(params(sent.single), {
        'p_household': 'household',
        'p_name': 'Edeka',
      });
    });

    test('the parser’s row reads the same as one object or a set', () async {
      final parsed = {
        'name': 'Milch',
        'quantity': '2 l',
        'brand': 'Weihenstephan',
        'store_id': 's1',
        'category_id': 'c1',
      };
      for (final answer in <Object>[
        parsed,
        [parsed],
      ]) {
        final entry = await server((_) => (200, answer)).parse('2 l Milch');
        expect(entry.name, 'Milch');
        expect(entry.quantity, '2 l');
        expect(entry.brand, 'Weihenstephan');
        expect(entry.storeId, 's1');
        expect(entry.categoryId, 'c1');
        expect(params(sent.single), {
          'p_household': 'household',
          'p_text': '2 l Milch',
        });
      }
    });

    test('suggestions keep the server’s order and source', () async {
      final repo = server(
        (_) => (
          200,
          [
            {'source': 'typed', 'name': 'Milch'},
            {'source': 'history', 'name': 'Milch', 'brand': 'Weihenstephan'},
          ],
        ),
      );
      final rows = await repo.suggest('Milch');
      expect(route(sent.single), 'POST /rest/v1/rpc/suggest_entries');
      expect(rows.map((s) => s.source), [
        SuggestionSource.typed,
        SuggestionSource.history,
      ]);
      expect(rows.last.entry.brand, 'Weihenstephan');
    });

    group('item ops', () {
      final at = DateTime.utc(2026, 10, 28, 9);

      test('ticking off at a store writes the status and the store', () async {
        final repo = server((_) => (200, [row('i1', status: 'bought')]));
        final rows = await repo.send(
          SetStatus('i1', ItemStatus.bought, at, storeId: 's1'),
        );
        expect(route(sent.single), 'PATCH /rest/v1/items');
        expect(sent.single.url.queryParameters['id'], 'eq.i1');
        expect(params(sent.single), {'status': 'bought', 'store_id': 's1'});
        expect(rows['i1']!.status, ItemStatus.bought);
      });

      test('ticking off without a store leaves the store alone', () async {
        final repo = server((_) => (200, [row('i1', status: 'bought')]));
        await repo.send(SetStatus('i1', ItemStatus.bought, at));
        expect(params(sent.single), {'status': 'bought'});
      });

      test(
        'an update that hits no row asks for the item: still there',
        () async {
          final repo = server(
            (r) => r.method == 'PATCH' ? (200, <Object>[]) : (200, [row('i1')]),
          );
          final rows = await repo.send(
            const EditItem('i1', ItemChanges(name: 'Vollkornbrot')),
          );
          expect(params(sent.first), {'name': 'Vollkornbrot'});
          expect(route(sent.last), 'GET /rest/v1/items');
          expect(sent.last.url.queryParameters['id'], 'eq.i1');
          expect(rows, {'i1': isNotNull});
        },
      );

      test('an update that hits no row asks for the item: gone', () async {
        final repo = server((r) => (200, <Object>[]));
        expect(await repo.send(SetStatus('i1', ItemStatus.active, at)), {
          'i1': null,
        });
        expect(sent.map(route), ['PATCH /rest/v1/items', 'GET /rest/v1/items']);
      });

      test('a delete answers that the item is gone', () async {
        final repo = server(
          (_) => (
            200,
            [
              {'id': 'i1'},
            ],
          ),
        );
        expect(await repo.send(const DeleteItem('i1')), {'i1': null});
        expect(route(sent.single), 'DELETE /rest/v1/items');
        expect(sent.single.url.queryParameters['id'], 'eq.i1');
      });

      test('a move goes to the end of its new group', () async {
        final repo = server((_) => (200, row('i1')));
        final rows = await repo.send(
          const MoveItem('i1', categoryId: 'c2', storeId: null),
        );
        expect(route(sent.single), 'POST /rest/v1/rpc/move_item');
        expect(params(sent.single), {
          'p_item': 'i1',
          'p_store': null,
          'p_category': 'c2',
        });
        expect(rows['i1']!.id, 'i1');
      });

      test('a place names its anchor and side', () async {
        final repo = server((_) => (200, [row('i1')]));
        await repo.send(
          const PlaceItem(
            'i1',
            anchorId: 'i2',
            edge: Edge.after,
            categoryId: 'c1',
            storeId: 's1',
            sortKey: 2.5,
          ),
        );
        expect(route(sent.single), 'POST /rest/v1/rpc/place_item');
        expect(params(sent.single), {
          'p_item': 'i1',
          'p_anchor': 'i2',
          'p_edge': 'after',
        });
      });

      test(
        'a move whose item is gone (P0002) answers its current row',
        () async {
          final repo = server(
            (r) => r.method == 'POST'
                ? (404, {'code': 'P0002', 'message': 'item not found'})
                : (200, <Object>[]),
          );
          expect(
            await repo.send(
              const MoveItem('i1', categoryId: 'c1', storeId: 's1'),
            ),
            {'i1': null},
          );
          expect(route(sent.last), 'GET /rest/v1/items');
        },
      );

      test('a move without a row back asks for the item', () async {
        final repo = server(
          (r) => r.method == 'POST' ? (200, null) : (200, [row('i1')]),
        );
        final rows = await repo.send(
          const MoveItem('i1', categoryId: 'c1', storeId: 's1'),
        );
        expect(rows['i1']!.id, 'i1');
        expect(route(sent.last), 'GET /rest/v1/items');
      });

      test('a move the database refuses otherwise is a rejection', () async {
        final repo = server(
          (_) => (400, {'code': '23503', 'message': 'no such category'}),
        );
        await expectLater(
          repo.send(const MoveItem('i1', categoryId: 'x', storeId: null)),
          throwsA(isA<RejectedOp>()),
        );
        expect(sent, hasLength(1));
      });

      const merge = MergeItems(
        'keep',
        mergeId: 'merge-1',
        otherId: 'other',
        quantity: '2',
        brand: null,
        properties: null,
      );

      test('a merge answers both rows', () async {
        final repo = server(
          (_) => (200, {'kept': row('keep'), 'merged': null}),
        );
        final rows = await repo.send(merge);
        expect(route(sent.single), 'POST /rest/v1/rpc/merge_items');
        expect(params(sent.single), {
          'p_merge': 'merge-1',
          'p_keep': 'keep',
          'p_other': 'other',
        });
        expect(rows.keys, unorderedEquals(['keep', 'other']));
        expect(rows['keep']!.id, 'keep');
        expect(rows['other'], isNull);
      });

      test(
        'a merge with an item gone (P0002) answers both current rows',
        () async {
          final repo = server(
            (r) => r.method == 'POST'
                ? (404, {'code': 'P0002', 'message': 'gone'})
                : r.url.queryParameters['id'] == 'eq.keep'
                ? (200, [row('keep')])
                : (200, <Object>[]),
          );
          final rows = await repo.send(merge);
          expect(rows['keep']!.id, 'keep');
          expect(rows['other'], isNull);
          expect(rows.keys, unorderedEquals(['keep', 'other']));
        },
      );

      test('a merge answer of another shape is a rejection', () async {
        final repo = server((_) => (200, {'unexpected': true}));
        await expectLater(
          repo.send(merge),
          throwsA(
            isA<RejectedOp>().having((e) => e.nameTaken, 'nameTaken', false),
          ),
        );
      });

      test('a merge the database refuses otherwise is a rejection', () async {
        final repo = server(
          (_) => (400, {'code': '22023', 'message': 'not open'}),
        );
        await expectLater(repo.send(merge), throwsA(isA<RejectedOp>()));
        expect(sent, hasLength(1));
      });

      test('an undone merge brings both rows back', () async {
        final kept = Item.fromJson(row('keep'));
        final merged = Item.fromJson(row('other'));
        final repo = server(
          (_) => (200, {'kept': row('keep'), 'merged': row('other')}),
        );
        final rows = await repo.send(
          UnmergeItems('keep', mergeId: 'merge-1', kept: kept, merged: merged),
        );
        expect(route(sent.single), 'POST /rest/v1/rpc/unmerge_items');
        expect(params(sent.single), {'p_merge': 'merge-1'});
        expect(rows.keys, unorderedEquals(['keep', 'other']));
        expect(rows['other']!.id, 'other');
      });

      test('an add sends every field of the item', () async {
        final repo = server((_) => (200, [row('i1')]));
        await repo.send(
          AddItem(
            Item(
              id: 'i1',
              name: 'Brot',
              quantity: '1',
              brand: 'Harry',
              properties: 'Vollkorn',
              categoryId: 'c1',
              storeId: 's1',
              sortKey: 1.5,
              status: ItemStatus.active,
              createdAt: at,
              updatedAt: at,
            ),
            noStore: true,
          ),
        );
        expect(route(sent.single), 'POST /rest/v1/rpc/put_item');
        expect(params(sent.single), {
          'p_id': 'i1',
          'p_household': 'household',
          'p_name': 'Brot',
          'p_quantity': '1',
          'p_brand': 'Harry',
          'p_properties': 'Vollkorn',
          'p_category': 'c1',
          'p_store': 's1',
          'p_sort_key': 1.5,
          'p_status': 'active',
          'p_no_store': true,
        });
      });
    });

    group('a dictated sentence', () {
      test('splits into the entries the voice endpoint found', () async {
        final repo = server(
          (_) => (
            200,
            {
              'items': [
                {'name': 'Milch', 'quantity': '2 l'},
                {'name': 'Brot', 'quantity': null},
                {'quantity': '3'},
              ],
            },
          ),
        );
        final (:entries, :truncated) = await repo.splitSpoken(
          'zwei Liter Milch und Brot',
        );
        expect(route(sent.single), 'POST /functions/v1/voice');
        expect(params(sent.single), {
          'text': 'zwei Liter Milch und Brot',
          'mode': 'parse',
          'split': true,
          'household': 'household',
        });
        expect(
          [for (final e in entries) (e.name, e.quantity)],
          [('Milch', '2 l'), ('Brot', null)],
        );
        expect(truncated, isFalse);
      });

      test('with nothing to add is empty', () async {
        for (final (status, body) in <(int, Object)>[
          (200, {'items': null}),
          (422, {'error': 'nothing'}),
        ]) {
          final (:entries, :truncated) = await server((_) => (status, body))
              .splitSpoken('ähm');
          expect(entries, isEmpty, reason: '$status');
          expect(truncated, isFalse, reason: '$status');
        }
      });

      test('fails when the endpoint does', () async {
        await expectLater(
          server((_) => (500, {'error': 'boom'})).splitSpoken('Milch'),
          throwsA(isA<ServerTrouble>()),
        );
        await expectLater(
          server((_) => (400, {'error': 'bad'})).splitSpoken('Milch'),
          throwsA(isA<FunctionException>()),
        );
      });
    });
  });
}
