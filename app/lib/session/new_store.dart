import 'package:flutter/foundation.dart' show immutable;

/// A store to create with a new household, as picked in the guided start
/// or for a further household: its name and, when it is a chain of the
/// registry, which one (job 321). A linked store opens that chain's app
/// and is not asked about later.
@immutable
class const NewStore(
  final String name, {

  /// `public.retailers`' key of the chain; null for a store of its own.
  final ({String chain, String country})? chain,
}) {
  /// A plain string is a store from a draft written before job 321.
  static NewStore? fromJson(Object? json) => switch (json) {
    final String name => NewStore(name),
    {
      'name': final String name,
      'chain': final String chain,
      'country': final String country,
    } =>
      NewStore(name, chain: (chain: chain, country: country)),
    {'name': final String name} => NewStore(name),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'name': name,
    'chain': chain?.chain,
    'country': chain?.country,
  };

  @override
  bool operator ==(Object other) =>
      other is NewStore && other.name == name && other.chain == chain;

  @override
  int get hashCode => Object.hash(name, chain);

  @override
  String toString() => switch (chain) {
    (:final chain, :final country) => 'NewStore($name, $chain/$country)',
    null => 'NewStore($name)',
  };
}
