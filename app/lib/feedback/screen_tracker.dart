import 'package:family_groceries/shell/router.dart';

/// Follows the router's location so a shake can say which screen a note is
/// about (job 21, DECISIONS 21.6; job 267: More's row sends none). Only
/// [screenNames] are ever reported.
class ScreenTracker() {
  var _current = 'list';

  /// The router moved to [location].
  void visit(Uri location) => _current = screenNameOf(location);

  /// The screen on show now.
  String get current => _current;
}
