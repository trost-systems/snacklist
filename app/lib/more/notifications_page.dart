import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:family_groceries/push/household_add_settings.dart';
import 'package:family_groceries/settings/shopping_day.dart';
import 'package:family_groceries/settings/shopping_reminders.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// More's Benachrichtigungen & Erinnerungen (`/more/notifications`, job 463,
/// renamed in job 472): the household-add alert's switches with the name
/// switch (Art. 21, Legal M2: on the same page as the reminders), then the
/// shopping reminders, SR1 or, without its flag, the weekday chips.
class const NotificationsPage({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final reminders = context.select<Flags?, bool>(
      (flags) => flags?.isOn(shoppingRemindersFlag) ?? false,
    );
    return ListView(
      key: const ValueKey('notifications-page'),
      padding: EdgeInsets.only(
        bottom: HlSpace.s5 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const HouseholdAddSettings(),
        // SR1 replaces the weekday chips where it is on (job 472).
        if (reminders && context.read<ShoppingReminders?>() != null)
          const ShoppingRemindersSettings()
        else
          const ShoppingDaySettings(),
      ],
    );
  }
}

/// Whether the page has a section to show under [flags]: the household-add
/// group whenever the app has it, since its name switch is never flagged
/// (N-425), the shopping reminders with `push-shopping-reminders` or the
/// weekday chips with `push-shopping-day`, both in a build with push.
bool notificationsShown(BuildContext context, Flags? flags) =>
    context.read<HouseholdAddAlert?>() != null ||
    ((flags?.isOn(shoppingRemindersFlag) ?? false) &&
        context.read<ShoppingReminders?>() != null) ||
    ((flags?.isOn(shoppingDayFlag) ?? false) &&
        context.read<ShoppingDayService?>() != null);
