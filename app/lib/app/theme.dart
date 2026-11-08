import 'dart:async';

import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/fonts.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The dim over the page behind a sheet: the add sheet's scrim and every
/// modal bottom sheet's barrier.
const sheetBarrier = Color(0x66000000);

/// The Material roles of the Hummlist palette (6b Hex Frische, design job
/// 52): cobalt is primary, lemon ("honey") secondary, mint tertiary; outline
/// is the navy contour. Every colour comes from `tokens.g.dart`.
ColorScheme hummlistColorScheme(Brightness brightness) {
  final t = HummlistColors.of(brightness);
  final light = brightness == Brightness.light;
  return ColorScheme(
    brightness: brightness,
    primary: t.brand,
    onPrimary: t.onBrand,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: t.onAccentSoft,
    secondary: t.honey,
    onSecondary: t.onHoney,
    secondaryContainer: t.honeySoft,
    onSecondaryContainer: t.text,
    tertiary: t.success,
    onTertiary: t.onSuccess,
    tertiaryContainer: t.mintSoft,
    onTertiaryContainer: t.text,
    error: t.error,
    onError: t.onError,
    errorContainer: Color.alphaBlend(
      t.error.withValues(alpha: light ? 0.14 : 0.22),
      t.surfaceRaised,
    ),
    onErrorContainer: t.text,
    surface: t.surface,
    onSurface: t.text,
    onSurfaceVariant: t.textMuted,
    surfaceDim: light ? t.surfaceSunken : t.surface,
    surfaceBright: t.surfaceRaised,
    surfaceContainerLowest: light ? t.surfaceRaised : t.surface,
    surfaceContainerLow: t.surfaceRaised,
    surfaceContainer: light ? t.surfaceSunken : t.surfaceRaised,
    surfaceContainerHigh: light
        ? t.surfaceSunken
        : Color.lerp(t.surfaceRaised, t.divider, 0.3),
    surfaceContainerHighest: Color.lerp(
      t.surfaceSunken,
      t.divider,
      light ? 0.5 : 0.7,
    ),
    outline: t.border,
    outlineVariant: t.divider,
    shadow: t.edge,
    scrim: const Color(0xFF000000),
    inverseSurface: light ? t.inverse : t.text,
    onInverseSurface: light ? t.onInverse : t.surface,
    inversePrimary: light ? t.honey : t.cobalt,
    surfaceTint: Colors.transparent,
  );
}

/// Material's type scale in the Hummlist fonts: Bricolage Grotesque for
/// display, headline and title, Inter for everything else. The sizes stay
/// Material's ([geometry]: ThemeData only applies them in `Theme.of`), so
/// layouts and text scaling behave as before, except the small roles, which
/// share [captionSize].
///
/// Every style splits its leading evenly above and below the glyphs: with
/// Material's proportional split, a line taller than the font (1.5 for
/// body text) carries its caps low, off the middle of a hex (job 148).
TextTheme _textTheme(TextTheme base, TextTheme geometry) {
  TextStyle display(
    TextStyle? Function(TextTheme) role,
    FontWeight weight,
    double tracking,
  ) => role(base)!.copyWith(
    fontFamily: HlFont.display,
    fontWeight: weight,
    letterSpacing: tracking * role(geometry)!.fontSize!,
    leadingDistribution: TextLeadingDistribution.even,
  );
  TextStyle sans(
    TextStyle? Function(TextTheme) role, [
    FontWeight? weight,
    double? size,
  ]) => role(base)!.copyWith(
    fontFamily: HlFont.sans,
    fontWeight: weight,
    fontSize: size,
    leadingDistribution: TextLeadingDistribution.even,
  );
  return base.copyWith(
    displayLarge: display((t) => t.displayLarge, FontWeight.w800, -0.04),
    displayMedium: display((t) => t.displayMedium, FontWeight.w800, -0.04),
    displaySmall: display((t) => t.displaySmall, FontWeight.w800, -0.035),
    headlineLarge: display((t) => t.headlineLarge, FontWeight.w800, -0.035),
    headlineMedium: display((t) => t.headlineMedium, FontWeight.w800, -0.03),
    headlineSmall: display((t) => t.headlineSmall, FontWeight.w800, -0.025),
    titleLarge: display((t) => t.titleLarge, FontWeight.w700, -0.02),
    titleMedium: display((t) => t.titleMedium, FontWeight.w700, -0.01),
    titleSmall: display((t) => t.titleSmall, FontWeight.w700, 0),
    bodyLarge: sans((t) => t.bodyLarge),
    bodyMedium: sans((t) => t.bodyMedium),
    bodySmall: sans((t) => t.bodySmall, null, captionSize),
    labelLarge: sans((t) => t.labelLarge, FontWeight.w600),
    labelMedium: sans((t) => t.labelMedium, FontWeight.w600, captionSize),
    labelSmall: sans((t) => t.labelSmall, FontWeight.w600, captionSize),
  );
}

/// The app's theme in [brightness], built from the design tokens
/// (`design/tokens/hummlist.tokens.json`): the colour scheme above, the
/// fonts, and the 6b shapes: tactile hex buttons on a hard edge, hex chips
/// and indicators, rounded cards and sheets with the navy contour.
ThemeData appTheme(Brightness brightness) {
  final t = HummlistColors.of(brightness);
  final scheme = hummlistColorScheme(brightness);
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: HlFont.sans,
  );
  // Sizes merged in now, so component themes built from it have them too.
  final text = _textTheme(
    base.typography.englishLike.merge(base.textTheme),
    base.typography.englishLike,
  );
  final label = text.labelLarge!.copyWith(fontWeight: FontWeight.w700);
  final contour = BorderSide(color: t.edge, width: HlBorder.width);
  final muted = _muted(t);

  // The one main action: lemon face, navy contour, darker lemon edge.
  final primary = tactileButtonStyle(
    colors: (states) => states.contains(WidgetState.disabled)
        ? muted
        : TactileColors(
            face: t.honey,
            contour: t.edge,
            edge: t.honeyEdge,
            focus: t.accent,
          ),
    foreground: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? t.textMuted : t.onHoney,
    ),
    textStyle: label,
  );
  // Second rank: raised surface face on a surface edge.
  final secondary = tactileButtonStyle(
    colors: (states) => states.contains(WidgetState.disabled)
        ? muted
        : TactileColors(
            face: t.surfaceRaised,
            contour: t.border,
            edge: t.surfaceEdge,
            focus: t.accent,
          ),
    foreground: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? t.textMuted : t.text,
    ),
    textStyle: label,
  );

  RoundedRectangleBorder rounded(double radius, [BorderSide? side]) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: side ?? BorderSide.none,
      );

  return base.copyWith(
    textTheme: text,
    extensions: [t],
    scaffoldBackgroundColor: t.surface,
    dividerTheme: DividerThemeData(color: t.divider),
    appBarTheme: AppBarTheme(
      backgroundColor: t.surface,
      foregroundColor: t.text,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge!.copyWith(color: t.text),
    ),
    filledButtonTheme: FilledButtonThemeData(style: primary),
    elevatedButtonTheme: ElevatedButtonThemeData(style: primary),
    outlinedButtonTheme: OutlinedButtonThemeData(style: secondary),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.brand,
        textStyle: label,
        shape: const HexBorder(),
        minimumSize: const Size(48, HlSize.target),
        padding: const EdgeInsets.symmetric(
          horizontal: HlHex.tip * HlSize.target,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: HexBorder(side: BorderSide(color: t.border)),
      side: BorderSide(color: t.border),
      backgroundColor: t.surfaceRaised,
      selectedColor: t.honey,
      checkmarkColor: t.onHoney,
      labelStyle: text.labelLarge!.copyWith(color: t.text),
      secondaryLabelStyle: text.labelLarge!.copyWith(color: t.onHoney),
      padding: const EdgeInsets.symmetric(horizontal: HlSpace.s3),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const HexBorder(),
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected) ? t.edge : t.border,
          width: HlBorder.width,
        ),
      ),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? t.honey : null,
      ),
      checkColor: WidgetStatePropertyAll(t.onHoney),
    ),
    cardTheme: CardThemeData(
      color: t.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: rounded(
        HlRadius.m,
        BorderSide(color: t.border, width: HlBorder.width),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: rounded(HlRadius.l, contour),
      titleTextStyle: text.headlineSmall!.copyWith(color: t.text),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(HlRadius.l)),
      ),
      dragHandleColor: t.textMuted,
      modalBarrierColor: sheetBarrier,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.surfaceRaised,
      elevation: 0,
      contentTextStyle: text.titleSmall!.copyWith(color: t.text),
      actionTextColor: t.brand,
      insetPadding: const EdgeInsets.all(HlSpace.s3),
      shape: rounded(HlRadius.m, contour),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: t.honey,
      indicatorShape: HexBorder(side: contour),
      selectedIconTheme: IconThemeData(color: t.onHoney),
      unselectedIconTheme: IconThemeData(color: t.textMuted),
      selectedLabelTextStyle: text.labelMedium!.copyWith(
        color: t.text,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: text.labelMedium!.copyWith(color: t.textMuted),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.brand),
    listTileTheme: ListTileThemeData(iconColor: t.textMuted),
    inputDecorationTheme: fieldTheme(t, FieldShape.hex),
  );
}

/// A disabled tactile button: flush on its edge, in muted colours.
TactileColors _muted(HummlistColors t) => TactileColors(
  face: t.surfaceSunken,
  contour: t.textMuted,
  edge: t.textMuted,
  focus: t.accent,
);

/// The destructive main action (Konto löschen): an error-red face on the
/// navy edge, tactile like every other button.
ButtonStyle dangerButtonStyle(BuildContext context) {
  final theme = Theme.of(context);
  final t = HummlistColors.of(theme.brightness);
  return tactileButtonStyle(
    colors: (states) => states.contains(WidgetState.disabled)
        ? _muted(t)
        : TactileColors(
            face: t.error,
            contour: t.edge,
            edge: t.edge,
            focus: t.accent,
          ),
    foreground: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? t.textMuted : t.onError,
    ),
    textStyle: theme.textTheme.labelLarge!.copyWith(
      fontWeight: FontWeight.w700,
    ),
  );
}

/// How a stored theme choice reads: `light`, `dark`, or anything else for
/// the device's setting.
ThemeMode themeModeOf(String? name) => switch (name) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

/// Light, dark or the device's setting, picked under More's Einstellungen
/// and kept on the device. The device's setting by default.
class ThemeCubit(final DeviceCache _cache, super.initialState)
    extends Cubit<ThemeMode> {
  void pick(ThemeMode mode) {
    emit(mode);
    unawaited(_cache.saveTheme(mode == ThemeMode.system ? null : mode.name));
  }
}

/// The WCAG 2 contrast ratio of two opaque colours, 1 to 21. AA asks 4.5
/// for text, 3 for large text and for the parts of a control.
double contrastRatio(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}
