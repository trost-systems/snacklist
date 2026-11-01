// GENERATED from design/tokens/hummlist.tokens.json by design/tokens/build.mjs. Do not edit.
import 'package:flutter/material.dart';

/// Every colour token, in light or dark. Read it with
/// `Theme.of(context).extension<HummlistColors>()!` or [HummlistColors.of].
@immutable
class HummlistColors extends ThemeExtension<HummlistColors> {
  const HummlistColors({
    required this.brand,
    required this.onBrand,
    required this.honey,
    required this.onHoney,
    required this.honeySoft,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.divider,
    required this.ink,
    required this.success,
    required this.onSuccess,
    required this.successSoft,
    required this.warning,
    required this.onWarning,
    required this.error,
    required this.onError,
    required this.edge,
    required this.honeyEdge,
    required this.surfaceEdge,
    required this.mint,
    required this.onMint,
    required this.mintSoft,
    required this.mintEdge,
    required this.cobalt,
    required this.onCobalt,
    required this.onAccentSoft,
    required this.tomato,
    required this.onTomato,
    required this.tomatoEdge,
    required this.inverse,
    required this.onInverse,
  });

  /// Kobalt: Schrift, Linien und Mengen („2×“) auf hellem Grund
  final Color brand;
  final Color onBrand;

  /// Zitrone: Knöpfe und Blöcke, auch direkt auf und neben Kobalt, immer mit Navy darauf
  final Color honey;
  final Color onHoney;

  /// Zitrone hell: neue Einträge, Antworten
  final Color honeySoft;

  /// Kobalt hell, Kobalt-Hell nachts: Links und Fokusring auf hellem Grund
  final Color accent;
  final Color onAccent;

  /// Kobalt-Nebel (brand-container von 5): ein Block, Sprechblasen, Avatare
  final Color accentSoft;

  /// Kreideweiß von 5: die Luft zwischen den Blöcken
  final Color surface;

  /// Karten, Listen, Eingabefeld
  final Color surfaceRaised;

  /// Blaugrauer Hauch von 5: Mulden und Bildflächen
  final Color surfaceSunken;

  /// Navy statt Schwarz
  final Color text;
  final Color textMuted;

  /// Die 2-px-Kontur in Navy
  final Color border;

  /// Haarlinien (die border-Farbe von 5)
  final Color divider;

  /// Kontur auf Zitrone, Kante unter Karten
  final Color ink;

  /// Abgehakt und synchron
  final Color success;
  final Color onSuccess;
  final Color successSoft;
  final Color warning;
  final Color onWarning;
  final Color error;
  final Color onError;
  final Color edge;
  final Color honeyEdge;
  final Color surfaceEdge;

  /// Mint: Nebenblock und Häkchen
  final Color mint;
  final Color onMint;
  final Color mintSoft;

  /// Seitenwand eines Mint-Knopfs
  final Color mintEdge;

  /// Kobalt als Fläche: Hero, Privatsphäre, E-Mail-Kopf
  final Color cobalt;
  final Color onCobalt;

  /// Schrift auf Kobalt-Nebel
  final Color onAccentSoft;

  /// Tomate: echter Akzentblock (Stimme) und Hervorhebung
  final Color tomato;
  final Color onTomato;

  /// Seitenwand eines Tomaten-Knopfs
  final Color tomatoEdge;

  /// Navy-Band: der Fuß
  final Color inverse;
  final Color onInverse;

  static const light = HummlistColors(
    brand: Color(0xFF1B3FAE),
    onBrand: Color(0xFFFFFFFF),
    honey: Color(0xFFFFE24A),
    onHoney: Color(0xFF0F1530),
    honeySoft: Color(0xFFFFF2A8),
    accent: Color(0xFF1B3FAE),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE1E8FF),
    surface: Color(0xFFF7F7F2),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFECEFF6),
    text: Color(0xFF0F1530),
    textMuted: Color(0xFF4B536C),
    border: Color(0xFF0F1530),
    divider: Color(0xFFD3D8E6),
    ink: Color(0xFF0F1530),
    success: Color(0xFF0D7A4E),
    onSuccess: Color(0xFFFFFFFF),
    successSoft: Color(0xFFD6F5E7),
    warning: Color(0xFF8A5300),
    onWarning: Color(0xFFFFFFFF),
    error: Color(0xFFC4280F),
    onError: Color(0xFFFFFFFF),
    edge: Color(0xFF0F1530),
    honeyEdge: Color(0xFFD4B20F),
    surfaceEdge: Color(0xFFC3CAE0),
    mint: Color(0xFF7FE3B8),
    onMint: Color(0xFF0F1530),
    mintSoft: Color(0xFFD6F5E7),
    mintEdge: Color(0xFF3FBF8A),
    cobalt: Color(0xFF1B3FAE),
    onCobalt: Color(0xFFFFFFFF),
    onAccentSoft: Color(0xFF132F86),
    tomato: Color(0xFFFF5B3A),
    onTomato: Color(0xFF0F1530),
    tomatoEdge: Color(0xFFC8402A),
    inverse: Color(0xFF0F1530),
    onInverse: Color(0xFFF3F6FF),
  );

  static const dark = HummlistColors(
    brand: Color(0xFF9FB6FF),
    onBrand: Color(0xFF0B1024),
    honey: Color(0xFFFFE24A),
    onHoney: Color(0xFF0B1024),
    honeySoft: Color(0xFF35310F),
    accent: Color(0xFF9FB6FF),
    onAccent: Color(0xFF0B1024),
    accentSoft: Color(0xFF1D2B66),
    surface: Color(0xFF0B1024),
    surfaceRaised: Color(0xFF151C3A),
    surfaceSunken: Color(0xFF111735),
    text: Color(0xFFEFF3FF),
    textMuted: Color(0xFFB0B9D8),
    border: Color(0xFF7F8CC4),
    divider: Color(0xFF2F3A66),
    ink: Color(0xFF03050F),
    success: Color(0xFF62C99D),
    onSuccess: Color(0xFF0B1024),
    successSoft: Color(0xFF123A31),
    warning: Color(0xFFFFD25A),
    onWarning: Color(0xFF0B1024),
    error: Color(0xFFFF8A73),
    onError: Color(0xFF0B1024),
    edge: Color(0xFF03050F),
    honeyEdge: Color(0xFFB39B1A),
    surfaceEdge: Color(0xFF2A3463),
    mint: Color(0xFF62C99D),
    onMint: Color(0xFF0B1024),
    mintSoft: Color(0xFF123A31),
    mintEdge: Color(0xFF3A9E78),
    cobalt: Color(0xFF2448C0),
    onCobalt: Color(0xFFFFFFFF),
    onAccentSoft: Color(0xFFE1E8FF),
    tomato: Color(0xFFF0603F),
    onTomato: Color(0xFF0B1024),
    tomatoEdge: Color(0xFFB04530),
    inverse: Color(0xFF111735),
    onInverse: Color(0xFFEFF3FF),
  );

  static HummlistColors of(Brightness brightness) => switch (brightness) {
    Brightness.light => light,
    Brightness.dark => dark,
  };

  @override
  HummlistColors copyWith() => this;

  @override
  HummlistColors lerp(HummlistColors? other, double t) {
    if (other == null) {
      return this;
    }
    return HummlistColors(
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      honey: Color.lerp(honey, other.honey, t)!,
      onHoney: Color.lerp(onHoney, other.onHoney, t)!,
      honeySoft: Color.lerp(honeySoft, other.honeySoft, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
      honeyEdge: Color.lerp(honeyEdge, other.honeyEdge, t)!,
      surfaceEdge: Color.lerp(surfaceEdge, other.surfaceEdge, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      onMint: Color.lerp(onMint, other.onMint, t)!,
      mintSoft: Color.lerp(mintSoft, other.mintSoft, t)!,
      mintEdge: Color.lerp(mintEdge, other.mintEdge, t)!,
      cobalt: Color.lerp(cobalt, other.cobalt, t)!,
      onCobalt: Color.lerp(onCobalt, other.onCobalt, t)!,
      onAccentSoft: Color.lerp(onAccentSoft, other.onAccentSoft, t)!,
      tomato: Color.lerp(tomato, other.tomato, t)!,
      onTomato: Color.lerp(onTomato, other.onTomato, t)!,
      tomatoEdge: Color.lerp(tomatoEdge, other.tomatoEdge, t)!,
      inverse: Color.lerp(inverse, other.inverse, t)!,
      onInverse: Color.lerp(onInverse, other.onInverse, t)!,
    );
  }
}

abstract final class HlFont {
  static const display = 'Bricolage Grotesque';
  static const sans = 'Inter';
}

abstract final class HlType {
  static const display = TextStyle(
    fontFamily: HlFont.display,
    fontSize: 72,
    fontWeight: FontWeight.w800,
    height: 0.94,
    letterSpacing: -3.24,
  );
  static const headlineL = TextStyle(
    fontFamily: HlFont.display,
    fontSize: 48,
    fontWeight: FontWeight.w800,
    height: 0.98,
    letterSpacing: -1.92,
  );
  static const headline = TextStyle(
    fontFamily: HlFont.display,
    fontSize: 36,
    fontWeight: FontWeight.w800,
    height: 1,
    letterSpacing: -1.26,
  );
  static const title = TextStyle(
    fontFamily: HlFont.display,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.44,
  );
  static const bodyL = TextStyle(
    fontFamily: HlFont.sans,
    fontSize: 19,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: -0.114,
  );
  static const body = TextStyle(
    fontFamily: HlFont.sans,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.55,
    letterSpacing: 0,
  );
  static const label = TextStyle(
    fontFamily: HlFont.sans,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0,
  );
  static const caption = TextStyle(
    fontFamily: HlFont.sans,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 1.08,
  );
}

abstract final class HlSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
  static const double s7 = 48;
  static const double s8 = 64;
  static const double s9 = 96;
}

abstract final class HlRadius {
  static const double s = 12;
  static const double m = 18;
  static const double l = 28;
  static const double xl = 40;
  static const double full = 999;
}

abstract final class HlBorder {
  /// Sticker outline
  static const double width = 2;
  static const double widthThin = 1;
}

abstract final class HlDepth {
  static const double edge = 4;
  static const double edgeL = 6;
  static const double lift = 2;

  /// How far the face sinks on press: all the way into its edge
  static const double press = 4;
}

abstract final class HlFocus {
  /// Focus ring around a hex control, drawn on the unmasked control so the hex mask never clips it
  static const double ringWidth = 3;

  /// Surface-coloured gap between the control and its focus ring
  static const double ringGap = 2;
}

abstract final class HlSize {
  /// Minimum interactive target, face plus edge
  static const double target = 48;
}

abstract final class HlHex {
  /// Width of each pointed end as a fraction of the control's height. 0.2887 = 1/(2·tan 60°): all six corners are 120°, the honeycomb angle.
  static const double tip = 0.2887;

  /// Height at which corner-radius applies; the radius scales with the control's height
  static const double referenceHeight = 48;

  /// Hex Soft: every corner rounded with this radius at reference-height (48 px), scaled with the control's height
  static const double cornerRadius = 8;
}

abstract final class HlDuration {
  static const short = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 260);
  static const long = Duration(milliseconds: 360);

  /// Face sinking on press
  static const press = Duration(milliseconds: 70);

  /// Face returning after press or hover
  static const release = Duration(milliseconds: 160);
}

abstract final class HlEasing {
  /// Overshoot: ticks, presses, stickers settling
  static const bounce = Cubic(0.34, 1.56, 0.64, 1);
  static const standard = Cubic(0.2, 0, 0, 1);
  static const exit = Cubic(0.4, 0, 1, 1);
  static const press = Cubic(0.3, 0, 0.6, 1);
}
