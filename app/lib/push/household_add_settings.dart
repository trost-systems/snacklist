import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Einstellungen's „Mitteilungen“ section (job 377): the switch for the push
/// when another member adds an item. Shown on iOS and Android builds with
/// push, while the `push-household-add` flag is on. Off by default.
class const HouseholdAddSettings({super.key}) extends StatefulWidget {
  @override
  State<HouseholdAddSettings> createState() => _HouseholdAddSettingsState();
}

class _HouseholdAddSettingsState() extends State<HouseholdAddSettings> {
  @override
  void initState() {
    super.initState();
    // Each time the settings open: the choice shown is the signed-in
    // user's, read from the server.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final alert = context.read<HouseholdAddAlert?>();
      if (alert != null) {
        unawaited(alert.refresh(Localizations.localeOf(context).languageCode));
      }
    });
  }

  Future<void> _tell(HouseholdAddResult result) async {
    final notices = Notices.of(context);
    final l10n = AppLocalizations.of(context);
    final message = switch (result) {
      HouseholdAddResult.done => null,
      HouseholdAddResult.blocked => l10n.pushBlocked,
      HouseholdAddResult.failed => l10n.catalogSaveFailed,
    };
    if (message != null) {
      notices.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _set(HouseholdAddAlert alert, {required bool on}) async {
    final result = await alert.set(
      on: on,
      language: Localizations.localeOf(context).languageCode,
    );
    if (mounted) {
      await _tell(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final flag = context.select<Flags?, bool>(
      (flags) => flags?.isOn(pushHouseholdAddFlag) ?? false,
    );
    final alert = context.watch<HouseholdAddAlert?>();
    final choice = alert?.state;
    if (!flag || alert == null || choice == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HlSectionLabel(
          l10n.settingsPush,
          padding: const EdgeInsets.fromLTRB(20, HlSpace.s5, 20, 0),
        ),
        HlGroup(
          top: HlSpace.s2,
          children: [
            if (alert.canNotify)
              HexSwitchTile(
                key: const ValueKey('settings-push-household-add'),
                leading: HlRowHex(
                  Icons.notifications_none,
                  face: t.surfaceSunken,
                ),
                title: Text(l10n.pushHouseholdAdd),
                subtitle: Text(l10n.pushHouseholdAddHint),
                isThreeLine: true,
                value: choice.on,
                onChanged: (value) => unawaited(_set(alert, on: value)),
              ),
            HexSwitchTile(
              key: const ValueKey('settings-push-name-hidden'),
              leading: HlRowHex(
                Icons.visibility_off_outlined,
                face: t.surfaceSunken,
              ),
              title: Text(l10n.pushNameHidden),
              subtitle: Text(l10n.pushNameHiddenHint),
              isThreeLine: true,
              value: choice.nameHidden,
              onChanged: (value) => unawaited(
                alert
                    .setNameHidden(hidden: value)
                    .then((result) => mounted ? _tell(result) : null),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
