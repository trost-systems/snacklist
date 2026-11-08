import 'dart:convert';

import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Request, Response;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Job 47: what the server says about archiving reaches the user.
void main() {
  final de = lookupAppLocalizations(const Locale('de'));
  final en = lookupAppLocalizations(const Locale('en'));

  SupabaseClient answering(int status, Object body) {
    final client = SupabaseClient(
      'http://localhost:54321',
      'sb_publishable_test',
      httpClient: MockClient(
        (request) async => Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    addTearDown(client.dispose);
    return client;
  }

  test('the switched-off archive is its own problem, in DE and EN', () async {
    final client = answering(400, {
      'code': 'P0001',
      'message': 'archive_disabled',
      'hint': 'Archiving households is switched off on this server.',
    });
    await expectLater(
      householdCall(() => client.rpc<Map<String, dynamic>>('accept_invite')),
      throwsA(
        isA<HouseholdError>().having(
          (e) => e.problem,
          'problem',
          HouseholdProblem.archiveDisabled,
        ),
      ),
    );
    expect(
      householdProblemText(de, HouseholdProblem.archiveDisabled),
      'Archivieren ist gerade nicht möglich. Dein Haushalt bleibt, wie er ist.',
    );
    expect(
      householdProblemText(en, HouseholdProblem.archiveDisabled),
      "Archiving isn't available right now. Your household stays as it is.",
    );
  });

  test('archived households carry the server deletion date', () async {
    final client = answering(200, [
      {
        'id': 'old',
        'name': 'Altbau',
        'archived_at': '2026-10-31T12:00:00+00:00',
        'deletes_at': '2028-10-31T12:00:00+00:00',
        'unlocked': true,
      },
      {
        'id': 'older',
        'name': 'Vorher',
        'archived_at': '2026-10-01T12:00:00+00:00',
        'unlocked': false,
      },
    ]);
    final archived = await SupabaseInviteRepository(client).archived();
    expect(archived.first.deletesAt, DateTime.utc(2028, 10, 31, 12));
    expect(archived.last.deletesAt, isNull, reason: 'a server before job 47');
  });

  test('the archive offer on leaving names the 24 months', () {
    expect(
      de.leaveArchiveOffer('Zuhause'),
      endsWith(
        'Aktivierst du ihn nicht innerhalb von 24 Monaten wieder, wird er '
        'gelöscht.',
      ),
    );
    expect(
      en.leaveArchiveOffer('Home'),
      endsWith("If you don't bring it back within 24 months, it is deleted."),
    );
  });

  group('invites on the wire', () {
    late List<Request> sent;

    SupabaseInviteRepository server(Object? Function(Request request) answer) {
      sent = [];
      final client = SupabaseClient(
        'http://localhost:54321',
        'sb_publishable_test',
        httpClient: MockClient((request) async {
          sent.add(request);
          return Response(
            jsonEncode(answer(request)),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      return SupabaseInviteRepository(client);
    }

    Object? params(Request r) => jsonDecode(r.body);

    test('a new invite comes back with its code and expiry', () async {
      final repo = server(
        (_) => {
          'id': 'i1',
          'code': 'ABCD2345',
          'expires_at': '2026-11-12T09:00:00Z',
        },
      );
      final invite = await repo.create('home');
      expect(sent.single.url.path, '/rest/v1/rpc/create_invite');
      expect(params(sent.single), {'p_household': 'home'});
      expect(invite.code, 'ABCD2345');
      expect(invite.expiresAt, DateTime.utc(2026, 11, 12, 9));
    });

    test('the open invites are the household’s unused, unrevoked, unexpired '
        'ones, newest first', () async {
      final repo = server(
        (_) => [
          {
            'id': 'i2',
            'code': 'NEWER234',
            'expires_at': '2026-11-12T09:00:00Z',
          },
          {
            'id': 'i1',
            'code': 'OLDER234',
            'expires_at': '2026-11-10T09:00:00Z',
          },
        ],
      );
      final invites = await repo.open('home');
      expect([for (final i in invites) i.code], ['NEWER234', 'OLDER234']);
      final query = sent.single.url.queryParameters;
      expect(sent.single.url.path, '/rest/v1/invites');
      expect(query['household_id'], 'eq.home');
      expect(query['used_at'], 'is.null');
      expect(query['revoked_at'], 'is.null');
      expect(query['expires_at'], startsWith('gt.'));
      expect(query['order'], 'created_at.desc.nullslast');
    });

    test('revoking names the invite', () async {
      await server((_) => null).revoke('i1');
      expect(sent.single.url.path, '/rest/v1/rpc/revoke_invite');
      expect(params(sent.single), {'p_invite': 'i1'});
    });

    test('an open code shows the household and what joining keeps', () async {
      final repo = server(
        (_) => {
          'status': 'ok',
          'name': 'Familie Brandt',
          'unlocked': true,
          'leaves_unlocked': false,
          'recent_purchase': true,
        },
      );
      final preview = await repo.preview('ABCD2345');
      expect(params(sent.single), {'p_code': 'ABCD2345'});
      expect(
        preview,
        isA<InviteOpen>()
            .having((p) => p.name, 'name', 'Familie Brandt')
            .having((p) => p.lifetime.targetUnlocked, 'target', isTrue)
            .having((p) => p.lifetime.recentPurchase, 'recent', isTrue),
      );
    });

    test('an open code without Lifetime facts keeps nothing', () async {
      final preview = await server((_) => {'status': 'ok', 'name': 'WG'})
          .preview('ABCD2345');
      final lifetime = (preview as InviteOpen).lifetime;
      expect(lifetime.targetUnlocked, isFalse);
      expect(lifetime.recentPurchase, isFalse);
    });

    test('a code of the user’s own household says so', () async {
      final preview = await server(
        (_) => {'status': 'member', 'name': 'Zuhause'},
      ).preview('ABCD2345');
      expect(
        preview,
        isA<InviteMember>().having((p) => p.name, 'name', 'Zuhause'),
      );
    });

    test('a refused code is its problem; an odd answer is another', () async {
      await expectLater(
        server((_) => {'status': 'invalid_invite'}).preview('XXXX0000'),
        throwsA(
          isA<HouseholdError>().having(
            (e) => e.problem,
            'problem',
            HouseholdProblem.invalidInvite,
          ),
        ),
      );
      await expectLater(
        server((_) => {'unexpected': true}).preview('XXXX0000'),
        throwsA(
          isA<HouseholdError>().having(
            (e) => e.problem,
            'problem',
            HouseholdProblem.other,
          ),
        ),
      );
    });

    test('the members come from household_members_of (job 169b)', () async {
      final repo = server(
        (_) => [
          {'user_id': 'peter', 'display_name': 'Peter', 'role': 'owner'},
          {'user_id': 'lea', 'display_name': null, 'role': 'member'},
        ],
      );
      final members = await repo.members('home');
      expect(sent.single.url.path, endsWith('/rpc/household_members_of'));
      expect(params(sent.single), {'p_household': 'home'});
      expect(
        [for (final m in members) (m.userId, m.displayName, m.role)],
        [('peter', 'Peter', 'owner'), ('lea', '', 'member')],
      );
    });

    test('leaves_unlocked asks about the given household', () async {
      final repo = server((_) => true);
      expect(await repo.leavesUnlocked('club'), isTrue);
      expect(sent.single.url.path, endsWith('/rpc/leaves_unlocked'));
      expect(params(sent.single), {'p_household': 'club'});
    });

    test('archived households keep their lock and deletion date', () async {
      final repo = server(
        (_) => [
          {
            'id': 'h1',
            'name': 'Alte WG',
            'archived_at': '2026-10-01T08:00:00Z',
            'unlocked': true,
            'deletes_at': '2027-10-01T08:00:00Z',
          },
          {
            'id': 'h2',
            'name': 'Ferienhaus',
            'archived_at': '2026-09-01T08:00:00Z',
            'unlocked': null,
            'deletes_at': null,
          },
        ],
      );
      final archived = await repo.archived();
      expect(sent.single.url.path, '/rest/v1/rpc/archived_households');
      expect(archived.first.unlocked, isTrue);
      expect(archived.first.deletesAt, DateTime.utc(2027, 10, 1, 8));
      expect(archived.first.archivedAt, DateTime.utc(2026, 10, 1, 8));
      expect(archived.last.unlocked, isFalse);
      expect(archived.last.deletesAt, isNull);
    });
  });
}
