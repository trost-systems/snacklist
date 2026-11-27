import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// How long after the frame that shows a change VoiceOver or TalkBack hears
/// about it. A row that leaves the tree moves VoiceOver's focus (to the
/// screen's first element when it held it), and VoiceOver then reads that
/// element over an announcement made before; one made after cuts in
/// instead (job 474).
const announceSettle = Duration(milliseconds: 300);

/// What the screen reader of a view hears, and where its focus goes, after
/// a change the user made. Taken from a context before an `await`, it can
/// still speak once that context is gone.
final class ScreenReader(
  final FlutterView _view,
  final PipelineOwner _owner,
  final TextDirection _direction,
) {
  factory of(BuildContext context) => ScreenReader(
    View.of(context),
    View.pipelineOwnerOf(context),
    Directionality.of(context),
  );

  /// Says [message] once the change it tells of shows: after the next frame,
  /// [announceSettle] later while VoiceOver or TalkBack runs. Announcements
  /// of the same moment (a tick and the card it brings) go out as one, in
  /// order.
  void announce(String message) => _batch().messages.add(message);

  /// Moves the focus to the first of [identifiers] (`Semantics.identifier`)
  /// still there, or the first node with a label inside it, with the
  /// announcements of the same moment and before them. The last request
  /// wins. Nothing without a screen reader, or when none is there by then.
  void moveFocus(List<String> identifiers) => _batch().focus.add(identifiers);

  /// The identifiers starting with [prefix], in reading order; none without
  /// a screen reader.
  List<String> identifiers(String prefix) {
    final ids = <String>[];
    void collect(SemanticsNode node) {
      if (node.identifier.startsWith(prefix)) {
        ids.add(node.identifier);
      }
      _inOrder(node).forEach(collect);
    }

    if (_owner.semanticsOwner?.rootSemanticsNode case final root?) {
      collect(root);
    }
    return ids;
  }

  /// The identifier after [identifier] among those starting with [prefix],
  /// else the one before; null without another. Asked while [identifier]'s
  /// node is still there, so the focus can stay where the user was once it
  /// goes.
  String? neighbourOf(String identifier, String prefix) {
    final ids = identifiers(prefix);
    final at = ids.indexOf(identifier);
    if (at < 0) {
      return null;
    }
    return at + 1 < ids.length ? ids[at + 1] : (at > 0 ? ids[at - 1] : null);
  }

  _Batch _batch() => _batches.putIfAbsent(_view, () {
    final batch = _Batch(this);
    final binding = SchedulerBinding.instance;
    // Only VoiceOver and TalkBack move a focus that could read it over.
    final navigating =
        binding.platformDispatcher.accessibilityFeatures.accessibleNavigation;
    binding
      ..addPostFrameCallback(
        (_) => navigating ? Timer(announceSettle, batch.send) : batch.send(),
      )
      ..ensureVisualUpdate();
    return batch;
  });
}

final _batches = <FlutterView, _Batch>{};

final class _Batch(final ScreenReader reader) {
  final messages = <String>[];
  final focus = <List<String>>[];

  void send() {
    _batches.remove(reader._view);
    final root = reader._owner.semanticsOwner?.rootSemanticsNode;
    if ((focus.lastOrNull, root) case (final ids?, final root?)) {
      ids
          .map((id) => _readable(_find(root, id)))
          .nonNulls
          .firstOrNull
          ?.sendEvent(const FocusSemanticEvent());
    }
    if (messages.isNotEmpty) {
      unawaited(
        SemanticsService.sendAnnouncement(
          reader._view,
          _sentences(messages),
          reader._direction,
        ),
      );
    }
  }
}

/// "Milch abgehakt" and "Lidl ist erledigt" as two sentences.
String _sentences(List<String> messages) => messages.length == 1
    ? messages.single
    : messages.map((m) => RegExp(r'[.!?…]$').hasMatch(m) ? m : '$m.').join(' ');

List<SemanticsNode> _inOrder(SemanticsNode node) =>
    node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder);

SemanticsNode? _find(SemanticsNode node, String identifier) {
  if (node.identifier == identifier) {
    return node;
  }
  for (final child in _inOrder(node)) {
    if (_find(child, identifier) case final found?) {
      return found;
    }
  }
  return null;
}

/// [node] when it has a label, else its first descendant that has one.
SemanticsNode? _readable(SemanticsNode? node) {
  if (node == null || node.label.isNotEmpty) {
    return node;
  }
  for (final child in _inOrder(node)) {
    if (_readable(child) case final found?) {
      return found;
    }
  }
  return null;
}
