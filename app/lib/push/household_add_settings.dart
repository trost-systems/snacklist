import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/design/word_wrap.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Mitteilungen's household-add group (job 377, its own More page since job
/// 463): the switch for the push when another member adds an item, shown on
/// iOS and Android builds with push, and the switch that leaves the user's
/// name out, everywhere; while the `push-household-add` flag is on. Off by
/// default. A tap moves a switch at once; one the server or the OS refuses
/// goes back, with a notice.
class const HouseholdAddSettings({super.key}) extends StatefulWidget {
  @override
  State<HouseholdAddSettings> createState() => _HouseholdAddSettingsState();
}

class _HouseholdAddSettingsState() extends State<HouseholdAddSettings> {
  /// What the switches show until their last tap is answered; null shows
  /// the alert's state.
  bool? _on;
  bool? _nameHidden;
  var _onTaps = 0;
  var _nameHiddenTaps = 0;

  /// Taps reach the alert one after another, so a quick on and off are
  /// saved in the order they were made.
  Future<void> _queue = Future.value();

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

  void _setOn(HouseholdAddAlert alert, {required bool on}) {
    final language = Localizations.localeOf(context).languageCode;
    final tap = ++_onTaps;
    setState(() => _on = on);
    _send(
      () => alert.set(on: on, language: language),
      settled: () => _on = tap == _onTaps ? null : _on,
    );
  }

  void _setNameHidden(HouseholdAddAlert alert, {required bool hidden}) {
    final tap = ++_nameHiddenTaps;
    setState(() => _nameHidden = hidden);
    _send(
      () => alert.setNameHidden(hidden: hidden),
      settled: () => _nameHidden = tap == _nameHiddenTaps ? null : _nameHidden,
    );
  }

  /// Sends a tap after the ones before it; [settled] hands the switch back
  /// to the alert's state unless a later tap moved it again.
  void _send(
    Future<HouseholdAddResult> Function() save, {
    required void Function() settled,
  }) {
    _queue = _queue.then((_) async {
      var result = HouseholdAddResult.failed;
      try {
        result = await save();
      } on Object {
        // Told below as a failed save.
      }
      if (mounted) {
        setState(settled);
        await _tell(result);
      }
    });
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
    // The page's title says Mitteilungen; the group needs no label.
    return HlGroup(
      children: [
        if (alert.canNotify)
          HexSwitchTile(
            key: const ValueKey('settings-push-household-add'),
            leading: HlRowHex(Icons.notifications_none, face: t.surfaceSunken),
            title: HlWordWrapText(l10n.pushHouseholdAdd),
            subtitle: HlWordWrapText(l10n.pushHouseholdAddHint),
            isThreeLine: true,
            value: _on ?? choice.on,
            onChanged: (value) => _setOn(alert, on: value),
          ),
        HexSwitchTile(
          key: const ValueKey('settings-push-name-hidden'),
          leading: HlRowHex(
            Icons.visibility_off_outlined,
            face: t.surfaceSunken,
          ),
          title: HlWordWrapText(l10n.pushNameHidden),
          subtitle: HlWordWrapText(l10n.pushNameHiddenHint),
          isThreeLine: true,
          value: _nameHidden ?? choice.nameHidden,
          onChanged: (value) => _setNameHidden(alert, hidden: value),
        ),
      ],
    );
  }
}
