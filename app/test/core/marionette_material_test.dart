import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_driver/marionette_material.dart';

void main() {
  testWidgets(
    'fg sees material_ui buttons, fields and checkboxes, and reads a field',
    (tester) async {
      final controller = TextEditingController(text: 'Milch');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
                FilledButton(onPressed: () {}, child: const Text('Speichern')),
                Checkbox(value: false, onChanged: (_) {}),
                TextField(controller: controller),
              ],
            ),
          ),
        ),
      );
      final elements = [
        find.byType(IconButton),
        find.byType(FilledButton),
        find.byType(Checkbox),
        find.byType(TextField),
      ].map((finder) => tester.element(finder)).toList();

      const builtIn = MarionetteConfiguration();
      expect(elements.where(builtIn.isElementInteractive), isEmpty);
      expect(
        elements.every(materialUiConfiguration.isElementInteractive),
        isTrue,
      );
      expect(
        elements.every(materialUiConfiguration.shouldStopAtElement),
        isTrue,
      );
      expect(
        materialUiConfiguration.extractTextFromWidget(elements.last),
        'Milch',
      );
    },
  );
}
