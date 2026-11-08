import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth.dart';

/// One household on [FakeHouseholds]' server.
class ServerHousehold(var String name, {var int open = 0}) {
  final members = <String>[];
}

/// The households RPCs of docs/households/W1.md, in memory, for the user
/// signed in on [fakeAuth]: a real SupabaseClient's requests are answered here.
/// [calls] has each request as `path body`.
class FakeHouseholds(final FakeAuth fakeAuth)
    extends Fake
    implements SupabaseClient {
  final households = <String, ServerHousehold>{};

  /// Each user's memberships, oldest first; the default by [defaults].
  final memberships = <String, List<String>>{};
  final defaults = <String, String>{};

  /// Households whose Hummlist Premium ends with their last member.
  final unlocked = <String>{};

  /// Invite code to the household it leads to.
  final invites = <String, String>{};

  /// Ids for the next households created, in order; then `h<n>`.
  final nextIds = <String>[];
  final calls = <String>[];

  /// The next call is done on the server but its answer is lost (not
  /// analytics' own consent call, which runs beside it, job 31).
  var dropNextAnswer = false;

  /// `my_households` fails: the reload after an RPC.
  var failReads = false;

  /// RPCs this server does not have yet (an older deploy): 404.
  final missing = <String>{};
  final _requests = <(String, String), String>{};
  var _n = 0;

  String get _user => fakeAuth.user?.id ?? 'nobody';

  /// Adds [userId] to a household [id] named [name]; the first one they
  /// are in is their default.
  void member(String userId, String id, String name, {int open = 0}) {
    households
        .putIfAbsent(id, () => ServerHousehold(name, open: open))
        .members
        .add(userId);
    memberships.putIfAbsent(userId, () => []).add(id);
    defaults.putIfAbsent(userId, () => id);
  }

  /// Another member removed [userId] from [id] (`remove_member`): their
  /// default moves to their oldest other membership, as the server's
  /// trigger does.
  void removedBySomeone(String userId, String id) {
    memberships[userId]?.remove(id);
    households[id]?.members.remove(userId);
    if (defaults[userId] == id) {
      defaults.remove(userId);
      if (memberships[userId]?.firstOrNull case final next?) {
        defaults[userId] = next;
      }
    }
  }

  /// Households that confirm joins (job 169b W3 M), and the join requests
  /// waiting: request id to who asked which household.
  final approval = <String>{};
  final requests = <String, ({String user, String household})>{};

  /// An owner or admin decides on [requestId] (`decide_join_request`):
  /// approved, its user becomes a member.
  void decide(String requestId, {required bool approve}) {
    final request = requests.remove(requestId)!;
    if (approve) {
      member(
        request.user,
        request.household,
        households[request.household]!.name,
      );
    }
  }

  /// Households of a kind (job 168) and with Premium.
  final kinds = <String, String>{};
  final premium = <String>{};

  late final _rest = PostgrestClient(
    'http://db.invalid/rest/v1',
    httpClient: MockClient((request) async {
      final path = request.url.path.replaceFirst('/rest/v1/', '');
      calls.add('$path ${request.body}');
      final body = switch (request.body.isEmpty
          ? null
          : jsonDecode(request.body)) {
        final Map<String, Object?> map => map,
        _ => const <String, Object?>{},
      };
      if (dropNextAnswer && path != 'rpc/record_analytics_consent') {
        dropNextAnswer = false;
        _answer(request.method, path, request.url, body);
        throw http.ClientException('connection lost', request.url);
      }
      if (missing.contains(path.replaceFirst('rpc/', ''))) {
        return _json(
          {'message': 'not found', 'code': 'PGRST202'},
          404,
          request,
        );
      }
      if (failReads && path == 'rpc/my_households') {
        return _json({'message': 'timeout'}, 503, request);
      }
      try {
        return _json(
          _answer(request.method, path, request.url, body),
          200,
          request,
        );
      } on _Refused catch (e) {
        return _json({'message': e.message, 'code': 'P0001'}, 400, request);
      }
    }),
  );

  static http.Response _json(Object? body, int status, http.Request r) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
        request: r,
      );

  Object? _answer(
    String method,
    String path,
    Uri url,
    Map<String, Object?> body,
  ) {
    final mine = memberships.putIfAbsent(_user, () => []);
    String household() {
      final id = body['p_household'];
      if (id is! String || !mine.contains(id)) {
        throw const _Refused('not_member');
      }
      return id;
    }

    switch ((method, path)) {
      case ('POST', 'rpc/record_analytics_consent'):
        return null;
      case ('POST', 'rpc/my_households'):
        return [
          for (final id in mine)
            {
              'id': id,
              'name': households[id]!.name,
              'kind': kinds[id],
              'role': households[id]!.members.first == _user
                  ? 'owner'
                  : 'member',
              'is_default': defaults[_user] == id,
              'member_count': households[id]!.members.length,
              'open_count': households[id]!.open,
              'premium': premium.contains(id),
              'join_approval': approval.contains(id),
              'joined_at': '2026-11-08T10:00:00Z',
            },
        ];
      case ('POST', 'rpc/household_members_of'):
        return [
          for (final user in households[household()]!.members)
            {
              'user_id': user,
              'display_name': user[0].toUpperCase() + user.substring(1),
              'role': 'member',
              'joined_at': '2026-11-08T10:00:00Z',
            },
        ];
      case ('POST', 'rpc/leaves_unlocked'):
        return unlocked.contains(household());
      case ('POST', 'rpc/archived_households'):
        return const <Object?>[];
      case ('POST', 'rpc/set_default_household'):
        defaults[_user] = household();
        return null;
      case ('POST', 'rpc/create_household'):
        final key = (_user, body['p_request_id']! as String);
        if (_requests[key] case final id?) {
          return {'id': id, 'name': households[id]!.name};
        }
        if (mine.length >= 10) {
          throw const _Refused('too_many_households');
        }
        final id = nextIds.isEmpty ? 'h${++_n}' : nextIds.removeAt(0);
        _requests[key] = id;
        member(_user, id, body['p_name']! as String);
        return {'id': id, 'name': body['p_name']};
      case ('POST', 'rpc/accept_invite'):
        expect(body['p_mode'], 'add', reason: 'the app never moves out');
        final id = invites[body['p_code']];
        if (id == null) {
          return {'status': 'invalid_invite', 'household_id': null};
        }
        if (mine.contains(id)) {
          return {'status': 'member', 'household_id': id};
        }
        if (approval.contains(id)) {
          if (!requests.values.any(
            (r) => r.user == _user && r.household == id,
          )) {
            requests['r${++_n}'] = (user: _user, household: id);
          }
          return {'status': 'requested', 'household_id': id};
        }
        member(_user, id, households[id]?.name ?? 'Eingeladen');
        return {'status': 'joined', 'household_id': id};
      case ('POST', 'rpc/my_join_requests'):
        return [
          for (final MapEntry(key: id, value: r) in requests.entries)
            if (r.user == _user)
              {
                'id': id,
                'household_id': r.household,
                'household_name': households[r.household]!.name,
                'created_at': '2026-11-08T10:00:00Z',
              },
        ];
      case ('POST', 'rpc/cancel_join_request'):
        final id = body['p_request'];
        if (requests[id]?.user != _user) {
          throw const _Refused('not_found');
        }
        requests.remove(id);
        return null;
      case ('POST', 'rpc/leave_household'):
        final id = household();
        mine.remove(id);
        final left = households[id]!..members.remove(_user);
        if (defaults[_user] == id) {
          defaults.remove(_user);
          if (mine.firstOrNull case final next?) {
            defaults[_user] = next;
          }
        }
        if (left.members.isEmpty) {
          households.remove(id);
        }
        return {
          'status': 'left',
          'deleted': left.members.isEmpty,
          'archived': false,
        };
      case ('POST', 'rpc/unarchive_household'):
        final id = body['p_household']! as String;
        member(_user, id, 'Archiviert');
        return {'status': 'unarchived'};
      case ('PATCH', 'households'):
        final id = url.queryParameters['id']!.substring('eq.'.length);
        households[id]!.name = body['name']! as String;
        return null;
    }
    throw StateError('no fake for $method $path');
  }

  @override
  GoTrueClient get auth => fakeAuth;

  @override
  PostgrestClient get rest => _rest;

  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    Object? get,
  }) => _rest.rpc<T>(fn, params: params);
}

final class const _Refused(final String message) implements Exception;
