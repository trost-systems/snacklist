import 'package:family_groceries/settings/access_repository.dart';
import 'package:flutter/widgets.dart';

/// What the app lends the hints beyond the list (job 168b): `main` passes
/// the real one to `App`, tests a fake or none.
@immutable
class const HintHost({
  /// Opens the household creation flow. Null while the app cannot add a
  /// second household (creating one today leaves the current one): then the
  /// hints with that button (`own-household`, `second-household`) never
  /// show. Job 169b sets it in `main.dart`, the one place to flip.
  final void Function(BuildContext context)? addHousehold,

  /// Whether an AI assistant or automation has access; null where the app
  /// cannot ask.
  final Future<bool> Function()? assistantConnected,

  /// Whether a Home Screen widget is placed; null without widgets.
  final Future<bool> Function()? widgetPlaced,
}) {
  bool get canAddHousehold => addHousehold != null;
}

/// Whether [access] lists an MCP client's grant, an MCP token or an API
/// key; Siri's credential is not an assistant.
Future<bool> assistantConnected(AccessRepository access) async {
  final (apps, tokens) = await (access.fetchApps(), access.fetchTokens()).wait;
  return apps.isNotEmpty || tokens.any((t) => t.kind != AccessKind.siri);
}
