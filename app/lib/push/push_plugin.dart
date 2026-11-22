/// The platform a token belongs to, as `register_push_token` takes it.
enum PushPlatform() {
  ios,
  android,
}

/// Whether the OS lets this app show notifications.
enum PushPermission() {
  /// Allowed (on iOS also provisionally).
  granted,

  /// Not asked yet: a request shows the OS prompt.
  undetermined,

  /// Refused, at the prompt or later in the system settings.
  denied,
}

/// The messaging SDK as the app needs it (docs/PUSH.md, "The app"). The
/// only implementation is `FirebasePush`; tests fake it.
abstract interface class PushPlugin() {
  PushPlatform get platform;

  /// The current permission; never prompts.
  Future<PushPermission> permission();

  /// Shows the OS prompt where it still can, and answers the permission.
  Future<PushPermission> requestPermission();

  /// This device's token, created if there is none; null if the platform
  /// has none to give (iOS without an APNs token yet).
  Future<String?> token();

  /// Each new token that replaces the one before.
  Stream<String> get tokenRefreshes;

  /// Deletes the token at the messaging service; it then delivers nothing
  /// more to this device.
  Future<void> deleteToken();

  /// The `data` of the notification whose tap started the app, if any.
  Future<Map<String, Object?>?> initialMessage();

  /// The `data` of each notification whose tap brought the app back.
  Stream<Map<String, Object?>> get openedMessages;
}
