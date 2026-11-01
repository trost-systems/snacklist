// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Hummlist';

  @override
  String get addFieldHint => 'Was brauchst du?';

  @override
  String get addButton => 'Hinzufügen';

  @override
  String get emptyList => 'Die Liste ist leer. Tippe unten ein, was fehlt.';

  @override
  String get sortingItem => 'Wird einsortiert …';

  @override
  String get recentlyUsed => 'Zuletzt verwendet';

  @override
  String get readd => 'Wieder auf die Liste';

  @override
  String itemDeleted(String name) {
    return '$name gelöscht';
  }

  @override
  String itemReadded(String name) {
    return '$name steht wieder auf der Liste';
  }

  @override
  String itemTicked(String name) {
    return '$name abgehakt';
  }

  @override
  String alreadyOnList(String name) {
    return '$name steht schon auf der Liste';
  }

  @override
  String get dedupeMerge => 'Zusammenführen';

  @override
  String dedupeMerged(String item) {
    return 'Zusammengeführt: $item';
  }

  @override
  String mergeRefused(String name) {
    return '$name konnte nicht zusammengeführt werden';
  }

  @override
  String get dictationStart => 'Diktieren';

  @override
  String get dictationStop => 'Diktat beenden';

  @override
  String get dictationListening => 'Ich höre zu …';

  @override
  String get dictationUnavailable =>
      'Spracheingabe ist nicht verfügbar. Erlaube Mikrofon und Spracherkennung in den Einstellungen.';

  @override
  String get dictationNoOfflineGerman =>
      'Diktieren geht nur offline, damit deine Stimme auf dem Gerät bleibt. Dafür fehlt hier die deutsche Offline-Spracherkennung. Lade sie in den Systemeinstellungen herunter oder tippe den Eintrag ein.';

  @override
  String get dictationNothingHeard => 'Ich habe nichts gehört.';

  @override
  String get dictationNothingUnderstood =>
      'Ich habe nichts verstanden, was auf die Liste soll.';

  @override
  String get dictationSplitFailed =>
      'Keine Verbindung. Der Text steht im Feld; prüfe ihn und tippe auf Hinzufügen.';

  @override
  String dictationAdded(String items) {
    return 'Hinzugefügt: $items.';
  }

  @override
  String dictationAlreadyOnList(String items) {
    return 'Schon auf der Liste: $items.';
  }

  @override
  String get undo => 'Rückgängig';

  @override
  String editTitle(String name) {
    return 'Bearbeiten: $name';
  }

  @override
  String get editSheet => 'Bearbeiten';

  @override
  String get fieldName => 'Bezeichnung';

  @override
  String get fieldBrand => 'Marke';

  @override
  String get brandNone => 'ohne Marke';

  @override
  String get itemQuantity => 'Menge';

  @override
  String get fieldProperties => 'Eigenschaften';

  @override
  String get propertiesExample => 'z. B. Bio, 1 l';

  @override
  String get quantityMinus => 'Eins weniger';

  @override
  String get quantityPlus => 'Eins mehr';

  @override
  String get noStore => 'Ohne Laden';

  @override
  String chipStore(String name) {
    return 'Laden: $name';
  }

  @override
  String chipCategory(String name) {
    return 'Kategorie: $name';
  }

  @override
  String get categoryAuto => 'Kategorie: automatisch';

  @override
  String get editHint => 'Gespeichert wird nur, was du änderst';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get offline =>
      'Offline: Änderungen werden synchronisiert, sobald die Verbindung zurück ist';

  @override
  String pendingChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen werden synchronisiert',
      one: '1 Änderung wird synchronisiert',
    );
    return '$_temp0';
  }

  @override
  String syncFailed(String name) {
    return 'Änderung abgelehnt: $name';
  }

  @override
  String get inviteMember => 'Partner einladen';

  @override
  String get joinOtherHousehold => 'Anderem Haushalt beitreten';

  @override
  String get signOut => 'Abmelden';

  @override
  String get inviteTitle => 'Mitglied einladen';

  @override
  String get inviteBody =>
      'Gib diesen Code in der App ein oder teile den Link. Die Einladung gilt 7 Tage und für eine Person.';

  @override
  String get inviteCodeLabel => 'Code';

  @override
  String get inviteLinkLabel => 'Link';

  @override
  String get copy => 'Kopieren';

  @override
  String get copied => 'Kopiert';

  @override
  String get close => 'Schließen';

  @override
  String get signInTitle => 'Anmelden';

  @override
  String get email => 'E-Mail';

  @override
  String get password => 'Passwort';

  @override
  String get signIn => 'Anmelden';

  @override
  String get signUp => 'Registrieren';

  @override
  String get sendMagicLink => 'Anmeldelink per E-Mail senden';

  @override
  String get magicLinkSent =>
      'Wir haben dir einen Anmeldelink geschickt. Öffne ihn auf diesem Gerät.';

  @override
  String get signUpCheckEmail =>
      'Bitte bestätige deine E-Mail-Adresse über den Link, den wir dir geschickt haben.';

  @override
  String get invalidEmail => 'Bitte eine gültige E-Mail-Adresse eingeben';

  @override
  String get passwordTooShort => 'Mindestens 6 Zeichen';

  @override
  String authFailed(String message) {
    return 'Anmeldung fehlgeschlagen: $message';
  }

  @override
  String get signInWithGoogle => 'Mit Google anmelden';

  @override
  String get signInWithApple => 'Mit Apple anmelden';

  @override
  String get signInCanceled => 'Anmeldung abgebrochen';

  @override
  String get orWithEmail => 'oder mit E-Mail';

  @override
  String get onboardingTitle => 'Willkommen bei Hummlist';

  @override
  String get onboardingBody =>
      'Hummlist teilt eine Einkaufsliste mit allen in deinem Haushalt. Erstelle einen neuen Haushalt oder nimm eine Einladung an.';

  @override
  String get householdName => 'Name des Haushalts';

  @override
  String get householdNameDefault => 'Unser Haushalt';

  @override
  String get createHousehold => 'Haushalt erstellen';

  @override
  String get inviteCode => 'Einladungscode';

  @override
  String get joinHousehold => 'Haushalt beitreten';

  @override
  String get joinTitle => 'Haushalt beitreten';

  @override
  String get invalidInvite => 'Dieser Code ist ungültig oder abgelaufen.';

  @override
  String get switchHouseholdWarning =>
      'Du verlässt deinen aktuellen Haushalt. Bist du der letzte, wird er mit seiner Liste gelöscht.';

  @override
  String genericError(String message) {
    return 'Etwas ist schiefgelaufen: $message';
  }

  @override
  String get loading => 'Lädt …';

  @override
  String get consentTitle => 'Zugriff erlauben?';

  @override
  String consentSignedInAs(String email) {
    return 'Angemeldet als $email';
  }

  @override
  String consentHousehold(String name) {
    return 'Haushalt: $name';
  }

  @override
  String consentWants(String client) {
    return '$client möchte:';
  }

  @override
  String consentListAccess(String client) {
    return 'Einträge deiner Einkaufsliste lesen, hinzufügen, abhaken und verschieben. $client und sein Anbieter erhalten dabei die Inhalte eurer Liste.';
  }

  @override
  String get scopeOpenid => 'Deine Anmeldung bestätigen';

  @override
  String get scopeEmail => 'Deine E-Mail-Adresse';

  @override
  String get scopeProfile => 'Dein Name und Profil';

  @override
  String get scopePhone => 'Deine Telefonnummer';

  @override
  String get scopeOfflineAccess => 'Dauerhaft angemeldet bleiben';

  @override
  String get consentAllow => 'Erlauben';

  @override
  String get consentDeny => 'Ablehnen';

  @override
  String get redirecting => 'Weiterleitung …';

  @override
  String get consentInvalid =>
      'Diese Anfrage ist ungültig oder abgelaufen. Starte die Verbindung in deiner App neu.';

  @override
  String get consentErrorTitle => 'Verbindung abgelaufen';

  @override
  String get consentBackToList => 'Zurück zur Liste';

  @override
  String get accessTitle => 'Zugänge';

  @override
  String get mcpServer => 'MCP-Server';

  @override
  String get mcpServerBody =>
      'Für Claude, ChatGPT und andere KI-Assistenten. Verbinde per Anmeldung (OAuth) oder mit einem Zugriffstoken.';

  @override
  String get accessTokens => 'Zugriffstoken';

  @override
  String get noTokens => 'Kein aktiver Token.';

  @override
  String tokenHint(String hint) {
    return '…$hint';
  }

  @override
  String createdOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Erstellt am $dateString';
  }

  @override
  String lastUsedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Zuletzt benutzt $dateString';
  }

  @override
  String get neverUsed => 'Noch nie benutzt';

  @override
  String get createToken => 'Token erstellen';

  @override
  String get create => 'Erstellen';

  @override
  String get tokenName => 'Name';

  @override
  String get tokenNameHint => 'z. B. Claude oder Kurzbefehle';

  @override
  String get tokenCreated => 'Token erstellt';

  @override
  String get tokenShownOnce =>
      'Kopiere den Token jetzt. Er wird nicht noch einmal angezeigt.';

  @override
  String get done => 'Fertig';

  @override
  String revokeToken(String name) {
    return '$name widerrufen';
  }

  @override
  String get revokeTokenTitle => 'Token widerrufen?';

  @override
  String get revokeTokenBody =>
      'Apps, die ihn benutzen, verlieren sofort den Zugriff.';

  @override
  String get revoke => 'Widerrufen';

  @override
  String get tooManyTokens => 'Höchstens 20 aktive Tokens.';

  @override
  String get connectedApps => 'Verbundene Apps';

  @override
  String get noConnectedApps => 'Noch keine App verbunden.';

  @override
  String get siriHeader => 'Siri';

  @override
  String get siriThisIphone => 'Siri (dieses iPhone)';

  @override
  String get siriOtherIphone => 'Siri (anderes iPhone)';

  @override
  String get siriWorksWithoutSetup =>
      'Siri funktioniert jetzt ohne Einrichtung. Sag: „Füge etwas zu Hummlist hinzu“.';

  @override
  String get siriShowPhrases => 'Siri-Sätze anzeigen';

  @override
  String siriOldShortcutHint(String name) {
    return 'Den alten Kurzbefehl brauchst du nicht mehr. Seinen Token „$name“ kannst du unten löschen.';
  }

  @override
  String get siriPhrasesTitle => 'Siri-Sätze';

  @override
  String get siriPhrasesEnglish => 'Auf Englisch';

  @override
  String get siriPhrasesGerman => 'Auf Deutsch';

  @override
  String siriPhrase(String phrase) {
    return '„$phrase“';
  }

  @override
  String get revokeSiriTitle => 'Siri-Zugang widerrufen?';

  @override
  String get revokeSiriBody =>
      'Siri kann auf dem iPhone dann nichts mehr hinzufügen. Beim nächsten Start von Hummlist dort wird Siri neu eingerichtet.';

  @override
  String connectedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Verbunden am $dateString';
  }

  @override
  String get disconnect => 'Trennen';

  @override
  String disconnectApp(String name) {
    return '$name trennen';
  }

  @override
  String disconnectTitle(String name) {
    return '$name trennen?';
  }

  @override
  String get disconnectBody =>
      'Die App verliert sofort den Zugriff auf deine Liste.';

  @override
  String get editStoreLayout => 'Reihenfolge bearbeiten';

  @override
  String get manageCategories => 'Kategorien verwalten';

  @override
  String get categoriesTitle => 'Kategorien';

  @override
  String get categoriesHint =>
      'In dieser Reihenfolge stehen die Kategorien unter „Ohne Laden“ und bei Läden ohne eigene Reihenfolge. Tippe auf eine Kategorie, um sie umzubenennen.';

  @override
  String get categoryName => 'Name';

  @override
  String get renameCategory => 'Kategorie umbenennen';

  @override
  String get addCategory => 'Kategorie hinzufügen';

  @override
  String deleteCategory(String name) {
    return '$name löschen';
  }

  @override
  String get moveItemsTo => 'Artikel verschieben nach';

  @override
  String dragCategory(String name) {
    return '$name verschieben';
  }

  @override
  String categoryNameTaken(String name) {
    return 'Eine Kategorie „$name“ gibt es schon.';
  }

  @override
  String get catalogSaveFailed =>
      'Die Änderung konnte nicht gespeichert werden.';

  @override
  String storeLayoutTitle(String store) {
    return '$store: Reihenfolge';
  }

  @override
  String get storeLayoutHint =>
      'Ordne die Kategorien so, wie du durch den Laden gehst.';

  @override
  String newItemsFrom(int count, String name) {
    return '$count neu von $name';
  }

  @override
  String newItems(int count) {
    return '$count neu';
  }

  @override
  String get newItem => 'Neu';

  @override
  String storeSectionLabel(String store, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artikel',
      one: '1 Artikel',
    );
    return '$store, $_temp0';
  }

  @override
  String itemsWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Artikel',
      one: 'Artikel',
    );
    return '$_temp0';
  }

  @override
  String get expandSection => 'Aufklappen';

  @override
  String get collapseSection => 'Zuklappen';

  @override
  String get moveStoreUp => 'Laden nach oben';

  @override
  String get moveStoreDown => 'Laden nach unten';

  @override
  String get moveCategoryUp => 'Kategorie nach oben';

  @override
  String get moveCategoryDown => 'Kategorie nach unten';

  @override
  String get listHint =>
      'Tippen hakt ab · Nach links wischen bearbeitet · Halten und ziehen verschiebt';

  @override
  String get listHintDismiss => 'Verstanden';

  @override
  String get reorderNeedsConnection =>
      'Die Reihenfolge lässt sich nur mit Verbindung ändern.';

  @override
  String suggestion(String label) {
    return 'Vorschlag: $label';
  }

  @override
  String get dueSuggestions => 'Brauchen wir wieder?';

  @override
  String get account => 'Konto';

  @override
  String get accountExport => 'Meine Daten exportieren';

  @override
  String get accountExportBody =>
      'Alles, was über dich gespeichert ist, als JSON-Datei.';

  @override
  String get accountDelete => 'Konto löschen';

  @override
  String get accountDeleteTitle => 'Konto löschen?';

  @override
  String get accountDeleteWhat =>
      'Dein Konto, dein Profil, deine Zugangs-Tokens und deine verbundenen Apps werden endgültig gelöscht. Das lässt sich nicht rückgängig machen.';

  @override
  String accountDeleteKept(String household, String names) {
    return 'Der Haushalt „$household“ bleibt für $names mit der ganzen Liste erhalten. Deine Einträge bleiben dort, aber ohne deinen Namen.';
  }

  @override
  String accountDeleteKeptUnnamed(String household) {
    return 'Der Haushalt „$household“ bleibt für die anderen Mitglieder mit der ganzen Liste erhalten. Deine Einträge bleiben dort, aber ohne deinen Namen.';
  }

  @override
  String namesAnd(String first, String last) {
    return '$first und $last';
  }

  @override
  String accountDeleteDeleted(String household) {
    return 'Du bist das letzte Mitglied. Deshalb wird der Haushalt „$household“ mit Liste, Verlauf, Kategorien und Geschäften gelöscht.';
  }

  @override
  String get accountDeleteNone =>
      'Du bist in keinem Haushalt, geteilte Daten gibt es nicht.';

  @override
  String get accountDeleteExportHint =>
      'Mit „Meine Daten exportieren“ unter Konto kannst du vorher eine Kopie sichern.';

  @override
  String get accountDeleteConfirmLabel => 'Zum Bestätigen LÖSCHEN eingeben';

  @override
  String get accountDeleteConfirm => 'Endgültig löschen';

  @override
  String get accountDeleteOffline =>
      'Keine Internetverbindung. Dein Konto wurde nicht gelöscht. Versuche es erneut, sobald du online bist.';

  @override
  String accountDeleteFailed(String code) {
    return 'Löschen fehlgeschlagen ($code). Dein Konto wurde nicht gelöscht.';
  }

  @override
  String get accountDeleteCanceled =>
      'Abgebrochen. Dein Konto wurde nicht gelöscht.';

  @override
  String get accountFateOffline =>
      'Keine Internetverbindung. Was mit deinem Haushalt passiert, konnte nicht geladen werden.';

  @override
  String accountFateFailed(String code) {
    return 'Was mit deinem Haushalt passiert, konnte nicht geladen werden ($code).';
  }

  @override
  String get accountDeletedNotice => 'Dein Konto wurde gelöscht.';

  @override
  String get accountDeletedApple =>
      'Falls du dich mit Apple angemeldet hattest: Entferne „Hummlist“ auf deinem iPhone unter Einstellungen › [dein Name] › Anmelden & Sicherheit › Mit Apple anmelden.';

  @override
  String get exportDone => 'Daten exportiert';

  @override
  String exportDoneAt(String path) {
    return 'Daten exportiert: $path';
  }

  @override
  String get exportOffline =>
      'Keine Internetverbindung. Deine Daten wurden nicht exportiert.';

  @override
  String exportFailed(String code) {
    return 'Export fehlgeschlagen ($code).';
  }

  @override
  String get tabList => 'Liste';

  @override
  String get tabMore => 'Mehr';

  @override
  String get addSheetHint =>
      'Antippen fügt hinzu · ↵ nimmt den ersten Vorschlag';

  @override
  String get storeAuto => 'Laden: automatisch';

  @override
  String get typeToSuggest => 'Tippe, um Vorschläge zu sehen';

  @override
  String get suggestionTyped => 'Wie getippt';

  @override
  String get suggestionHistory => 'Schon mal gekauft';

  @override
  String get suggestionPack => 'Andere Packung';

  @override
  String get suggestionVariant => 'Andere Sorte';

  @override
  String get suggestionSize => 'Andere Größe';

  @override
  String get suggestionBrand => 'Andere Marke';

  @override
  String get suggestionCatalog => 'Aus dem Katalog';

  @override
  String get suggestionDue => 'Wieder fällig';

  @override
  String addedTo(String name, String store) {
    return 'Hinzugefügt: $name → $store';
  }

  @override
  String addedItem(String name) {
    return 'Hinzugefügt: $name';
  }

  @override
  String get clearInput => 'Eingabe leeren';

  @override
  String listItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artikel',
      one: '1 Artikel',
    );
    return '$_temp0';
  }

  @override
  String get household => 'Haushalt';

  @override
  String get storesTitle => 'Läden';

  @override
  String get storesRowHint => 'Reihenfolge und Laufweg';

  @override
  String get storesHint =>
      'Halten und ziehen ändert die Reihenfolge der Läden in der Liste. Ein Laden öffnet seinen Laufweg.';

  @override
  String dragStore(String store) {
    return '$store verschieben';
  }

  @override
  String get storeNew => 'Neuer Laden';

  @override
  String get storeNewLabel => 'Neuen Laden anlegen';

  @override
  String get storeNameHint => 'Name des Ladens';

  @override
  String get storeCreateConfirm => 'Laden anlegen';

  @override
  String storeAddedAndSelected(String store) {
    return '$store angelegt und ausgewählt';
  }

  @override
  String storeAdded(String store) {
    return '$store angelegt';
  }

  @override
  String get storeSearch => 'Läden durchsuchen';

  @override
  String storeRename(String store) {
    return '$store umbenennen';
  }

  @override
  String storeDelete(String store) {
    return '$store löschen';
  }

  @override
  String storeDeleteTitle(String store) {
    return '$store löschen?';
  }

  @override
  String storeNameTaken(String name) {
    return 'Einen Laden „$name“ gibt es schon.';
  }

  @override
  String get storesNeedConnection =>
      'Läden lassen sich nur mit Verbindung anlegen, umbenennen oder löschen.';

  @override
  String get storesEmpty =>
      'Noch keine Läden. Leg einen an, dann sortiert die Liste deine Artikel nach seinem Laufweg.';

  @override
  String storeMenu(String store) {
    return 'Optionen für $store';
  }

  @override
  String get storeRenameAction => 'Umbenennen';

  @override
  String storeDeleteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offene Artikel kommen zu „Ohne Laden“.',
      one: '1 offener Artikel kommt zu „Ohne Laden“.',
      zero: 'In diesem Laden sind keine offenen Artikel.',
    );
    return '$_temp0 Sein Laufweg geht mit.';
  }

  @override
  String get accessRowHint => 'MCP-Server, Zugangsschlüssel, verbundene Apps';

  @override
  String get accountRowHint => 'Daten exportieren, Konto löschen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsRowHint => 'Darstellung und Sprache';

  @override
  String get appearance => 'Darstellung';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get language => 'Sprache';

  @override
  String get languageSystem => 'Wie Gerät';

  @override
  String languageSystemNow(String language) {
    return 'Gerade $language';
  }

  @override
  String languageSystemPicked(String language) {
    return 'Wie Gerät ($language)';
  }

  @override
  String get legal => 'Rechtliches';

  @override
  String get imprint => 'Impressum';

  @override
  String get privacy => 'Datenschutz';

  @override
  String get licenses => 'Lizenzen';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get categoryProduce => 'Obst & Gemüse';

  @override
  String get categoryBakery => 'Brot & Backwaren';

  @override
  String get categoryChilled => 'Kühlregal';

  @override
  String get categoryMeat => 'Fleisch/Wurst/Fisch';

  @override
  String get categoryPantry => 'Vorrat & Konserven';

  @override
  String get categorySweets => 'Süßes & Snacks';

  @override
  String get categoryDrinks => 'Getränke';

  @override
  String get categoryFrozen => 'Tiefkühl';

  @override
  String get categoryHousehold => 'Haushalt';

  @override
  String get categoryDrugstore => '👶 Drogerie';

  @override
  String get categoryOther => 'Sonstiges';

  @override
  String get analyticsConsentTitle => 'Darf Hummlist Nutzungsdaten erfassen?';

  @override
  String get analyticsConsentBody =>
      'Hummlist (Anbieter: Peter Trost) möchte verstehen, welche Funktionen genutzt werden, Fehler finden, messen, ob sich Hummlist trägt, und neue Funktionen schrittweise freischalten. Dafür speichert Hummlist eine zufällige Kennung auf diesem Gerät und sendet damit pseudonyme Nutzungsdaten, Fehlerberichte, die Kennung deines Haushalts und technische Angaben zu Gerät oder Browser an unseren Dienstleister PostHog (Server in der EU). Listeninhalte, Namen und E-Mail-Adressen werden nie gesendet. Du kannst jederzeit unter Mehr → Nutzungsdaten widerrufen. Mehr in der';

  @override
  String get analyticsConsentPrivacyLink => 'Datenschutzerklärung';

  @override
  String get analyticsAccept => 'Erlauben';

  @override
  String get analyticsDecline => 'Nicht erlauben';

  @override
  String get analyticsSection => 'Nutzungsdaten';

  @override
  String get analyticsToggle => 'Nutzungsdaten und Fehlerberichte senden';

  @override
  String get analyticsToggleHint =>
      'Pseudonym an PostHog (Server in der EU), ohne Listeninhalte. Gilt für dieses Gerät. Ausschalten löscht die Kennung auf diesem Gerät.';

  @override
  String get internalInstall => 'Interne Installation';

  @override
  String get internalInstallOn => 'Diese Installation zählt jetzt als intern.';

  @override
  String get internalInstallOff =>
      'Diese Installation zählt nicht mehr als intern.';

  @override
  String get sendTestError => 'Testfehler senden';

  @override
  String get feedbackSection => 'Feedback';

  @override
  String get feedbackRow => 'Feedback senden';

  @override
  String get feedbackRowHint => 'Fehler, Ideen und Fragen an Peter';

  @override
  String get helpRow => 'Hilfe & Kontakt';

  @override
  String get helpRowHint => 'Fragen, Anleitungen und unsere E-Mail-Adresse';

  @override
  String get feedbackMessage => 'Deine Nachricht';

  @override
  String get feedbackMessageHint => 'Was ist dir aufgefallen?';

  @override
  String get feedbackCategoryBug => 'Bug';

  @override
  String get feedbackCategoryIdea => 'Idee';

  @override
  String get feedbackCategoryOther => 'Sonstiges';

  @override
  String get feedbackCategories => 'Art (optional)';

  @override
  String get feedbackContact => 'Peter darf mich dazu kontaktieren';

  @override
  String get feedbackAttached =>
      'App-Version, Gerät, Sprache und aktueller Bildschirm. Keine Listeneinträge.';

  @override
  String get feedbackAttachedTitle => 'Wird mitgeschickt:';

  @override
  String get feedbackSend => 'Senden';

  @override
  String get feedbackRetry => 'Erneut senden';

  @override
  String get feedbackSending => 'Wird gesendet …';

  @override
  String get feedbackThanks => 'Danke!';

  @override
  String get feedbackFailed =>
      'Nicht gesendet. Prüfe die Verbindung und versuch es noch einmal.';

  @override
  String feedbackTooLong(int max) {
    return 'Höchstens $max Zeichen';
  }

  @override
  String feedbackCounter(int count, int max) {
    return '$count / $max';
  }

  @override
  String get feedbackClose => 'Schließen';

  @override
  String get onboardingCreateHint =>
      'Eine neue Liste, zu der du danach deinen Partner einlädst.';

  @override
  String get onboardingJoin => 'Einladung annehmen';

  @override
  String get onboardingJoinHint =>
      'Du hast einen Link oder einen Code bekommen.';

  @override
  String get householdNameInvalid =>
      'Gib einen Namen mit 1 bis 80 Zeichen ein.';

  @override
  String get storesChoice => 'Läden';

  @override
  String get defaultStores => 'Deutsche Standard-Läden hinzufügen';

  @override
  String get defaultStoresHint =>
      'dm, Lidl und Edeka, jeweils in ihrer Gangfolge';

  @override
  String get skipStores => 'Überspringen';

  @override
  String get skipStoresHint =>
      'Ohne Läden starten. Du kannst sie später unter Mehr anlegen.';

  @override
  String get householdOffline =>
      'Keine Internetverbindung. Versuche es erneut, sobald du online bist.';

  @override
  String get householdArchiveDisabled =>
      'Archivieren ist gerade nicht möglich. Dein Haushalt bleibt, wie er ist.';

  @override
  String get tooManyAttempts => 'Zu viele Versuche. Bitte später noch einmal.';

  @override
  String get alreadyInHousehold => 'Du bist schon in einem Haushalt';

  @override
  String switchHouseholdAlone(String household) {
    return 'Du bist das einzige Mitglied von „$household“. Trittst du bei, wird „$household“ mit seiner Liste gelöscht.';
  }

  @override
  String switchHouseholdShared(String household) {
    return 'Trittst du bei, verlässt du „$household“. Die anderen Mitglieder behalten die Liste.';
  }

  @override
  String get inviteCheck => 'Weiter';

  @override
  String get invitePreview => 'Einladung in den Haushalt';

  @override
  String get invitePartnerBody =>
      'Teile den Link oder den Code mit der Person, mit der du einkaufst. Die Einladung gilt 7 Tage und für eine Person.';

  @override
  String get later => 'Später';

  @override
  String get toTheList => 'Weiter zur Liste';

  @override
  String inviteShareText(String link, String code) {
    return 'Komm in unseren Hummlist-Haushalt: $link · Code: $code';
  }

  @override
  String inviteShareTextCodeOnly(String code) {
    return 'Komm in unseren Hummlist-Haushalt. Code: $code';
  }

  @override
  String get share => 'Teilen';

  @override
  String get copyLink => 'Link kopieren';

  @override
  String get copyCode => 'Code kopieren';

  @override
  String get linkCopied => 'Link kopiert';

  @override
  String get codeCopied => 'Code kopiert';

  @override
  String get invitesTitle => 'Einladungen';

  @override
  String get invitesOpen => 'Offene Einladungen';

  @override
  String get invitesEmpty => 'Keine offenen Einladungen.';

  @override
  String get newInvite => 'Neue Einladung';

  @override
  String inviteValidUntil(DateTime date, DateTime time) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);
    final intl.DateFormat timeDateFormat = intl.DateFormat.Hm(localeName);
    final String timeString = timeDateFormat.format(time);

    return 'gültig bis $dateString, $timeString Uhr';
  }

  @override
  String get inviteRevoke => 'Widerrufen';

  @override
  String inviteRevokeLabel(String code) {
    return 'Einladung $code widerrufen';
  }

  @override
  String get inviteRevoked =>
      'Einladung widerrufen. Link und Code gelten nicht mehr.';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get lifetimeTitle => 'Hummlist Lifetime';

  @override
  String get lifetimeRowHint => 'Hummlist unterstützen';

  @override
  String get lifetimeBody =>
      'Ein Kauf, für euren ganzen Haushalt: Hummlist Lifetime unterstützt die Entwicklung von Hummlist.';

  @override
  String get lifetimeBuy => 'Weiter zum Kauf';

  @override
  String get lifetimePriceInStore =>
      'Den Preis zeigen dir der App Store oder Google Play, bevor du kaufst.';

  @override
  String get lifetimeRestore => 'Kauf wiederherstellen';

  @override
  String get lifetimeUnlocked => 'Freigeschaltet';

  @override
  String get lifetimeUnlockedBody =>
      'Hummlist Lifetime ist für euren ganzen Haushalt freigeschaltet. Danke!';

  @override
  String get lifetimePending => 'Wartet auf Bestätigung';

  @override
  String get lifetimePendingBody =>
      'Hummlist Lifetime wird freigeschaltet, sobald der Kauf bestätigt ist. Das kann etwas dauern.';

  @override
  String get lifetimeUnlocking => 'Wird freigeschaltet …';

  @override
  String get lifetimeUnlockDelayed =>
      'Dein Kauf ist angekommen, die Freischaltung dauert nur länger als sonst. Sie erscheint hier von selbst; bitte nicht noch einmal kaufen.';

  @override
  String get lifetimeBoughtTwice =>
      'Euer Haushalt hat Hummlist Lifetime mehr als einmal gekauft. Einen der Käufe kannst du dir erstatten lassen.';

  @override
  String get lifetimeCanceled => 'Kauf abgebrochen.';

  @override
  String get lifetimeComingSoon => 'Hummlist Lifetime ist bald verfügbar.';

  @override
  String get lifetimeStoreOffline =>
      'Der Store ist gerade nicht erreichbar. Prüfe die Verbindung.';

  @override
  String get lifetimeUsedElsewhere =>
      'Dieser Kauf gehört zu einem anderen, früheren Haushalt und bleibt dort. Hier schaltet er nichts frei.';

  @override
  String get lifetimeNothingRestored => 'Kein früherer Kauf gefunden.';

  @override
  String lifetimeStoreFailed(String code) {
    return 'Der Kauf hat nicht geklappt ($code).';
  }

  @override
  String get lifetimeWeb =>
      'Kaufen kannst du Hummlist Lifetime in der iPhone- oder Android-App. Danach ist es auch hier für deinen ganzen Haushalt freigeschaltet.';

  @override
  String get lifetimeChecking =>
      'Wir prüfen, ob dein Haushalt Hummlist Lifetime schon hat …';

  @override
  String get lifetimeRefundLink =>
      'Doppelt gekauft? So bekommst du dein Geld zurück';

  @override
  String get refundHelpTitle => 'Kauf zurückfordern';

  @override
  String get refundHelpBody =>
      'Hummlist Lifetime gehört immer zu dem Haushalt, in dem es gekauft wurde. Käufe im App Store erstattet nur Apple. Bei Google Play beantragst du die Erstattung in den ersten 48 Stunden bei Google; danach schreib uns an support@hummlist.com, wir prüfen jede Anfrage einzeln. Deine gesetzlichen Rechte bleiben unberührt.';

  @override
  String get refundHelpApple =>
      'iPhone: Öffne reportaproblem.apple.com, melde dich mit deinem Apple Account an, wähle „Rückerstattung anfordern“ und dann Hummlist Lifetime.';

  @override
  String get refundHelpGoogle =>
      'Android, in den ersten 48 Stunden: Öffne Google Play, tippe auf dein Profilbild, dann „Zahlungen und Abos“, „Budget und Bestellverlauf“, wähle Hummlist Lifetime und „Problem melden“. Danach schreib uns mit der Bestellnummer (beginnt mit „GPA.“) oder der E-Mail-Adresse deines Google-Kontos.';

  @override
  String get refundHelpReason =>
      'Als Grund kannst du schreiben: „Mein Haushalt war schon freigeschaltet.“';

  @override
  String get refundHelpAppleLink => 'Bei Apple anfragen';

  @override
  String get refundHelpGoogleLink => 'Bei Google anfragen';

  @override
  String get refundHelpFaqLink => 'Mehr in den häufigen Fragen';

  @override
  String get joinTargetUnlocked =>
      'Dieser Haushalt hat Hummlist Lifetime. Du musst nichts kaufen.';

  @override
  String get joinRefundLink =>
      'Du hast Hummlist Lifetime vor Kurzem gekauft? So forderst du den Kauf zurück';

  @override
  String joinLifetimeEnds(String household) {
    return '„$household“ hat Hummlist Lifetime. Du bist das letzte Mitglied: Trittst du bei, wird der Haushalt gelöscht. Hummlist Lifetime endet mit ihm, denn ein Kauf gehört zu seinem Haushalt und zieht nicht mit um.';
  }

  @override
  String get joinAnyway => 'Trotzdem beitreten';

  @override
  String get joinLifetimeRefundLink =>
      'Erstattung bei Apple oder Google anfragen';

  @override
  String joinArchiveOffer(String household) {
    return '„$household“ hat Hummlist Lifetime. Du bist das letzte Mitglied. Archiviere den Haushalt, statt ihn zu löschen: Liste und Hummlist Lifetime bleiben erhalten, und du kannst ihn später unter „Mehr“ wieder aktivieren. Aktivierst du ihn nicht innerhalb von 24 Monaten wieder, wird er gelöscht.';
  }

  @override
  String get joinArchive => 'Archivieren und beitreten';

  @override
  String get joinDelete => 'Löschen und beitreten';

  @override
  String joinDeleteTitle(String household) {
    return '„$household“ löschen?';
  }

  @override
  String get archivedTitle => 'Archivierte Haushalte';

  @override
  String get archivedEmpty => 'Du hast keinen Haushalt archiviert.';

  @override
  String get archivedUnlocked => 'Mit Hummlist Lifetime';

  @override
  String archivedDeletesOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Wird am $dateString gelöscht';
  }

  @override
  String get archivedRestore => 'Wieder aktivieren';

  @override
  String archivedRestoreTitle(String household) {
    return '„$household“ wieder aktivieren?';
  }

  @override
  String archivedRestoreBody(String household) {
    return 'Du wechselst in „$household“ und bist dort wieder Mitglied.';
  }

  @override
  String archivedRestoreArchivesCurrent(String household) {
    return 'Du bist das letzte Mitglied von „$household“. Weil er Hummlist Lifetime hat, wird er archiviert, nicht gelöscht.';
  }

  @override
  String get premiumTitle => 'Hummlist Premium';

  @override
  String get premiumRowHint => 'Siri, Alexa und KI-Assistenten';

  @override
  String get premiumBody =>
      'Hummlist Premium schaltet für euren ganzen Haushalt die Verbindungen frei: Siri, Alexa und KI-Assistenten (MCP). Später kommen Google Assistant und die Apple Watch dazu.';

  @override
  String get premiumUnlockedBody =>
      'Hummlist Premium ist für euren ganzen Haushalt freigeschaltet. Danke!';

  @override
  String premiumStatusRenews(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Hummlist Premium aktiv (jährlich, verlängert sich am $dateString)';
  }

  @override
  String premiumStatusEnds(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Hummlist Premium aktiv (jährlich, läuft am $dateString aus)';
  }

  @override
  String get premiumStatusLifetime => 'Hummlist Premium Lifetime';

  @override
  String get premiumStatusGranted => 'Hummlist Premium geschenkt';

  @override
  String premiumStatusGrantedUntil(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Hummlist Premium geschenkt bis $dateString';
  }

  @override
  String get premiumChecking =>
      'Wir prüfen, ob euer Haushalt Hummlist Premium schon hat …';

  @override
  String get premiumYearlyTitle => 'Jährlich';

  @override
  String premiumYearlyPrice(String price) {
    return '$price / Jahr';
  }

  @override
  String get premiumLifetimeTitle => 'Lifetime';

  @override
  String premiumLifetimePrice(String price) {
    return '$price einmalig';
  }

  @override
  String get premiumLifetimeValue =>
      'Einmal zahlen, für immer: so viel wie drei Jahre.';

  @override
  String get premiumVat => 'inkl. MwSt.';

  @override
  String get premiumYearlyTerms =>
      'Hummlist Premium jährlich, Laufzeit 1 Jahr. Das Abo verlängert sich automatisch um ein Jahr, wenn du es nicht mindestens 24 Stunden vor Ende der Laufzeit kündigst. Bezahlt wird über dein Apple- bzw. Google-Konto, bei der Bestätigung des Kaufs und bei jeder Verlängerung. Verwalten und kündigen kannst du das Abo in den Abo-Einstellungen des App Store bzw. von Google Play.';

  @override
  String get premiumBuyYearly => 'Jährlich abschließen';

  @override
  String get premiumBuyLifetime => 'Lifetime kaufen';

  @override
  String get premiumUnavailable =>
      'Hummlist Premium ist gerade nicht verfügbar.';

  @override
  String get premiumComingSoon => 'Hummlist Premium ist bald verfügbar.';

  @override
  String get premiumTermsLink => 'Nutzungsbedingungen (EULA)';

  @override
  String get premiumPrivacyLink => 'Datenschutzerklärung';

  @override
  String get premiumUsedElsewhereYearly =>
      'Dein Apple- bzw. Google-Konto zahlt schon ein Jahresabo für einen anderen Haushalt. Jemand anderes aus diesem Haushalt kann Hummlist Premium abschließen.';

  @override
  String get premiumTwoYearly =>
      'Euer Haushalt hat zwei Jahresabos. Kündigen kann jedes nur, wer es abgeschlossen hat.';

  @override
  String get premiumWeb =>
      'Hummlist Premium kaufst du in der iPhone- oder Android-App. Danach ist es auch hier für deinen ganzen Haushalt freigeschaltet.';

  @override
  String get premiumRefundYearly =>
      'Für das Jahresabo gilt dasselbe. Eine Kündigung beendet nur die Verlängerung; das laufende Jahr wird nicht automatisch erstattet.';

  @override
  String get premiumManage => 'Abo verwalten oder kündigen';

  @override
  String get premiumManageWeb =>
      'Dein Jahresabo verwaltest du im App Store oder bei Google Play.';

  @override
  String get premiumManageApple => 'App Store';

  @override
  String get premiumManageGoogle => 'Google Play';

  @override
  String premiumBillingIssue(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Apple bzw. Google konnten dein Jahresabo nicht abbuchen. Premium läuft noch bis $dateString. Prüfe deine Zahlungsmethode im Store.';
  }

  @override
  String get premiumLifetimeWhileYearly =>
      'Euer Haushalt hat schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird weiter abgerechnet, bis es gekündigt wird; das restliche Abojahr wird nicht automatisch erstattet. Kündigen kann nur, wer das Abo abgeschlossen hat, unter [Abos verwalten]. Hummlist kann das Abo nicht kündigen.';

  @override
  String get premiumLifetimeWhileYearlySubscriber =>
      'Euer Haushalt hat schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird weiter abgerechnet, bis es gekündigt wird; das restliche Abojahr wird nicht automatisch erstattet. Du kannst es unter [Abo verwalten] kündigen. Hummlist kann das Abo nicht kündigen.';

  @override
  String get premiumBuyAnyway => 'Trotzdem kaufen';

  @override
  String get premiumBillingContinues =>
      'Dein Jahresabo für Hummlist Premium läuft weiter und wird über dein Apple- bzw. Google-Konto abgerechnet, bis du es kündigst. Löschen oder Verlassen kündigt es nicht.';

  @override
  String get premiumBillingContinuesOther =>
      'Ein Jahresabo für diesen Haushalt läuft weiter, bis es gekündigt wird.';

  @override
  String get premiumManageSubscription => 'Abo verwalten';

  @override
  String get premiumContinueAnyway => 'Trotzdem fortfahren';

  @override
  String get integrationPremiumTitle => 'Teil von Hummlist Premium';

  @override
  String get integrationPremiumBody =>
      'Siri, Alexa und KI-Assistenten gehören zu Hummlist Premium. Eure Verbindungen bleiben gespeichert und funktionieren wieder, sobald euer Haushalt Hummlist Premium hat.';

  @override
  String get integrationPremiumSiri => 'Siri auf dem iPhone';

  @override
  String get integrationPremiumAlexa => 'Alexa-Skill';

  @override
  String get integrationPremiumAi =>
      'KI-Assistenten wie ChatGPT oder Claude (MCP)';

  @override
  String get integrationPremiumLater =>
      'Später: Google Assistant und Apple Watch';

  @override
  String get integrationPremiumBuy => 'Hummlist Premium freischalten';

  @override
  String get integrationPremiumSoon => 'Bald verfügbar.';

  @override
  String get integrationPaused => 'Pausiert: braucht Hummlist Premium';
}
