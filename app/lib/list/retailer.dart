import 'package:family_groceries/analytics/events.dart' show retailerCountries;
import 'package:family_groceries/list/retailer_registry.g.dart';
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

/// The phone's region when the app's registry has chains there, else null
/// (a phone set to the UK or the US): the country whose chains the
/// onboarding offers as chips (job 321). On the web the browser's language
/// names it (`de-AT`); never the location.
String? registryRegion() {
  final code = WidgetsBinding.instance.platformDispatcher.locale.countryCode
      ?.toUpperCase();
  return retailerRegistry.any((r) => r.country == code) ? code : null;
}

/// The chains of [country] in the registry's order, the onboarding's chips;
/// none for null.
List<Retailer> registryChains(String? country) => [
  for (final r in retailerRegistry)
    if (r.country == country) r,
];

/// A name as matching compares it, as `public.retailer_key` does: lower
/// case, diacritics and ß folded, every run of other characters one space.
String retailerKey(String name) {
  final folded = StringBuffer();
  for (final char in name.toLowerCase().split('')) {
    folded.write(_folds[char] ?? char);
  }
  return folded.toString().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();
}

const _from = 'àáâãäåāăąçćčďđèéêëēėęěìíîïīįłñńňòóôõöøōőŕřśšşșťțùúûüūůűųýÿźżž';
const _to = 'aaaaaaaaacccddeeeeeeeeiiiiiilnnnoooooooorrssssttuuuuuuuuyyzzz';
final _folds = {
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  for (var i = 0; i < _from.length; i++) _from[i]: _to[i],
};

/// The chains [typed] names, from the app's registry, as
/// `public.match_retailers` answers before sign-in (the onboarding has no
/// account yet): the exact matches first, of several only the longest
/// name, [country]'s alone when it has one; then the chains whose name or
/// an alias starts with it (two characters or more). At most five; with
/// [country] null every country counts the same.
List<RetailerMatch> matchRegistry(
  String typed,
  String? country, {
  List<Retailer> registry = retailerRegistry,
}) {
  final k = retailerKey(typed);
  if (k.isEmpty) {
    return const [];
  }
  List<String> keysOf(Retailer r) => [
    for (final name in [r.name, ...r.aliases]) retailerKey(name),
  ];
  final exact = <Retailer, int>{
    for (final r in registry)
      if (keysOf(r).where((key) => k == key || k.startsWith('$key '))
          case final hits when hits.isNotEmpty)
        r: hits.map((h) => h.length).reduce((a, b) => a > b ? a : b),
  };
  final longest = exact.values.fold(0, (a, b) => a > b ? a : b);
  final best = [
    for (final MapEntry(:key, :value) in exact.entries)
      if (value == longest) key,
  ];
  final home = best.any((r) => r.country == country);
  final prefix = [
    if (k.length >= 2)
      for (final r in registry)
        if (!exact.containsKey(r) && keysOf(r).any((key) => key.startsWith(k)))
          r,
  ];
  int byCountryAndName(Retailer a, Retailer b) {
    final here =
        (b.country == country ? 1 : 0) - (a.country == country ? 1 : 0);
    if (here != 0) {
      return here;
    }
    for (final (x, y) in [
      (a.name.toLowerCase(), b.name.toLowerCase()),
      (a.country, b.country),
      (a.chain, b.chain),
    ]) {
      if (x.compareTo(y) case final order when order != 0) {
        return order;
      }
    }
    return 0;
  }

  return [
    for (final r in [
      for (final r in best)
        if (!home || r.country == country) r,
    ]..sort(byCountryAndName))
      RetailerMatch(r, exact: true),
    for (final r in prefix..sort(byCountryAndName))
      RetailerMatch(r, exact: false),
  ].take(5).toList();
}

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

  /// What a chip and a store made from it are called when shorter than
  /// [name] („Netto“); only the app's copy of the registry has it (job 321).
  final String? short,

  /// Further names people type for it, lower case; only the app's copy of
  /// the registry has them.
  final List<String> aliases = const [],

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

  /// The name a chip shows and a store picked from one gets.
  String get label => short ?? name;

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
