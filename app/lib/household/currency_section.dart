import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/focus_ring.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The household page's "Währung" (job 190): the currency prices and the
/// list's total are in, for everyone in the household; any member changes
/// it. Only with the prices flag and the household's list above it.
class const CurrencySection({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final on = context.select<Flags?, bool>(
      (flags) => flags?.isOn(pricesFlag) ?? false,
    );
    final cubit = context.watch<ListCubit?>();
    if (!on || cubit == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final code = cubit.state.catalog.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HlSectionLabel(l10n.currencyTitle),
        FocusRingTile(
          key: const ValueKey('household-currency'),
          child: ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(_name(context, code)),
            subtitle: Text(l10n.currencyHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_pick(context, cubit, code)),
          ),
        ),
      ],
    );
  }

  static String _name(BuildContext context, String code) {
    final symbol = currencySymbol(
      code,
      Localizations.localeOf(context).toString(),
    );
    return symbol == code ? code : '$code · $symbol';
  }

  Future<void> _pick(BuildContext context, ListCubit cubit, String now) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        key: const ValueKey('currency-picker'),
        title: Text(AppLocalizations.of(dialog).currencyPick),
        children: [
          RadioGroup<String>(
            groupValue: now,
            onChanged: (code) => Navigator.of(dialog).pop(code),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final code in currencies)
                  FocusRingTile(
                    key: ValueKey('currency-$code'),
                    child: RadioListTile<String>(
                      value: code,
                      title: Text(_name(dialog, code)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null && picked != now) {
      await cubit.setCurrency(picked);
    }
  }
}
