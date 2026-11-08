import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/hex_segmented.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// More's Einstellungen (`/more/settings`): the theme as one segmented
/// control, System, Hell or Dunkel; and the language, a row that opens
/// [LanguageScreen]. Both are kept on the device and apply at once.
class const SettingsScreen({super.key}) extends StatelessWidget {
  /// More's RECHTLICHES overline: over its group, at the group's inset.
  static const _labelPadding = EdgeInsets.fromLTRB(20, HlSpace.s5, 20, 0);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.watch<ThemeCubit>();
    final t = HummlistColors.of(Theme.of(context).brightness);
    return ListView(
      key: const ValueKey('settings-screen'),
      padding: const EdgeInsets.only(bottom: HlSpace.s5),
      children: [
        HlSectionLabel(l10n.appearance, padding: _labelPadding),
        HlGroup(
          top: HlSpace.s2,
          children: [
            Padding(
              padding: const EdgeInsets.all(HlSpace.s3),
              child: HexSegmented<ThemeMode>(
                key: const ValueKey('theme-mode'),
                label: l10n.appearance,
                value: theme.state,
                onChanged: theme.pick,
                segments: [
                  HexSegment(
                    key: const ValueKey('theme-system'),
                    value: ThemeMode.system,
                    label: l10n.themeSystem,
                    icon: Icons.brightness_auto_outlined,
                  ),
                  HexSegment(
                    key: const ValueKey('theme-light'),
                    value: ThemeMode.light,
                    label: l10n.themeLight,
                    icon: Icons.light_mode_outlined,
                  ),
                  HexSegment(
                    key: const ValueKey('theme-dark'),
                    value: ThemeMode.dark,
                    label: l10n.themeDark,
                    icon: Icons.dark_mode_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
        HlSectionLabel(l10n.language, padding: _labelPadding),
        HlGroup(
          top: HlSpace.s2,
          children: [
            ListTile(
              key: const ValueKey('settings-language'),
              minTileHeight: 56,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: HlSpace.s3,
              ),
              leading: HlRowHex(Icons.language, face: t.surfaceSunken),
              title: Text(l10n.language),
              subtitle: Text(switch (context.watch<LanguageCubit>().state) {
                final picked? => picked.nativeName,
                null => l10n.languageSystemPicked(
                  deviceLanguage(context).nativeName,
                ),
              }),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(languagePath),
            ),
          ],
        ),
      ],
    );
  }
}

/// The language list (`/more/settings/language`): the device's language
/// first, then every language the app speaks, each in its own name. A list
/// page rather than a dropdown or segments: it takes any number of
/// languages, shows the pick and what the device gives at a glance, and
/// reads well to a screen reader (DECISIONS 29e).
class const LanguageScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RadioGroup<AppLanguage?>(
      groupValue: context.watch<LanguageCubit>().state,
      onChanged: (language) => context.read<LanguageCubit>().pick(language),
      child: ListView(
        key: const ValueKey('language-screen'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          HexRadioTile<AppLanguage?>(
            key: const ValueKey('language-system'),
            value: null,
            title: Text(l10n.languageSystem),
            subtitle: Text(
              l10n.languageSystemNow(deviceLanguage(context).nativeName),
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          for (final language in AppLanguage.values)
            HexRadioTile<AppLanguage?>(
              key: ValueKey('language-${language.code}'),
              value: language,
              title: Text(language.nativeName),
            ),
        ],
      ),
    );
  }
}

/// The language the app speaks when it follows the device.
AppLanguage deviceLanguage(BuildContext context) => AppLanguage.byCode(
  resolveLocale(View.of(context).platformDispatcher.locales, null).languageCode,
)!;
