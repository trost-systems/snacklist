import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The node a screen reader knows by [identifier] (`Semantics.identifier`).
FinderBase<SemanticsNode> bySemanticsId(String identifier) =>
    find.semantics.byPredicate((node) => node.identifier == identifier);

/// What the screen reader is told from now on, in order: `focus: label`
/// (the label of the node the focus is sent to) and `say: message`. Takes
/// the place of [WidgetTester.takeAnnouncements] for the test.
List<String> screenReaderLog(WidgetTester tester) {
  final log = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  // The binding puts its own back only over its own handler.
  addTearDown(
    () => messenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      null,
    ),
  );
  messenger.setMockDecodedMessageHandler<Object?>(
    SystemChannels.accessibility,
    (message) async {
      switch (message) {
        case {'type': 'announce', 'data': {'message': final String said}}:
          log.add('say: $said');
        case {'type': 'focus', 'nodeId': final int id}:
          log.add('focus: ${_labelOf(id)}');
      }
      return null;
    },
  );
  return log;
}

String? _labelOf(int id) {
  String? label;
  void visit(SemanticsNode node) {
    if (node.id == id) {
      label = node.label;
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  for (final view in RendererBinding.instance.renderViews) {
    if (view.owner?.semanticsOwner?.rootSemanticsNode case final root?) {
      visit(root);
    }
  }
  return label;
}
