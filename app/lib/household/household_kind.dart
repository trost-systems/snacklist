/// Who a household shops with, from onboarding's „Mit wem kaufst du ein?“
/// (job 168b), stored as `households.kind`. Its [name] is the wire value;
/// never rename one.
enum HouseholdKind() {
  partner,
  family,
  flat,
  club,
  solo,
  other;

  /// The kind of the wire value [name], or null for none or an unknown one
  /// (a newer server's).
  static HouseholdKind? parse(Object? name) =>
      values.where((k) => k.name == name).firstOrNull;
}
