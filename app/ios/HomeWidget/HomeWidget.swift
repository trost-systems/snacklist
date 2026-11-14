import SwiftUI
import WidgetKit

struct HomeWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: ListSnapshot
}

/// Shows what the app last wrote to the App Group. The app reloads the timeline through WidgetCenter
/// whenever it writes, so the widget never refreshes on its own.
struct HomeWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> HomeWidgetEntry {
    HomeWidgetEntry(date: .now, snapshot: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (HomeWidgetEntry) -> Void) {
    let snapshot = ListSnapshot.read()
    // The gallery shows a list rather than the prompt when the app has written nothing yet.
    let shown = context.isPreview && snapshot == .noData ? ListSnapshot.sample : snapshot
    completion(HomeWidgetEntry(date: .now, snapshot: shown))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<HomeWidgetEntry>) -> Void) {
    let entry = HomeWidgetEntry(date: .now, snapshot: ListSnapshot.read())
    completion(Timeline(entries: [entry], policy: .never))
  }
}

struct HomeWidget: Widget {
  static let kind = "HomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: HomeWidget.kind, provider: HomeWidgetProvider()) { entry in
      HomeWidgetView(snapshot: entry.snapshot)
    }
    .configurationDisplayName(String("Snacklist"))
    .description("Your shopping list at a glance")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

extension ListSnapshot {
  /// The widget gallery's example list, in the phone's language.
  static let sample = ListSnapshot.ready(
    open: 9,
    items: [
      ListItem(name: String(localized: "Oat milk"), quantity: "2 l", store: "Rewe"),
      ListItem(name: String(localized: "Apples"), quantity: "1 kg", store: "Rewe"),
      ListItem(name: String(localized: "Toothpaste"), quantity: nil, store: "dm-drogerie markt"),
      ListItem(name: String(localized: "Bread"), quantity: nil, store: String(localized: "Schneider's Bakery on Market Square")),
      ListItem(name: String(localized: "Basil"), quantity: String(localized: "1 pot"), store: nil),
      ListItem(name: String(localized: "Coffee beans"), quantity: "500 g", store: nil),
    ])
}

#Preview("Small", as: .systemSmall) {
  HomeWidget()
} timeline: {
  HomeWidgetEntry(date: .now, snapshot: .sample)
  HomeWidgetEntry(date: .now, snapshot: .ready(open: 0, items: []))
  HomeWidgetEntry(date: .now, snapshot: .signedOut)
}

#Preview("Medium", as: .systemMedium) {
  HomeWidget()
} timeline: {
  HomeWidgetEntry(date: .now, snapshot: .sample)
  HomeWidgetEntry(date: .now, snapshot: .ready(open: 0, items: []))
  HomeWidgetEntry(date: .now, snapshot: .signedOut)
}
