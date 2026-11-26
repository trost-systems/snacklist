import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:family_groceries/push/household_add_settings.dart';
import 'package:family_groceries/settings/shopping_day.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// More's Mitteilungen (`/more/notifications`, job 463): the household-add
/// alert's switches and the shopping-day reminder, which sat in
/// Einstellungen before.
class const NotificationsPage({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('notifications-page'),
    padding: EdgeInsets.only(
      bottom: HlSpace.s5 + MediaQuery.paddingOf(context).bottom,
    ),
    children: const [HouseholdAddSettings(), ShoppingDaySettings()],
  );
}

/// Whether Mitteilungen has a section to show under [flags]: the
/// household-add alert with `push-household-add` (its name switch also on
/// the web), the shopping-day reminder with `push-shopping-day` in a build
/// with push.
bool notificationsShown(BuildContext context, Flags? flags) =>
    ((flags?.isOn(pushHouseholdAddFlag) ?? false) &&
        context.read<HouseholdAddAlert?>() != null) ||
    ((flags?.isOn(shoppingDayFlag) ?? false) &&
        context.read<ShoppingDayService?>() != null);
