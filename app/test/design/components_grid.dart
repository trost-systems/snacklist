// The themed components in every state, for components_golden_test.dart
// and rd1_golden_test.dart.
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/hex_checkbox.dart';
import 'package:family_groceries/design/hex_segmented.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:family_groceries/list/stores_screen.dart';
import 'package:material_ui/material_ui.dart';

typedef _State = ({String name, Set<WidgetState> states, bool enabled});

const List<_State> _states = [
  (name: 'Ruhe', states: {}, enabled: true),
  (name: 'Hover', states: {WidgetState.hovered}, enabled: true),
  (name: 'Fokus', states: {WidgetState.focused}, enabled: true),
  (name: 'Gedrückt', states: {WidgetState.pressed}, enabled: true),
  (name: 'Aus', states: {WidgetState.disabled}, enabled: false),
];

/// Every themed component in every state, in [brightness]; [extra] rows
/// below the sticker, the app's [locale] when set.
Widget componentsGrid(
  Brightness brightness, {
  Locale? locale,
  List<Widget> extra = const [],
}) {
  Widget cell(Widget child) =>
      SizedBox(width: 150, height: 72, child: Center(child: child));
  Widget row(String label, Widget Function(_State s) build) => Row(
    children: [
      SizedBox(width: 90, child: Text(label)),
      for (final s in _states) cell(build(s)),
    ],
  );
  VoidCallback? on(_State s) => s.enabled ? () {} : null;
  WidgetStatesController controller(_State s) =>
      WidgetStatesController(s.states);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(brightness),
    locale: locale,
    localizationsDelegates: locale == null ? null : appLocalizationsDelegates,
    supportedLocales: locale == null
        ? const [Locale('en', 'US')]
        : AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(HlSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 90),
                    for (final s in _states)
                      SizedBox(
                        width: 150,
                        child: Center(
                          child: Text(
                            s.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ),
                  ],
                ),
                row(
                  'Filled',
                  (s) => FilledButton(
                    statesController: controller(s),
                    onPressed: on(s),
                    child: const Text('Anlegen'),
                  ),
                ),
                row(
                  'Filled.icon',
                  (s) => FilledButton.icon(
                    statesController: controller(s),
                    onPressed: on(s),
                    icon: const Icon(Icons.add),
                    label: const Text('Neu'),
                  ),
                ),
                row(
                  'Outlined',
                  (s) => OutlinedButton(
                    statesController: controller(s),
                    onPressed: on(s),
                    child: const Text('Später'),
                  ),
                ),
                row(
                  'Text',
                  (s) => TextButton(
                    statesController: controller(s),
                    onPressed: on(s),
                    child: const Text('Abbrechen'),
                  ),
                ),
                row(
                  'Chip',
                  (s) => ChoiceChip(
                    label: const Text('Fehler'),
                    selected: s.states.contains(WidgetState.pressed),
                    onSelected: s.enabled ? (_) {} : null,
                  ),
                ),
                row(
                  'Checkbox',
                  (s) => Checkbox(
                    value: s.states.contains(WidgetState.pressed),
                    onChanged: s.enabled ? (_) {} : null,
                  ),
                ),
                Row(
                  children: [
                    const SizedBox(width: 90, child: Text('Switch')),
                    for (final (caption, value, enabled, autofocus) in const [
                      ('Aus', false, true, false),
                      ('An', true, true, false),
                      ('Fokus', true, true, true),
                      ('Aus, gesperrt', false, false, false),
                      ('An, gesperrt', true, false, false),
                    ])
                      SizedBox(
                        width: 150,
                        height: 88,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            HexSwitch(
                              value: value,
                              onChanged: enabled ? (_) {} : null,
                              autofocus: autofocus,
                            ),
                            Text(
                              caption,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(width: 90, child: Text('Hex-Box')),
                    for (final (caption, value, enabled, autofocus) in const [
                      ('Aus', false, true, false),
                      ('An', true, true, false),
                      ('Fokus', true, true, true),
                      ('Aus, gesperrt', false, false, false),
                      ('An, gesperrt', true, false, false),
                    ])
                      SizedBox(
                        width: 150,
                        height: 72,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            HexCheckbox(
                              value: value,
                              onChanged: enabled ? (_) {} : null,
                              autofocus: autofocus,
                            ),
                            Text(
                              caption,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 90,
                      height: 72,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('Felder'),
                      ),
                    ),
                    for (final field in [
                      const LabeledField(label: 'E-Mail', field: TextField()),
                      // The switch and box below hold the one real focus.
                      LabeledField(
                        label: 'Laden',
                        field: InputDecorator(
                          isFocused: true,
                          decoration: const InputDecoration(),
                          child: Text(
                            'Lidl',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ),
                      LabeledField(
                        label: 'E-Mail',
                        field: TextField(
                          controller: TextEditingController(text: 'peter'),
                          decoration: const InputDecoration(
                            errorText: 'Keine E-Mail',
                          ),
                        ),
                      ),
                      const LabeledField(
                        label: 'Code',
                        field: TextField(enabled: false),
                      ),
                      const RoundedFields(
                        child: TextField(
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'Nachricht',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                    ])
                      Container(
                        width: 150,
                        height: 120,
                        padding: const EdgeInsets.symmetric(
                          horizontal: HlSpace.s3,
                          vertical: HlSpace.s2,
                        ),
                        alignment: AlignmentDirectional.topCenter,
                        child: field,
                      ),
                  ],
                ),
                SizedBox(
                  height: 72,
                  child: Row(
                    spacing: HlSpace.s4,
                    children: [
                      const SizedBox(width: 74, child: Text('Segmente')),
                      for (final (value, enabled) in const [
                        (1, true),
                        (2, false),
                      ])
                        SizedBox(
                          width: 300,
                          child: HexSegmented<int>(
                            value: value,
                            onChanged: enabled ? (_) {} : null,
                            segments: const [
                              HexSegment(
                                value: 0,
                                label: 'System',
                                icon: Icons.brightness_auto_outlined,
                              ),
                              HexSegment(
                                value: 1,
                                label: 'Hell',
                                icon: Icons.light_mode_outlined,
                              ),
                              HexSegment(
                                value: 2,
                                label: 'Dunkel',
                                icon: Icons.dark_mode_outlined,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  spacing: HlSpace.s4,
                  children: [
                    const SizedBox(width: 90, child: Text('Laden')),
                    FilledButton(
                      onPressed: () {},
                      child: const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                    AddButton(onPressed: () {}, label: 'Kategorie'),
                    for (final store in const [
                      Store(id: 'dm', name: 'dm', sortOrder: 0, seedKey: 'dm'),
                      Store(
                        id: 'lidl',
                        name: 'Lidl',
                        sortOrder: 0,
                        seedKey: 'lidl',
                      ),
                      Store(id: 'own', name: 'Bäcker', sortOrder: 0),
                    ])
                      StoreBadge(store),
                  ],
                ),
                const SizedBox(height: HlSpace.s4),
                Card(
                  child: ListTile(
                    title: const Text('Karte'),
                    subtitle: Text(
                      'Oberfläche, Kontur, Radius m',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(height: HlSpace.s2),
                HlSticker(
                  child: ListTile(
                    title: const Text('Sticker'),
                    subtitle: Text(
                      'Kontur und harter Schatten',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                ...extra,
                const SizedBox(height: HlSpace.s4),
                Builder(
                  builder: (context) => Text(
                    'Snacklist',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
