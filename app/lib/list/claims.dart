import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';

/// The line under an item that members bring (job 169b L): "Mia bringt",
/// "Mia bringt 2 · Tom bringt 1", "Du bringst" for [userId]'s own claim.
/// Null without claims.
String? claimLine(
  AppLocalizations l10n,
  List<Claim> claims,
  Catalog catalog,
  String userId,
) {
  if (claims.isEmpty) {
    return null;
  }
  return [
    for (final Claim(userId: by, :quantity) in claims)
      switch ((by == userId, quantity)) {
        (true, null) => l10n.claimYou,
        (true, final amount?) => l10n.claimYouAmount(amount),
        (false, null) => l10n.claimBy(_name(l10n, catalog, by)),
        (false, final amount?) => l10n.claimByAmount(
          _name(l10n, catalog, by),
          amount,
        ),
      },
  ].join(' · ');
}

String _name(AppLocalizations l10n, Catalog catalog, String userId) =>
    switch (catalog.member(userId)?.displayName) {
      final name? when name.trim().isNotEmpty => name,
      _ => l10n.claimSomeone,
    };
