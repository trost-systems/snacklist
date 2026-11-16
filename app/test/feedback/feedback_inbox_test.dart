import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/feedback/feedback_inbox.dart';
import 'package:family_groceries/feedback/feedback_note.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fb4_harness.dart';

void main() {
  group('SupabaseFeedbackRepository reads (job 268)', () {
    late List<http.Request> requests;

    SupabaseFeedbackRepository repository(
      FutureOr<http.Response> Function(http.Request request) answer,
    ) {
      requests = [];
      final client = SupabaseClient(
        'http://localhost:54321',
        'test',
        httpClient: MockClient((request) async {
          requests.add(request);
          final response = await answer(request);
          return http.Response(
            response.body,
            response.statusCode,
            headers: response.headers,
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      return SupabaseFeedbackRepository(client);
    }

    http.Response json(Object? body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    test('notes: the own notes newest first, 50 at most, every status and '
        'stamp; an unknown status reads as sent', () async {
      final repo = repository(
        (_) => json([
          {
            'id': 'n1',
            'created_at': '2026-11-14T17:44:00.123456+00:00',
            'message': 'Hafermilch landet unter Vorrat.',
            'category': 'bug',
            'status': 'fixed',
            'fixed_in': '1.4.1',
            'reply': 'Danke, behoben.',
            'replied_at': '2026-11-15T09:02:00+00:00',
            'answered_at': '2026-11-15T09:02:00+00:00',
            'seen_at': null,
          },
          {
            'id': 'n2',
            'created_at': '2026-11-13T08:00:00+00:00',
            'message': 'Neu',
            'category': null,
            'status': 'archived',
            'fixed_in': null,
            'reply': null,
            'replied_at': null,
            'answered_at': null,
            'seen_at': null,
          },
        ]),
      );
      final notes = await repo.notes();
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/feedback');
      expect(
        request.url.queryParameters['order'],
        startsWith('created_at.desc'),
      );
      expect(request.url.queryParameters['limit'], '50');
      expect(
        request.url.queryParameters['select']!.split(',').map((c) => c.trim()),
        unorderedEquals([
          'id',
          'created_at',
          'message',
          'category',
          'status',
          'fixed_in',
          'reply',
          'replied_at',
          'answered_at',
          'seen_at',
        ]),
      );
      final [fixed, unknown] = notes;
      expect(fixed.id, 'n1');
      expect(fixed.createdAt, DateTime.utc(2026, 11, 14, 17, 44, 0, 123, 456));
      expect(fixed.category, FeedbackCategory.bug);
      expect(fixed.status, NoteStatus.fixed);
      expect(fixed.fixedIn, '1.4.1');
      expect(fixed.reply, 'Danke, behoben.');
      expect(fixed.repliedAt, DateTime.utc(2026, 11, 15, 9, 2));
      expect(fixed.answeredAt, DateTime.utc(2026, 11, 15, 9, 2));
      expect(fixed.seenAt, isNull);
      expect(fixed.unread, isTrue);
      expect(unknown.status, NoteStatus.sent);
      expect(unknown.category, isNull);
      expect(unknown.unread, isFalse);
    });

    test('ideas: the household asks feedback_ideas; titles, status, '
        'totals, its own +1; an unknown status reads as considering', () async {
      final repo = repository(
        (_) => json([
          {
            'id': 'i1',
            'title_de': 'Wochenplan',
            'title_en': 'Meal plan',
            'status': 'planned',
            'votes': 10,
            'voted': true,
          },
          {
            'id': 'i2',
            'title_de': 'Kassenbons',
            'title_en': 'Receipts',
            'status': 'later',
            'votes': 0,
            'voted': false,
          },
        ]),
      );
      final ideas = await repo.ideas('home');
      expect(requests.single.url.path, '/rest/v1/rpc/feedback_ideas');
      expect(jsonDecode(requests.single.body), {'p_household': 'home'});
      final [plan, receipts] = ideas;
      expect(plan.title('de'), 'Wochenplan');
      expect(plan.title('en'), 'Meal plan');
      expect(plan.status, IdeaStatus.planned);
      expect(plan.votes, 10);
      expect(plan.voted, isTrue);
      expect(receipts.status, IdeaStatus.considering);
    });

    test('vote sends idea, household and on; answers the new total', () async {
      final repo = repository((_) => json(15));
      expect(await repo.vote('i1', 'home', on: true), 15);
      expect(requests.single.url.path, '/rest/v1/rpc/vote_feedback_idea');
      expect(jsonDecode(requests.single.body), {
        'p_idea': 'i1',
        'p_household': 'home',
        'p_on': true,
      });
    });

    test('markSeen names the note', () async {
      final repo = repository((_) => http.Response('', 204));
      await repo.markSeen('n1');
      expect(requests.single.url.path, '/rest/v1/rpc/feedback_mark_seen');
      expect(jsonDecode(requests.single.body), {'p_id': 'n1'});
    });

    test('a refusal names its code, no connection is offline, a row '
        'without its id is refused', () async {
      final refused = repository(
        (_) => json({'code': '42501', 'message': 'no'}, 403),
      );
      await expectLater(
        refused.ideas('other'),
        throwsA(isA<FeedbackRefused>().having((e) => e.code, 'code', '42501')),
      );
      final offline = repository(
        (_) => throw http.ClientException('Failed to fetch'),
      );
      await expectLater(offline.notes(), throwsA(isA<FeedbackOffline>()));
      final broken = repository(
        (_) => json([
          {'message': 'ohne id'},
        ]),
      );
      await expectLater(broken.notes(), throwsA(isA<FeedbackRefused>()));
    });
  });

  group('FeedbackNote.unread', () {
    FeedbackNote note({DateTime? answered, DateTime? seen}) => FeedbackNote(
      id: 'n',
      createdAt: at(1, 8),
      message: 'm',
      category: null,
      status: NoteStatus.read,
      answeredAt: answered,
      seenAt: seen,
    );

    test('only an answer the user has not opened since', () {
      expect(note().unread, isFalse);
      expect(note(answered: at(2, 8)).unread, isTrue);
      expect(note(answered: at(2, 8), seen: at(2, 7)).unread, isTrue);
      expect(note(answered: at(2, 8), seen: at(2, 8)).unread, isFalse);
      expect(note(answered: at(2, 8), seen: at(3, 8)).unread, isFalse);
      expect(note(answered: at(2, 8)).seen().unread, isFalse);
    });
  });

  group('FeedbackInbox', () {
    test('another user starts empty; the newest load wins', () async {
      final server = fb4Server();
      final inbox = FeedbackInbox(server);
      addTearDown(inbox.close);
      await inbox.load(userId: 'a', householdId: 'home');
      expect(inbox.state.unread, 2);
      expect(inbox.state.ideas, hasLength(2));
      server.serverNotes.clear();
      final other = inbox.load(userId: 'b', householdId: null);
      expect(inbox.state.notes, isNull, reason: "a's notes are gone at once");
      await other;
      expect(inbox.state.notes, isEmpty);
      expect(inbox.state.ideas, isEmpty, reason: 'no household, no ideas');
    });

    test(
      'markSeen counts the note read at once and tells the server',
      () async {
        final server = fb4Server();
        final inbox = FeedbackInbox(server);
        addTearDown(inbox.close);
        await inbox.load(userId: 'a', householdId: 'home');
        final marking = inbox.markSeen('n-fixed');
        expect(inbox.state.unread, 1);
        await marking;
        expect(server.seen, ['n-fixed']);
        await inbox.markSeen('n-planned');
        expect(server.seen, ['n-fixed'], reason: 'nothing unopened there');
      },
    );

    test('a load during a +1 keeps what the tap showed', () async {
      final server = fb4Server()..holdVote = Completer();
      final inbox = FeedbackInbox(server);
      addTearDown(inbox.close);
      await inbox.load(userId: 'a', householdId: 'home');
      final voting = inbox.vote(mealIdea, on: true);
      await inbox.load(userId: 'a', householdId: 'home');
      expect(inbox.state.ideas.last.votes, 10);
      expect(inbox.state.ideas.last.voted, isTrue);
      server.holdVote!.complete();
      expect(await voting, isTrue);
      expect(inbox.state.ideas.last.votes, 10);
    });

    test('another household drops the ideas at once; a +1 then counts for '
        'it, and an answer for the one left changes nothing', () async {
      final server = fb4Server()..holdVote = Completer();
      final inbox = FeedbackInbox(server);
      addTearDown(inbox.close);
      await inbox.load(userId: 'a', householdId: 'home');
      final left = inbox.vote(mealIdea, on: true);
      expect(inbox.state.ideas.last.voted, isTrue);

      final switching = inbox.load(userId: 'a', householdId: 'work');
      expect(inbox.state.ideas, isEmpty, reason: "home's +1s are gone");
      expect(inbox.state.notes, hasLength(5), reason: 'the notes are the same');
      server.serverIdeas = [aisleIdea, mealIdea];
      await switching;
      expect(inbox.state.ideas.last.voted, isFalse);

      server.holdVote!.complete();
      server.holdVote = null;
      expect(await left, isTrue);
      expect(inbox.state.ideas.last.voted, isFalse);
      expect(inbox.state.ideas.last.votes, 9, reason: "home's total stays out");

      expect(await inbox.vote(mealIdea, on: true), isTrue);
      expect(server.votes.last.household, 'work');
      expect(inbox.state.ideas.last.votes, 10);
    });

    test('a second tap while a +1 is on its way is ignored; the list ends '
        'as the server has it', () async {
      final server = fb4Server()..holdVote = Completer();
      final inbox = FeedbackInbox(server);
      addTearDown(inbox.close);
      await inbox.load(userId: 'a', householdId: 'home');
      final on = inbox.vote(mealIdea, on: true);
      final off = inbox.vote(inbox.state.ideas.last, on: false);
      server.holdVote!.complete();
      server.holdVote = null;
      expect(await off, isTrue);
      expect(await on, isTrue);
      expect(server.votes, hasLength(1));
      final shown = inbox.state.ideas.last;
      final stored = server.serverIdeas.last;
      expect((shown.voted, shown.votes), (stored.voted, stored.votes));

      expect(await inbox.vote(shown, on: false), isTrue);
      expect(inbox.state.ideas.last.voted, isFalse, reason: 'free again');
      expect(server.serverIdeas.last.voted, isFalse);
    });

    test('a refused +1 is undone and reported', () async {
      final server = fb4Server()..failVotes = 1;
      final inbox = FeedbackInbox(server);
      addTearDown(inbox.close);
      await inbox.load(userId: 'a', householdId: 'home');
      expect(await inbox.vote(aisleIdea, on: true), isFalse);
      expect(inbox.state.ideas.first.votes, 14);
      expect(inbox.state.ideas.first.voted, isFalse);
    });
  });
}
