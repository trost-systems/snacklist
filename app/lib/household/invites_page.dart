import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/invite_sheet.dart';
import 'package:family_groceries/household/invites_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// More's Einladungen (`/more/invites`): the invite sheet's panel as a
/// page, for the shown household: person invites (make, share, revoke)
/// and, for owner and admins, the group link and who joined with it.
class const InvitesPage({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => switch (context
      .watch<SessionCubit>()
      .state) {
    InHousehold(:final household) => InvitesScope(
      // A new household (a switch) lists its own invites.
      key: ValueKey(household.id),
      household: household,
      child: Builder(
        builder: (context) => RefreshIndicator(
          onRefresh: context.read<InvitesCubit>().reload,
          child: ListView(
            key: const ValueKey('invites-page'),
            padding: EdgeInsets.fromLTRB(
              HlSpace.s5,
              0,
              HlSpace.s5,
              HlSpace.s5 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              InvitePanel(household: household, origin: InviteContext.settings),
            ],
          ),
        ),
      ),
    ),
    _ => const SizedBox.shrink(),
  };
}
