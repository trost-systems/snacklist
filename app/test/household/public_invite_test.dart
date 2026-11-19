import 'dart:convert';

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/join_code_screen.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Request, Response;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Job 271: a typed code's preview, from `preview_invite_public` to the
/// card.
void main() {
  group('preview_invite_public on the wire', () {
    late List<Request> sent;

    SupabaseInviteRepository server(Object? answer) {
      sent = [];
      final client = SupabaseClient(
        'http://localhost:54321',
        'sb_publishable_test',
        httpClient: MockClient((request) async {
          sent.add(request);
          return Response(
            jsonEncode(answer),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      return SupabaseInviteRepository(client);
    }

    Map<String, Object?> empty(String status) => {
      'status': status,
      'household': null,
      'inviter': null,
      'members': null,
      'open_items': null,
      'premium': null,
      'invite_kind': null,
    };

    test('an open invite brings the join page facts', () async {
      final repo = server({
        'status': 'ok',
        'household': 'Familie Trost',
        'inviter': 'Peter',
        'members': 3,
        'open_items': 12,
        'premium': true,
        'invite_kind': 'person',
      });
      final answer = await repo.previewPublic('ABCD2345');
      expect(sent.single.url.path, '/rest/v1/rpc/preview_invite_public');
      expect(jsonDecode(sent.single.body), {'p_code': 'ABCD2345'});
      expect(answer, isA<PublicInviteOpen>());
      final open = answer as PublicInviteOpen;
      expect(
        (
          open.household,
          open.inviter,
          open.members,
          open.openItems,
          open.premium,
        ),
        ('Familie Trost', 'Peter', 3, 12, true),
      );
    });

    test('an inviter without a name of their own is none', () async {
      for (final inviter in [null, '', '  ']) {
        final answer = await server({
          'status': 'ok',
          'household': 'H',
          'inviter': inviter,
          'members': 1,
          'open_items': 0,
          'premium': false,
        }).previewPublic('ABCD2345');
        expect((answer as PublicInviteOpen).inviter, isNull);
      }
    });

    test('invalid and full are one answer, rate-limited its own', () async {
      expect(
        await server(empty('invalid')).previewPublic('ABCD2345'),
        isA<PublicInviteUnavailable>(),
      );
      expect(
        await server(empty('full')).previewPublic('ABCD2345'),
        isA<PublicInviteUnavailable>(),
      );
      expect(
        await server(empty('rate_limited')).previewPublic('ABCD2345'),
        isA<PublicInviteRateLimited>(),
      );
    });

    test('an answer of another shape is an error to retry', () async {
      for (final body in <Object?>[
        {'status': 'ok', 'household': 'H', 'members': -1, 'open_items': 0},
        {'status': 'ok', 'household': 7, 'members': 1, 'open_items': 0},
        {'status': 'what'},
        null,
      ]) {
        await expectLater(
          server(body).previewPublic('ABCD2345'),
          throwsA(
            isA<HouseholdError>().having(
              (e) => e.problem,
              'problem',
              HouseholdProblem.other,
            ),
          ),
        );
      }
    });
  });

  group('the preview card', () {
    const open = PublicInviteOpen(
      household: 'Familie Trost',
      inviter: 'Peter',
      members: 1,
      openItems: 12,
      premium: true,
    );

    Future<void> pumpCard(
      WidgetTester tester,
      InvitePreviewFields fields, {
      PublicInviteOpen invite = open,
      Locale locale = const Locale('de'),
    }) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: InvitePreviewCard(invite: invite, fields: fields),
        ),
      ),
    );

    List<String> texts(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.byType(Text)))
        text.data ?? '',
    ];

    for (final (what, fields, expected) in [
      (
        'every field',
        const InvitePreviewFields(),
        [
          'Peter lädt dich zu „Familie Trost“ ein',
          '1 Mitglied · 12 offene Einträge',
          'Premium gilt für alle im Haushalt',
        ],
      ),
      (
        'no inviter',
        const InvitePreviewFields(inviter: false),
        [
          'Du bist zu „Familie Trost“ eingeladen',
          '1 Mitglied · 12 offene Einträge',
          'Premium gilt für alle im Haushalt',
        ],
      ),
      (
        'no household name',
        const InvitePreviewFields(household: false),
        [
          'Peter lädt dich in einen Haushalt ein',
          '1 Mitglied · 12 offene Einträge',
          'Premium gilt für alle im Haushalt',
        ],
      ),
      (
        'no members',
        const InvitePreviewFields(members: false),
        [
          'Peter lädt dich zu „Familie Trost“ ein',
          '12 offene Einträge',
          'Premium gilt für alle im Haushalt',
        ],
      ),
      (
        'no open items',
        const InvitePreviewFields(openItems: false),
        [
          'Peter lädt dich zu „Familie Trost“ ein',
          '1 Mitglied',
          'Premium gilt für alle im Haushalt',
        ],
      ),
      (
        'no Premium',
        const InvitePreviewFields(premium: false),
        [
          'Peter lädt dich zu „Familie Trost“ ein',
          '1 Mitglied · 12 offene Einträge',
        ],
      ),
      (
        'nothing',
        const InvitePreviewFields(
          inviter: false,
          household: false,
          members: false,
          openItems: false,
          premium: false,
        ),
        ['Du bist in einen Haushalt eingeladen'],
      ),
    ]) {
      testWidgets('reads well with $what', (tester) async {
        await pumpCard(tester, fields);
        expect(texts(tester), expected);
      });
    }

    testWidgets('a household without Premium or a named inviter, in '
        'English', (tester) async {
      await pumpCard(
        tester,
        const InvitePreviewFields(),
        invite: const PublicInviteOpen(
          household: 'Flat 3',
          inviter: null,
          members: 2,
          openItems: 1,
          premium: false,
        ),
        locale: const Locale('en'),
      );
      expect(texts(tester), [
        'You’re invited to “Flat 3”',
        '2 members · 1 open item',
      ]);
    });
  });
}
