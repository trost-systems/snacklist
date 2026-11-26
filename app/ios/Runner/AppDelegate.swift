import Flutter
import Intents
import Speech
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // After every install or update, not only once a list has loaded and the app pushed its
    // suggestions: Siri trains the App Shortcut phrases with these parameters (job 92).
    SnacklistShortcuts.updateAppShortcutParameters()
    // Each time the app comes forward until the user has answered: asking only when the app
    // stored a new Siri credential left installs that kept theirs, or missed the question at
    // sign-in, without "Use with Siri" (job 467).
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { _ in
      SiriAuthorization.askIfUndetermined()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// SiriKit's Lists domain in-app (SiriKitLists.swift): what no App Shortcut phrase matches.
  override func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
    switch intent {
    case is INAddTasksIntent: return AddTasksHandler(client: .live(caller: "Lists.add"))
    case is INSearchForNotebookItemsIntent: return SearchTasksHandler(client: .live(caller: "Lists.read"))
    default: return nil
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OfflineSpeech") {
      OfflineSpeech.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SiriBridge") {
      SiriBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StorePrices") {
      StorePrices.register(with: registrar)
    }
  }
}

/// Answers lib/list/dictation.dart's check: speech_to_text reports a device
/// without on-device recognition in the app's language only once listening
/// has started. Gets the candidate locales, best first (en_GB, en_US), and
/// answers the first one Siri recognizes on the device as "installed", else
/// "missing".
final class OfflineSpeech: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "familygroceries/speech", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(OfflineSpeech(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "offlineSpeech",
      let locales = (call.arguments as? [String: Any])?["locales"] as? [String]
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    let ready = locales.first {
      SFSpeechRecognizer(locale: Locale(identifier: $0))?.supportsOnDeviceRecognition == true
    }
    result(ready.map { ["status": "installed", "locale": $0] } ?? ["status": "missing"])
  }
}

/// lib/purchases/store_prices.dart's prices, read from StoreKit 2 before
/// the user taps Buy (Legal Review A2-5). It only reads product details and
/// opens Apple's subscription sheet: no transaction observer, no
/// Transaction.updates, no purchase. Purchases go through RevenueCat alone.
final class StorePrices: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "familygroceries/store_prices", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(StorePrices(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prices":
      guard let args = call.arguments as? [String: Any],
        let yearly = args["yearly"] as? String,
        let lifetime = args["lifetime"] as? String
      else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      Task { @MainActor in
        result(await Self.prices(yearly: yearly, lifetime: lifetime))
      }
    case "manageSubscriptions":
      Task { @MainActor in
        result(await Self.manageSubscriptions())
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Null when StoreKit fails, which Dart reads as no answer. A product the
  /// storefront does not sell is simply missing from StoreKit's list, and
  /// null in the map: the page hides that plan.
  private static func prices(yearly: String, lifetime: String) async -> Any? {
    let products: [Product]
    do {
      products = try await Product.products(for: [yearly, lifetime])
    } catch {
      return nil
    }
    func price(_ id: String, _ type: Product.ProductType) -> Any {
      guard let product = products.first(where: { $0.id == id && $0.type == type }) else {
        return NSNull()
      }
      return ["price": product.displayPrice, "currency": product.priceFormatStyle.currencyCode]
    }
    return [
      "yearly": price(yearly, .autoRenewable),
      "lifetime": price(lifetime, .nonConsumable),
    ]
  }

  /// False without a foreground window scene or when StoreKit fails: Dart
  /// then opens Apple's subscriptions page.
  @MainActor
  private static func manageSubscriptions() async -> Bool {
    guard
      let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive })
    else {
      return false
    }
    do {
      try await AppStore.showManageSubscriptions(in: scene)
      return true
    } catch {
      return false
    }
  }
}
