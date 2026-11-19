import 'package:family_groceries/core/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgetbook/widgetbook.dart';

/// The app's two themes, as `appTheme` builds them.
final themes = {
  'Hell': appTheme(Brightness.light),
  'Dunkel': appTheme(Brightness.dark),
};

/// The text sizes the app is checked at: the default, a common larger
/// setting and the largest the layouts promise to hold.
class TextSizeAddon() extends Addon<double> with SingleFieldOnly {
  this : super(name: 'Textgröße', initialValue: 1);

  @override
  Field<double> get field => ObjectSegmentedField<double>(
    name: 'faktor',
    values: const [1, 1.3, 2],
    initialValue: initialValue,
    labelBuilder: (factor) => '${factor}x',
  );

  @override
  Widget apply(BuildContext context, Widget child, double setting) =>
      MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(setting)),
        child: child,
      );
}

/// The platform's reduce-motion setting: the design system's animations
/// (`hlMotion`) jump instead of moving.
class ReducedMotionAddon({bool on = false})
    extends Addon<bool>
    with SingleFieldOnly {
  this : super(name: 'Bewegung reduzieren', initialValue: on);

  @override
  Field<bool> get field => BooleanField(name: 'an', initialValue: initialValue);

  @override
  Widget apply(BuildContext context, Widget child, bool setting) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: setting),
    child: child,
  );
}

/// [ReducedMotionAddon] turned on or off, for a scenario or a test.
class ReducedMotionMode({required bool on}) extends Mode<bool> {
  this : super(on, ReducedMotionAddon(on: on));

  @override
  String get formattedValue => value ? 'an' : 'aus';
}
