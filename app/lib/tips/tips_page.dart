import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/tips/hint_host.dart';
import 'package:family_groceries/tips/hint_views.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// More → Tipps (job 168b): every hint this device can show, to read again,
/// shown or not, hidden or not, each with its button.
class const TipsPage({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final platform = HintPlatform.current(
      web: kIsWeb,
      platform: defaultTargetPlatform,
    );
    final canAddHousehold = context.read<HintHost?>()?.canAddHousehold ?? false;
    final shown = [
      for (final hint in hints)
        if (hint.offered(platform, canAddHousehold: canAddHousehold)) hint,
    ];
    return ListView(
      key: const ValueKey('more-tips-page'),
      padding: EdgeInsets.fromLTRB(
        HlSpace.s4,
        HlSpace.s4,
        HlSpace.s4,
        HlSpace.s5 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        for (final hint in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: HlSpace.s3),
            child: HintCard(
              key: ValueKey('tips-${hint.id.wire}'),
              hint: hint,
              onAct: () => switch (hint.action) {
                final action? => openHintAction(context, action),
                null => null,
              },
            ),
          ),
      ],
    );
  }
}
