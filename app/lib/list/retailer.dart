import 'package:family_groceries/analytics/events.dart' show retailerCountries;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show WidgetsBinding;

/// The phone's region (ISO 3166-1 alpha-2, upper case), read when asked:
/// the country whose chains a store name matches first. Germany when the
/// device names none or one the registry has no chains for (an en-US
/// browser would otherwise rank Austria's Lidl above Germany's).
String phoneRegion() => switch (WidgetsBinding
    .instance
    .platformDispatcher
    .locale
    .countryCode
    ?.toUpperCase()) {
  final String code when retailerCountries.contains(code) => code,
  _ => 'DE',
};

/// A chain's app, as `public.retailers.apps` lists it (job 313). Its
/// [android] package is its identity: `stores.retailer_app` names it.
@immutable
class const RetailerApp({
  required final String name,
  required final String android,

  /// The App Store id, digits only.
  required final String ios,

  /// An https link the app claims (iOS universal link), opening its home;
  /// none when the chain's site claims none that lands there.
  final String? universalLink,
}) {
  /// Null for a row without a name or both store ids, so one bad entry
  /// leaves the chain's other apps and the list itself working.
  static RetailerApp? tryParse(Object? json) => switch (json) {
    {
      'name': final String name,
      'android': final String android,
      'ios': final String ios,
    } =>
      RetailerApp(
        name: name,
        android: android,
        ios: ios,
        universalLink: switch (json['universalLink']) {
          final String link when link.isNotEmpty => link,
          _ => null,
        },
      ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'name': name,
    'android': android,
    'ios': ios,
    'universalLink': universalLink,
  };
}

/// A chain in one country, an entry of `public.retailers`: a store of the
/// household can be linked to one.
@immutable
class const Retailer({
  /// The registry's id of the chain, the same in every country (`lidl`).
  required final String chain,

  /// ISO 3166-1 alpha-2, upper case.
  required final String country,
  required final String name,

  /// The chain's apps, the default (loyalty or coupon app) first.
  final List<RetailerApp> apps = const [],
}) {
  factory fromJson(Map<String, Object?> json) => Retailer(
    chain: json['chain']! as String,
    country: json['country']! as String,
    name: json['name']! as String,
    apps: [
      if (json['apps'] case final List<Object?> apps)
        for (final app in apps) ?RetailerApp.tryParse(app),
    ],
  );

  Map<String, Object?> toJson() => {
    'chain': chain,
    'country': country,
    'name': name,
    'apps': [for (final app in apps) app.toJson()],
  };

  /// What identifies the entry: `public.retailers`' primary key.
  ({String chain, String country}) get key => (chain: chain, country: country);

  /// The app with the [android] package, else the default; null for a chain
  /// without an app.
  RetailerApp? app(String? android) =>
      apps.where((a) => a.android == android).firstOrNull ?? apps.firstOrNull;
}

/// A chain whose name or alias matches a typed store name
/// (`public.match_retailers`).
@immutable
class const RetailerMatch(
  final Retailer retailer, {

  /// The typed name is the chain's name or alias, or starts with it and a
  /// space („Lidl am Markt“); otherwise it is only the start of one („Li“).
  required final bool exact,
}) {
  factory fromJson(Map<String, Object?> json) =>
      RetailerMatch(Retailer.fromJson(json), exact: json['exact'] == true);

  /// The name a store gets when the user picks this match for [typed]: the
  /// chain's own name when the text was only its start, else the text.
  String storeName(String typed) => exact ? typed.trim() : retailer.name;
}

/// An existing store to ask about once: is it one of [chains]
/// (`public.retailer_questions`)?
@immutable
class const StoreQuestion({
  required final String storeId,

  /// One chain, or several when the name fits more than one („Aldi“).
  required final List<Retailer> chains,
}) {
  /// One question per store, in the order the rows came.
  static List<StoreQuestion> group(List<Map<String, Object?>> rows) {
    final chains = <String, List<Retailer>>{};
    for (final row in rows) {
      (chains[row['store_id']! as String] ??= []).add(Retailer.fromJson(row));
    }
    return [
      for (final MapEntry(:key, :value) in chains.entries)
        StoreQuestion(storeId: key, chains: value),
    ];
  }
}
