import 'package:family_groceries/design/tokens.g.dart';

/// The app's shapes: today's hexagons (6b Hex Frische) or RD1's soft
/// rounded rectangles (job 368).
enum Look() {
  hex,
  soft,
}

/// The look of this app run.
///
/// Set once before `runApp` (`main.dart`) from the forced flags or the last
/// value of the `redesign-rd1` flag the device saw; tests set it and reset
/// it in tearDown. It never changes while the app runs: const shapes, clip
/// caches and theme radii would keep the old look, so a new value takes
/// effect on the next start.
Look appLook = Look.hex;

/// Whether this run has RD1's soft shapes.
bool get softLook => appLook == Look.soft;

/// A card's corners ([HlRadius.m]; [HlSoft.lg] under the soft look): the
/// default of every sticker, group and snack bar.
double get cardRadius => softLook ? HlSoft.lg : HlRadius.m;

/// A sheet's top corners and a dialog's ([HlRadius.l]; [HlSoft.xl] under
/// the soft look).
double get sheetRadius => softLook ? HlSoft.xl : HlRadius.l;

/// The corner radius of a soft shape whose shorter side is [side], nested
/// by size: a badge [HlSoft.xs], a chip [HlSoft.sm], a button or field
/// [HlSoft.md], the tab bar capsule and anything larger [HlSoft.lg].
double softRadius(double side) => switch (side) {
  < 28 => HlSoft.xs,
  < 40 => HlSoft.sm,
  < 60 => HlSoft.md,
  _ => HlSoft.lg,
};
