// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Snacklist';

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
  String get dictationTooMany =>
      'Mehr als dreißig auf einmal gehen nicht; sag den Rest bitte noch einmal.';

  @override
  String get undo => 'Rückgängig';

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
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get syncOffline => 'Offline';

  @override
  String get syncOfflineLine =>
      'Änderungen werden synchronisiert, sobald du wieder online bist.';

  @override
  String get syncOfflineLabel =>
      'Offline: Änderungen werden synchronisiert, sobald du wieder online bist.';

  @override
  String get syncFailing => 'Sync gestört';

  @override
  String get syncFailingWord => 'Gestört';

  @override
  String get syncFailingLine =>
      'Deine Änderungen sind auf dem Gerät gespeichert.';

  @override
  String get syncFailingLabel =>
      'Sync gestört: Deine Änderungen sind auf dem Gerät gespeichert.';

  @override
  String get syncRetrying => 'Wird erneut versucht';

  @override
  String get syncDetails => 'Details anzeigen';

  @override
  String get syncSynced => 'Synchronisiert';

  @override
  String get syncStillFailing => 'Immer noch gestört';

  @override
  String syncFailed(String name) {
    return 'Änderung abgelehnt: $name';
  }

  @override
  String get inviteMember => 'Partner einladen';

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
  String get continueWithEmail => 'Weiter mit E-Mail';

  @override
  String get orWithEmail => 'oder mit E-Mail';

  @override
  String get onboardingTitle => 'Willkommen bei Snacklist';

  @override
  String get onboardingBody =>
      'Snacklist teilt eine Einkaufsliste mit allen in deinem Haushalt. Erstelle einen neuen Haushalt oder nimm eine Einladung an.';

  @override
  String get householdName => 'Name des Haushalts';

  @override
  String get householdNameDefault => 'Unser Haushalt';

  @override
  String get householdNameHintFurther => 'z. B. Eltern, WG, Verein';

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
  String get consentConnectedTitle => 'Verbunden';

  @override
  String get consentDeclinedTitle => 'Nicht verbunden';

  @override
  String consentDone(String client) {
    return 'Fertig, du kannst zu $client zurückkehren.';
  }

  @override
  String get consentDoneNoClient =>
      'Fertig, du kannst zu deiner App zurückkehren.';

  @override
  String consentDeclined(String client) {
    return 'Abgelehnt, du kannst zu $client zurückkehren.';
  }

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
  String get siriSayHint =>
      'Sag zum Beispiel: „Hey Siri, etwas auf Snacklist setzen“.';

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
      'Siri kann auf dem iPhone dann nichts mehr hinzufügen. Beim nächsten Start von Snacklist dort wird Siri neu eingerichtet.';

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
  String categoryPosition(int position, int count) {
    return '$position von $count';
  }

  @override
  String categoryNameTaken(String name) {
    return 'Eine Kategorie „$name“ gibt es schon.';
  }

  @override
  String get catalogSaveFailed =>
      'Die Änderung konnte nicht gespeichert werden.';

  @override
  String get storeLayoutHint =>
      'Ordne die Kategorien so, wie du durch den Laden gehst. Tippe auf eine Kategorie, um sie umzubenennen.';

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
  String get listHint => 'Tippen hakt ab · Halten bearbeitet';

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
  String accountDeletePremium(String household) {
    return '„$household“ hat Snacklist Premium. Es gehört zum Haushalt und endet mit ihm. Archivieren geht hier nicht, denn ein archivierter Haushalt wird mit deinem Konto gelöscht. Soll der Haushalt mit Premium bleiben, lade vorher jemanden ein und lösche dein Konto erst, wenn die Person beigetreten ist.';
  }

  @override
  String accountDeletePremiumLastMember(String household) {
    return '„$household“ hat Snacklist Premium. Das gehört zum Haushalt. Löschst du dein Konto, endet es. Soll es bleiben? Dann lad erst jemand ein. Warte, bis die Person beigetreten ist. Lösch dann dein Konto.';
  }

  @override
  String accountDeleteArchived(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Deine archivierten Haushalte $names werden mit deinem Konto gelöscht.',
      one: 'Dein archivierter Haushalt $names wird mit deinem Konto gelöscht.',
    );
    return '$_temp0';
  }

  @override
  String accountDeleteArchivedPremium(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Deine archivierten Haushalte $names werden mit deinem Konto gelöscht, und mit ihnen ihr Snacklist Premium.',
      one:
          'Dein archivierter Haushalt $names wird mit deinem Konto gelöscht, und mit ihm sein Snacklist Premium.',
    );
    return '$_temp0';
  }

  @override
  String quotedName(String name) {
    return '„$name“';
  }

  @override
  String get accountDeletePremiumAck =>
      'Ich weiß: Premium endet. Ich bekomme mein Geld nicht von selbst zurück.';

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
      'Falls du dich mit Apple angemeldet hattest: Entferne „Snacklist“ auf deinem iPhone unter Einstellungen › [dein Name] › Anmelden & Sicherheit › Mit Apple anmelden.';

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
  String get chipStoreShort => 'Laden';

  @override
  String get chipCategoryShort => 'Kategorie';

  @override
  String storeAutoValue(String name) {
    return 'Laden: automatisch, $name';
  }

  @override
  String categoryAutoValue(String name) {
    return 'Kategorie: automatisch, $name';
  }

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
  String get suggestionRecent => 'Zuletzt verwendet';

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
  String get listEdit => 'Anpassen';

  @override
  String get noStoreRowHint => 'Kategorien für Artikel ohne Laden';

  @override
  String get storeAdd => 'Laden hinzufügen';

  @override
  String get deleteCategoryEverywhere => 'Sie verschwindet aus allen Läden.';

  @override
  String get storesHint =>
      'Ziehe die Läden in die Reihenfolge, in der sie auf der Liste stehen. Tippe auf einen Laden, um ihn umzubenennen und seine Kategorien zu ordnen.';

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
  String get settingsTitle => 'Einstellungen';

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
  String get imprint => 'Impressum';

  @override
  String get privacy => 'Datenschutz';

  @override
  String get licenses => 'Lizenzen';

  @override
  String get privacyPolicy => 'Datenschutzerklärung';

  @override
  String get updatePatchTitle => 'Update bereit';

  @override
  String get updatePatchBody =>
      'Snacklist hat Verbesserungen geladen. Starte die App neu, um sie zu nutzen.';

  @override
  String get updatePatchAction => 'Neu starten';

  @override
  String get updateStoreTitle => 'Neue Version da';

  @override
  String updateStoreBody(String version) {
    return 'Version $version ist im Store. Aktualisiere, um alles Neue zu bekommen.';
  }

  @override
  String get updateStoreAction => 'Aktualisieren';

  @override
  String get updateLater => 'Später';

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
  String get categoryPaint => 'Farben & Lacke';

  @override
  String get categoryPlumbing => 'Sanitär';

  @override
  String get categoryElectrical => 'Elektro & Leuchtmittel';

  @override
  String get categoryTools => 'Werkzeug';

  @override
  String get categoryFasteners => 'Schrauben & Befestigung';

  @override
  String get categoryBuilding => 'Holz & Baustoffe';

  @override
  String get categoryGarden => 'Garten & Pflanzen';

  @override
  String get categoryOther => 'Sonstiges';

  @override
  String get analyticsConsentTitle => 'Darf Snacklist Nutzungsdaten erfassen?';

  @override
  String get analyticsConsentBody =>
      'Snacklist (Anbieter: Peter Trost) möchte verstehen, welche Funktionen genutzt werden, Fehler finden, messen, ob sich Snacklist trägt, und neue Funktionen schrittweise freischalten. Dafür speichert Snacklist eine zufällige Kennung auf diesem Gerät und sendet damit pseudonyme Nutzungsdaten (etwa zu Einträgen, Haushalten und der Einrichtung, welche Tipps du siehst und wie du Siri nutzt), Fehlerberichte, die Kennung deines Haushalts und technische Angaben zu Gerät oder Browser an unseren Dienstleister PostHog (Server in der EU). Listeninhalte, Namen und E-Mail-Adressen werden nie gesendet. Du kannst jederzeit unter Mehr → Nutzungsdaten widerrufen. Mehr in der';

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
  String copyInstallId(String id) {
    return 'Installations-ID kopieren: $id';
  }

  @override
  String get sendTestError => 'Testfehler senden';

  @override
  String get feedbackRow => 'Feedback senden';

  @override
  String get rateApp => 'Snacklist bewerten';

  @override
  String get helpRow => 'Hilfe & Kontakt';

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
  String get onboardingStoresHint =>
      'Wähl die Läden, in denen ihr einkauft. In dieser Reihenfolge stehen sie in der Liste.';

  @override
  String get storeAddOwn => 'Eigenen Laden hinzufügen';

  @override
  String get storeHardware => 'Baumarkt';

  @override
  String get storesDisclaimer =>
      'Ladennamen wie dm, Lidl oder EDEKA verwenden wir nur, damit du erkennst, für welchen Laden eine Liste gedacht ist. Die Namen und Marken gehören den jeweiligen Unternehmen. Snacklist ist ein unabhängiges Angebot und steht in keiner Verbindung zu diesen Unternehmen. Sie unterstützen oder empfehlen Snacklist nicht.';

  @override
  String get skipStores => 'Überspringen';

  @override
  String get skipStoresHint =>
      'Ohne Läden starten. Du kannst sie später unter Liste → Anpassen anlegen.';

  @override
  String get householdOffline =>
      'Keine Internetverbindung. Versuche es erneut, sobald du online bist.';

  @override
  String get householdArchiveDisabled =>
      'Archivieren ist gerade nicht möglich. Dein Haushalt bleibt, wie er ist.';

  @override
  String get tooManyAttempts => 'Zu viele Versuche. Bitte später noch einmal.';

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
  String get startTagline => 'Eure Einkaufsliste. Live auf jedem Handy.';

  @override
  String get startWelcome =>
      'Willkommen! In zwei Minuten steht eure gemeinsame Liste, mit allem, was gerade fehlt.';

  @override
  String get startGo => 'Los geht\'s';

  @override
  String get startLogIn => 'Schon ein Konto? Anmelden';

  @override
  String get loginNew => 'Neu bei Snacklist? Los geht\'s';

  @override
  String onboardingProgress(int step, int count) {
    return 'Schritt $step von $count';
  }

  @override
  String get onboardingBack => 'Zurück';

  @override
  String get onboardingNext => 'Weiter';

  @override
  String get onboardingSkip => 'Überspringen';

  @override
  String get onboardingExit => 'Einrichtung verlassen';

  @override
  String get onboardingExitTitle => 'Einrichtung verlassen?';

  @override
  String get onboardingExitBody =>
      'Was du bisher eingegeben hast, bleibt auf diesem Gerät gespeichert.';

  @override
  String get onboardingExitLogIn => 'Stattdessen anmelden';

  @override
  String get onboardingExitDiscard => 'Fortschritt verwerfen';

  @override
  String get onboardingExitStay => 'Weiter einrichten';

  @override
  String get onboardingDiscardTitle => 'Fortschritt verwerfen?';

  @override
  String onboardingDiscardBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ' und $count Artikel',
      one: ' und 1 Artikel',
      zero: '',
    );
    return 'Deine Antworten$_temp0 werden von diesem Gerät gelöscht.';
  }

  @override
  String get onboardingDiscard => 'Verwerfen';

  @override
  String get whoTitle => 'Mit wem kaufst du ein?';

  @override
  String get whoBody =>
      'Wähl alles, was passt. Danach richten sich Name, Einladung und deine ersten Tipps.';

  @override
  String get kindPartner => 'Partner·in';

  @override
  String get kindFamily => 'Familie';

  @override
  String get kindFlat => 'WG';

  @override
  String get kindClub => 'Verein oder Team';

  @override
  String get kindSolo => 'Nur ich';

  @override
  String get kindOther => 'Andere';

  @override
  String get whoOtherLabel => 'Mit wem noch?';

  @override
  String get whoOtherHint => 'z. B. Nachbarn';

  @override
  String whoSeveral(String first) {
    return 'Wir starten mit „$first“. Die anderen merken wir uns für später.';
  }

  @override
  String get nameTitle => 'Wie soll euer Haushalt heißen?';

  @override
  String get nameBody =>
      'Den Namen sehen alle, die du einlädst. Du kannst ihn später ändern.';

  @override
  String get householdNameFamily => 'Unsere Familie';

  @override
  String get householdNameFlat => 'Unsere WG';

  @override
  String get householdNameClub => 'Unser Verein';

  @override
  String get householdNameSolo => 'Meine Liste';

  @override
  String get storesStepTitle => 'Wo kauft ihr ein?';

  @override
  String get needTitle => 'Was fehlt gerade?';

  @override
  String get needBody =>
      'Tipp an, was auf die Liste soll, oder schreib es unten hin.';

  @override
  String get needStaples =>
      'Milch,Brot,Eier,Butter,Käse,Bananen,Äpfel,Tomaten,Nudeln,Kaffee,Joghurt,Klopapier';

  @override
  String get needFieldLabel => 'Noch etwas?';

  @override
  String get needFieldHint => 'z. B. 2 Gurken';

  @override
  String get needAdd => 'Hinzufügen';

  @override
  String needListTitle(int count) {
    return 'Auf deiner Liste ($count)';
  }

  @override
  String needRemove(String name) {
    return '$name entfernen';
  }

  @override
  String needNext(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Weiter mit $count Artikeln',
      one: 'Weiter mit 1 Artikel',
      zero: 'Weiter',
    );
    return '$_temp0';
  }

  @override
  String get accountStepTitle => 'Konto erstellen';

  @override
  String get accountStepBody =>
      'Fast geschafft. Mit einem Konto speichern wir eure Liste, und du kannst jemanden einladen.';

  @override
  String get setupBusy => 'Wir richten euren Haushalt ein …';

  @override
  String get inviteStepPartner => 'Partner·in einladen';

  @override
  String get inviteStepFamily => 'Familie einladen';

  @override
  String get inviteStepFlat => 'Mitbewohner einladen';

  @override
  String get inviteStepClub => 'Mitglieder einladen';

  @override
  String get inviteStepOther => 'Jemanden einladen';

  @override
  String get inviteStepBody =>
      'Teile den Link mit der Person, mit der du einkaufst. Jede Einladung gilt 7 Tage und für eine Person.';

  @override
  String get inviteStepBodyClub =>
      'Schick jedem Mitglied einen eigenen Link. Alle sehen dieselbe Liste.';

  @override
  String inviteStepWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artikel warten schon auf der Liste.',
      one: '1 Artikel wartet schon auf der Liste.',
    );
    return '$_temp0';
  }

  @override
  String get inviteAnother => 'Weitere Einladung';

  @override
  String get inviteJoined => 'Beigetreten';

  @override
  String inviteJoinedName(String name) {
    return '$name ist beigetreten';
  }

  @override
  String inviteShareTextCodeOnly(String code) {
    return 'Komm in unseren Snacklist-Haushalt. Code: $code';
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
  String get retry => 'Erneut versuchen';

  @override
  String get lifetimeTitle => 'Snacklist Lifetime';

  @override
  String get lifetimeRowHint => 'Snacklist unterstützen';

  @override
  String get lifetimeBody =>
      'Ein Kauf, für euren ganzen Haushalt: Snacklist Lifetime unterstützt die Entwicklung von Snacklist.';

  @override
  String get lifetimeBuy => 'Weiter zum Kauf';

  @override
  String get lifetimePriceInStore =>
      'Den Preis zeigen dir der App Store oder Google Play, bevor du kaufst.';

  @override
  String get lifetimeRestore => 'Kauf wiederherstellen';

  @override
  String get lifetimeUnlockedBody =>
      'Snacklist Lifetime ist für euren ganzen Haushalt freigeschaltet. Danke!';

  @override
  String get lifetimePending => 'Wartet auf Bestätigung';

  @override
  String get lifetimePendingBody =>
      'Snacklist Lifetime wird freigeschaltet, sobald der Kauf bestätigt ist. Das kann etwas dauern.';

  @override
  String get lifetimeUnlocking => 'Wird freigeschaltet …';

  @override
  String get lifetimeUnlockDelayed =>
      'Dein Kauf ist angekommen, die Freischaltung dauert nur länger als sonst. Sie erscheint hier von selbst; bitte nicht noch einmal kaufen.';

  @override
  String get lifetimeBoughtTwice =>
      'Euer Haushalt hat Snacklist Lifetime mehr als einmal gekauft. Einen der Käufe kannst du dir erstatten lassen.';

  @override
  String get lifetimeCanceled => 'Kauf abgebrochen.';

  @override
  String get lifetimeComingSoon => 'Snacklist Lifetime ist bald verfügbar.';

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
      'Kaufen kannst du Snacklist Lifetime in der iPhone- oder Android-App. Danach ist es auch hier für deinen ganzen Haushalt freigeschaltet.';

  @override
  String get lifetimeChecking =>
      'Wir prüfen, ob dein Haushalt Snacklist Lifetime schon hat …';

  @override
  String get lifetimeRefundLink =>
      'Doppelt gekauft? So bekommst du dein Geld zurück';

  @override
  String get refundHelpTitle => 'Kauf zurückfordern';

  @override
  String get refundHelpBody =>
      'Snacklist Lifetime gehört immer zu dem Haushalt, in dem es gekauft wurde. Käufe im App Store erstattet nur Apple. Bei Google Play beantragst du die Erstattung in den ersten 48 Stunden bei Google; danach schreib uns an support@snacklist.app, wir prüfen jede Anfrage einzeln. Deine gesetzlichen Rechte bleiben unberührt.';

  @override
  String get refundHelpApple =>
      'iPhone: Öffne reportaproblem.apple.com, melde dich mit deinem Apple Account an, wähle „Rückerstattung anfordern“ und dann Snacklist Lifetime.';

  @override
  String get refundHelpGoogle =>
      'Android, in den ersten 48 Stunden: Öffne Google Play, tippe auf dein Profilbild, dann „Zahlungen und Abos“, „Budget und Bestellverlauf“, wähle Snacklist Lifetime und „Problem melden“. Danach schreib uns mit der Bestellnummer (beginnt mit „GPA.“) oder der E-Mail-Adresse deines Google-Kontos.';

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
      'Dieser Haushalt hat Snacklist Lifetime. Du musst nichts kaufen.';

  @override
  String get joinRefundLink =>
      'Du hast Snacklist Lifetime vor Kurzem gekauft? So forderst du den Kauf zurück';

  @override
  String get joinLifetimeRefundLink =>
      'Erstattung bei Apple oder Google anfragen';

  @override
  String get archivedTitle => 'Archivierte Haushalte';

  @override
  String get archivedEmpty => 'Du hast keinen Haushalt archiviert.';

  @override
  String get archivedUnlocked => 'Mit Snacklist Lifetime';

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
    return 'Du bist wieder Mitglied von „$household“. Deine anderen Haushalte bleiben.';
  }

  @override
  String get premiumTitle => 'Snacklist Premium';

  @override
  String get premiumHeroTitle => 'Einer kauft. Alle haben es.';

  @override
  String get premiumHeroBody =>
      'Snacklist Premium gilt für euren ganzen Haushalt, auch für alle, die später dazukommen.';

  @override
  String get premiumBenefitAi =>
      'KI-Assistenten, die MCP unterstützen, mit eurer Liste verbinden';

  @override
  String get premiumBenefitApi => 'Eigene Automationen mit der Snacklist API';

  @override
  String premiumStatusRenews(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Snacklist Premium aktiv (jährlich, verlängert sich am $dateString)';
  }

  @override
  String premiumStatusEnds(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Snacklist Premium aktiv (jährlich, läuft am $dateString aus)';
  }

  @override
  String get premiumStatusLifetime => 'Snacklist Premium Lifetime';

  @override
  String premiumWithVat(String period) {
    return '$period, inkl. MwSt.';
  }

  @override
  String get premiumBetaPrivacyLink => 'Mehr dazu in der Datenschutzerklärung';

  @override
  String get premiumBetaBody =>
      'Du zahlst nichts, und nichts verlängert sich automatisch. Bevor die kostenlose Freischaltung endet, sagen wir dir mindestens 4 Wochen vorher Bescheid.';

  @override
  String get premiumStatusFree =>
      'Kostenlos freigeschaltet (Test und App-Prüfung)';

  @override
  String get premiumStatusBeta =>
      'In der Beta kostenlos freigeschaltet, bis Snacklist Premium startet';

  @override
  String get premiumChecking =>
      'Wir prüfen, ob euer Haushalt Snacklist Premium schon hat …';

  @override
  String get premiumYearlyTitle => 'Jährlich';

  @override
  String get premiumPerYear => 'pro Jahr';

  @override
  String get premiumLifetimeTitle => 'Lifetime';

  @override
  String get premiumOneTime => 'einmalig';

  @override
  String get premiumLifetimeValue => 'Einmal zahlen, für immer.';

  @override
  String get premiumYearlyTerms =>
      'Snacklist Premium jährlich, Laufzeit 1 Jahr. Das Abo verlängert sich automatisch um ein Jahr, wenn du es nicht mindestens 24 Stunden vor Ende der Laufzeit kündigst. Bezahlt wird über dein Apple- bzw. Google-Konto, bei der Bestätigung des Kaufs und bei jeder Verlängerung. Verwalten und kündigen kannst du das Abo in den Abo-Einstellungen des App Store bzw. von Google Play.';

  @override
  String premiumHousehold(String household) {
    return 'Premium gehört dann zum Haushalt „$household“ und bleibt dort, auch wenn du den Haushalt später verlässt.';
  }

  @override
  String get premiumBuyYearly => 'Jährlich abschließen';

  @override
  String get premiumBuyLifetime => 'Lifetime kaufen';

  @override
  String get premiumUnavailable =>
      'Snacklist Premium ist gerade nicht verfügbar.';

  @override
  String get premiumTermsLink => 'Nutzungsbedingungen (EULA)';

  @override
  String get premiumPrivacyLink => 'Datenschutzerklärung';

  @override
  String get premiumUsedElsewhereYearly =>
      'Dein Apple- bzw. Google-Konto zahlt schon ein Jahresabo für einen anderen Haushalt. Jemand anderes aus diesem Haushalt kann Snacklist Premium abschließen.';

  @override
  String get premiumTwoYearly =>
      'Euer Haushalt hat zwei Jahresabos. Kündigen kann jedes nur, wer es abgeschlossen hat.';

  @override
  String get premiumWeb =>
      'Snacklist Premium kaufst du in der iPhone- oder Android-App. Danach ist es auch hier für deinen ganzen Haushalt freigeschaltet.';

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
      'Euer Haushalt hat schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird weiter abgerechnet, bis es gekündigt wird; das restliche Abojahr wird nicht automatisch erstattet. Kündigen kann nur, wer das Abo abgeschlossen hat, unter [Abos verwalten]. Snacklist kann das Abo nicht kündigen.';

  @override
  String get premiumLifetimeWhileYearlySubscriber =>
      'Euer Haushalt hat schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird weiter abgerechnet, bis es gekündigt wird; das restliche Abojahr wird nicht automatisch erstattet. Du kannst es unter [Abo verwalten] kündigen. Snacklist kann das Abo nicht kündigen.';

  @override
  String get premiumBuyAnyway => 'Trotzdem kaufen';

  @override
  String get premiumBillingContinues =>
      'Dein Jahresabo für Snacklist Premium läuft weiter und wird über dein Apple- bzw. Google-Konto abgerechnet, bis du es kündigst. Löschen oder Verlassen kündigt es nicht.';

  @override
  String get premiumBillingContinuesOther =>
      'Ein Jahresabo für diesen Haushalt läuft weiter, bis es gekündigt wird.';

  @override
  String get premiumManageSubscription => 'Abo verwalten';

  @override
  String get premiumContinueAnyway => 'Trotzdem fortfahren';

  @override
  String get integrationPremiumTitle => 'Teil von Snacklist Premium';

  @override
  String get integrationPremiumBody =>
      'KI-Assistenten gehören zu Snacklist Premium. Eure Verbindungen bleiben gespeichert und funktionieren wieder, sobald euer Haushalt Snacklist Premium hat.';

  @override
  String get integrationPremiumAi => 'KI-Assistenten, die MCP unterstützen';

  @override
  String get integrationPremiumLater =>
      'Später: Google Assistant und Apple Watch';

  @override
  String get integrationPremiumBuy => 'Snacklist Premium freischalten';

  @override
  String get integrationPremiumSoon => 'Bald verfügbar.';

  @override
  String get integrationPaused => 'Pausiert: braucht Snacklist Premium';

  @override
  String get apiHeader => 'API';

  @override
  String get apiBody =>
      'Für eigene Skripte und Automationen: Lies und ändere eure Liste über HTTP, mit einem API-Schlüssel.';

  @override
  String get apiDocs => 'API-Dokumentation';

  @override
  String get noApiKeys => 'Kein aktiver API-Schlüssel.';

  @override
  String get createApiKey => 'API-Schlüssel erstellen';

  @override
  String get apiKeyNameHint => 'z. B. Home Assistant';

  @override
  String get apiScopeRead => 'Nur lesen';

  @override
  String get apiScopeReadBody =>
      'Liest die Liste, Kategorien und Läden. Ändert nichts.';

  @override
  String get apiScopeReadWrite => 'Lesen und schreiben';

  @override
  String get apiScopeReadWriteBody =>
      'Kann auch Einträge hinzufügen, abhaken und verschieben.';

  @override
  String get apiKeyCreated => 'API-Schlüssel erstellt';

  @override
  String get apiKeyShownOnce =>
      'Kopiere den Schlüssel jetzt. Er wird nicht noch einmal angezeigt.';

  @override
  String get revokeApiKeyTitle => 'API-Schlüssel widerrufen?';

  @override
  String get revokeApiKeyBody =>
      'Skripte, die ihn benutzen, verlieren sofort den Zugriff.';

  @override
  String get tooManyApiKeys =>
      'Höchstens 10 aktive API-Schlüssel. Widerrufe erst einen.';

  @override
  String get apiKeySessionRequired =>
      'API-Schlüssel kannst du nur hier in der App erstellen, während du angemeldet bist.';

  @override
  String get apiDisabled => 'Die API ist noch nicht freigeschaltet.';

  @override
  String get apiPremium =>
      'Die Snacklist-API gehört zu Snacklist Premium. Deine Schlüssel bleiben und funktionieren wieder, sobald dein Haushalt Premium hat.';

  @override
  String get accessTokensHint =>
      'Mit einem Token baust du eigene Automationen, die eure Liste pflegen, etwa ein Skript oder einen Assistenten am MCP-Server.';

  @override
  String get accessTokensHintWithApi =>
      'Mit einem Token baust du eigene Automationen am MCP-Server, die eure Liste pflegen. Für Programme ohne MCP gibt es unten die API.';

  @override
  String accessKeysHousehold(String household) {
    return 'Ein neuer Token gilt für „$household“, den Haushalt, der gerade offen ist.';
  }

  @override
  String accessKeysHouseholdWithApi(String household) {
    return 'Neue Token und API-Schlüssel gelten für „$household“, den Haushalt, der gerade offen ist.';
  }

  @override
  String lastActiveOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Zuletzt aktiv $dateString';
  }

  @override
  String get notActiveYet => 'Noch nicht aktiv';

  @override
  String appDevice(String device) {
    return 'Freigegeben auf $device';
  }

  @override
  String appCanTitle(String name) {
    return 'Was $name darf';
  }

  @override
  String get appCanEmail => 'Deine E-Mail-Adresse sehen.';

  @override
  String get appCanProfile => 'Deinen Namen sehen.';

  @override
  String get appCanPhone => 'Deine Telefonnummer sehen.';

  @override
  String get appCanStay => 'Verbunden bleiben, bis du die Verbindung trennst.';

  @override
  String get copyEmail => 'E-Mail-Adresse kopieren';

  @override
  String get tipEditTitle => 'Artikel bearbeiten';

  @override
  String get tipEditBody =>
      'Halte einen Artikel gedrückt und ändere Menge, Marke, Laden und mehr.';

  @override
  String get tipAmountsTitle => 'Menge gleich mittippen';

  @override
  String get tipAmountsBody =>
      'Schreib „2 Gurken“ oder „Milch 2 l“, und Snacklist erkennt die Menge.';

  @override
  String get tipDismiss => 'Tipp ausblenden';

  @override
  String get tooManyHouseholds =>
      'Du bist schon in 20 Haushalten. Verlasse einen, bevor du einen neuen anlegst oder beitrittst.';

  @override
  String get householdSwitch => 'Haushalt wechseln';

  @override
  String get householdsTitle => 'Deine Haushalte';

  @override
  String householdMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder',
      one: '1 Mitglied',
    );
    return '$_temp0';
  }

  @override
  String householdOpenItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offen',
      one: '1 offen',
      zero: 'nichts offen',
    );
    return '$_temp0';
  }

  @override
  String get householdCurrent => 'Angezeigt';

  @override
  String get newHousehold => 'Neuer Haushalt';

  @override
  String get joinWithCode => 'Mit Code beitreten';

  @override
  String voiceDefaultRow(String household) {
    return 'Siri, Alexa & KI nutzen: $household';
  }

  @override
  String get voiceDefaultTitle => 'Standard für Siri, Alexa & KI';

  @override
  String get voiceDefaultBody =>
      'Was du Siri, Alexa oder einem KI-Assistenten sagst, landet in diesem Haushalt.';

  @override
  String get voiceDefaultOn =>
      'Siri, Alexa und KI-Assistenten nutzen diesen Haushalt.';

  @override
  String voiceDefaultOff(String household) {
    return 'Siri, Alexa und KI-Assistenten nutzen gerade „$household“.';
  }

  @override
  String get householdPageTitle => 'Haushalt';

  @override
  String get householdRename => 'Umbenennen';

  @override
  String get householdRenameTitle => 'Haushalt umbenennen';

  @override
  String get householdMembersTitle => 'Mitglieder';

  @override
  String householdMemberYou(String name) {
    return '$name (du)';
  }

  @override
  String get householdMemberUnnamed => 'Ohne Namen';

  @override
  String get householdMembersFailed =>
      'Die Mitglieder konnten nicht geladen werden.';

  @override
  String get leaveHousehold => 'Haushalt verlassen';

  @override
  String leaveTitle(String household) {
    return '„$household“ verlassen?';
  }

  @override
  String get leaveShared =>
      'Die anderen Mitglieder behalten die Liste. Zurück kommst du nur mit einer neuen Einladung.';

  @override
  String get leaveLast =>
      'Du bist das letzte Mitglied. Der Haushalt wird mit Liste, Verlauf, Kategorien und Geschäften gelöscht.';

  @override
  String leaveLifetimeEnds(String household) {
    return '„$household“ hat Snacklist Lifetime. Du bist das letzte Mitglied: Verlässt du ihn, wird der Haushalt gelöscht. Snacklist Lifetime endet mit ihm, denn ein Kauf gehört zu seinem Haushalt.';
  }

  @override
  String leaveArchiveOffer(String household) {
    return '„$household“ hat Snacklist Lifetime. Du bist das letzte Mitglied. Archiviere den Haushalt, statt ihn zu löschen: Liste und Snacklist Lifetime bleiben erhalten, und du kannst ihn später unter „Mehr“ wieder aktivieren. Aktivierst du ihn nicht innerhalb von 24 Monaten wieder, wird er gelöscht.';
  }

  @override
  String get leaveArchive => 'Archivieren und verlassen';

  @override
  String get leaveDelete => 'Löschen und verlassen';

  @override
  String consentDefaultHousehold(String name) {
    return 'Arbeitet in deinem Standard-Haushalt „$name“. Nennst du einen anderen deiner Haushalte, auch dort.';
  }

  @override
  String get voiceDefaultMake => 'Als Standard nutzen';

  @override
  String get defaultListTitle => 'Liste für Siri, Alexa & KI';

  @override
  String defaultListRow(String list) {
    return 'Liste: $list';
  }

  @override
  String get inviteSheetTitle => 'Leute einladen';

  @override
  String inviteSheetOpen(String name) {
    return 'Leute in $name einladen';
  }

  @override
  String get invitePremiumShared => 'Premium gilt für alle im Haushalt.';

  @override
  String get invitePersonTitle => 'Für eine Person';

  @override
  String get invitePersonBody => 'Ein Link für eine Person, 7 Tage gültig.';

  @override
  String get inviteJoinPageHint =>
      'Wer den Link hat, sieht auf der Beitrittsseite deinen Vornamen (aus deinem Anzeigenamen, falls du einen eingetragen hast), den Namen des Haushalts, die Zahl der Mitglieder und der offenen Einträge und ob der Haushalt Snacklist Premium hat. Gib den Link nur an Personen weiter, die du einladen willst.';

  @override
  String get inviteGroupTitle => 'Gruppenlink';

  @override
  String get inviteGroupBody =>
      'Für bis zu 50 Leute, 30 Tage gültig. Zeig den QR-Code oder teil den Link.';

  @override
  String get inviteGroupCreate => 'Gruppenlink erstellen';

  @override
  String inviteGroupUses(int count, int max) {
    return '$count von $max beigetreten';
  }

  @override
  String get inviteGroupFull =>
      'Der Link ist voll: Niemand kann mehr damit beitreten.';

  @override
  String get inviteGroupRevoked =>
      'Link widerrufen: Niemand kann mehr damit beitreten.';

  @override
  String get inviteGroupRevoke => 'Link widerrufen';

  @override
  String get inviteGroupRenew => 'Neuen Link erstellen';

  @override
  String get inviteGroupRevokeTitle => 'Gruppenlink widerrufen?';

  @override
  String get inviteGroupRevokeBody =>
      'Mit dem Link kann dann niemand mehr beitreten. Wer schon dabei ist, bleibt im Haushalt.';

  @override
  String get inviteGroupRevokeConfirm => 'Widerrufen';

  @override
  String get inviteGroupRenewTitle => 'Neuen Link erstellen?';

  @override
  String get inviteGroupRenewBody =>
      'Der bisherige Link funktioniert dann nicht mehr. Wer schon dabei ist, bleibt im Haushalt.';

  @override
  String get inviteGroupQr => 'QR-Code des Gruppenlinks';

  @override
  String get inviteJoinsTitle => 'Wer ist beigetreten';

  @override
  String get inviteJoinsEmpty => 'Noch niemand.';

  @override
  String inviteJoinedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'am $dateString';
  }

  @override
  String inviteShareKind(String kind, String name, String link, String code) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'partner':
          'Ich hab unsere Einkaufsliste in Snacklist angelegt. Komm dazu: $link · Code: $code',
      'family':
          'Unsere Familien-Einkaufsliste „$name“ ist jetzt in Snacklist. Komm dazu: $link · Code: $code',
      'flat':
          'Unsere WG-Einkaufsliste „$name“ ist jetzt in Snacklist. Komm dazu: $link · Code: $code',
      'club':
          'Wir planen die Einkäufe für „$name“ in Snacklist. Mach mit: $link · Code: $code',
      'solo':
          'Ich teile meine Einkaufsliste „$name“ in Snacklist mit dir: $link · Code: $code',
      'other': 'Komm in unseren Snacklist-Haushalt: $link · Code: $code',
    });
    return '$_temp0';
  }

  @override
  String get householdRoleOwner => 'Hauptadmin';

  @override
  String get householdRoleAdmin => 'Admin';

  @override
  String memberActions(String name) {
    return 'Optionen für $name';
  }

  @override
  String get memberMakeAdmin => 'Zum Admin machen';

  @override
  String get memberRemoveAdmin => 'Adminrechte entziehen';

  @override
  String get memberRemove => 'Aus dem Haushalt entfernen';

  @override
  String memberRemoveTitle(String name) {
    return '$name entfernen?';
  }

  @override
  String memberRemoveBody(String name, String household) {
    return '$name sieht die Liste von „$household“ dann nicht mehr und kommt über bisherige Einladungen oder den jetzigen Gruppenlink nicht zurück. In den nächsten 30 Tagen holt $name nur eine neue Einladung oder ein neuer Gruppenlink von einem Admin zurück.';
  }

  @override
  String get memberRemoveConfirm => 'Entfernen';

  @override
  String householdRemovedNotice(String name) {
    return 'Du wurdest aus dem Haushalt „$name“ entfernt. 30 Tage lang kommst du über alte Einladungen nicht zurück. Beitreten kannst du in dieser Zeit nur über eine neue Einladung vom Hauptadmin oder einem Admin.';
  }

  @override
  String householdGoneNotice(String name) {
    return 'Du bist nicht mehr Mitglied von „$name“.';
  }

  @override
  String get householdNotAdmin => 'Das können nur Admins.';

  @override
  String get householdCannotRemove => 'Diese Person kannst du nicht entfernen.';

  @override
  String get invitePaste => 'Einladung einfügen';

  @override
  String get invitePasteNothing =>
      'In der Zwischenablage ist kein Einladungslink und kein Code.';

  @override
  String get invitePasteWaiting =>
      'Einladung gemerkt. Melde dich an, dann trittst du bei.';

  @override
  String get householdNotOwner =>
      'Admins ernennt nur, wer den Haushalt angelegt hat.';

  @override
  String get listsTitle => 'Listen';

  @override
  String get listMain => 'Einkaufsliste';

  @override
  String get listNew => 'Neue Liste';

  @override
  String get listNameLabel => 'Name der Liste';

  @override
  String listAdded(String name) {
    return 'Liste „$name“ angelegt';
  }

  @override
  String get listRenameTitle => 'Liste umbenennen';

  @override
  String listActions(String name) {
    return 'Aktionen für „$name“';
  }

  @override
  String get listMoveUp => 'Nach oben';

  @override
  String get listMoveDown => 'Nach unten';

  @override
  String listDeleteTitle(String name) {
    return '„$name“ löschen?';
  }

  @override
  String listDeleteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Die $count offenen Artikel darauf werden mit gelöscht.',
      one: 'Der 1 offene Artikel darauf wird mit gelöscht.',
      zero: 'Auf der Liste ist nichts offen.',
    );
    return '$_temp0';
  }

  @override
  String get listsNeedConnection =>
      'Listen lassen sich nur mit Verbindung anlegen, umbenennen, sortieren oder löschen.';

  @override
  String onListAlready(String name, String list) {
    return '„$name“ steht schon auf „$list“.';
  }

  @override
  String get editList => 'Liste';

  @override
  String get claimMine => 'Ich bringe das';

  @override
  String get claimAmount => 'Wie viel?';

  @override
  String get claimAmountHint => 'z. B. 2';

  @override
  String claimBy(String name) {
    return '$name bringt';
  }

  @override
  String claimByAmount(String name, String amount) {
    return '$name bringt $amount';
  }

  @override
  String get claimYou => 'Du bringst';

  @override
  String claimYouAmount(String amount) {
    return 'Du bringst $amount';
  }

  @override
  String get claimSomeone => 'Jemand';

  @override
  String joinRequestSent(String name) {
    return 'Anfrage gesendet: Ein Admin von „$name“ bestätigt deinen Beitritt.';
  }

  @override
  String get joinDeclinedRecently =>
      'Deine Anfrage für diesen Haushalt wurde vor Kurzem abgelehnt. Du kannst nach 24 Stunden wieder anfragen.';

  @override
  String get joinRequestWithdraw => 'Anfrage zurückziehen';

  @override
  String get joinRequestToList => 'Zur Liste';

  @override
  String get joinRequestCreateOwn => 'Eigenen Haushalt anlegen';

  @override
  String joinApprovedNotice(String name) {
    return 'Du bist jetzt in „$name“.';
  }

  @override
  String joinDeclinedNotice(String name) {
    return 'Deine Anfrage für „$name“ wurde nicht angenommen.';
  }

  @override
  String get joinRequestPending => 'Anfrage offen';

  @override
  String joinRequestWithdrawFor(String name) {
    return 'Anfrage für „$name“ zurückziehen?';
  }

  @override
  String get joinApprovalToggle => 'Beitritte bestätigen';

  @override
  String get joinApprovalHint =>
      'Neue Leute warten, bis ein Admin sie aufnimmt.';

  @override
  String get joinRequestsTitle => 'Beitrittsanfragen';

  @override
  String joinRequestsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offene Anfragen',
      one: '1 offene Anfrage',
    );
    return '$_temp0';
  }

  @override
  String get joinRequestsNone => 'Keine offenen Anfragen.';

  @override
  String get joinRequestsFailed => 'Anfragen konnten nicht geladen werden.';

  @override
  String get joinRequestApprove => 'Aufnehmen';

  @override
  String get joinRequestInviteFull =>
      'Die Einladung zu dieser Anfrage ist voll. Schick einen neuen Link. Sobald er geöffnet ist, kannst du aufnehmen.';

  @override
  String get joinRequestDecline => 'Ablehnen';

  @override
  String get hintInviteTitle => 'Gemeinsam einkaufen';

  @override
  String get hintInviteBody =>
      'Lade jemanden ein, um die Liste gemeinsam zu nutzen.';

  @override
  String get hintInviteAction => 'Einladen';

  @override
  String get hintStoreOrderTitle => 'Sortiert wie dein Laden';

  @override
  String get hintStoreOrderBody =>
      'Hier kannst du die Kategorien so sortieren, wie du durch den Laden gehst.';

  @override
  String get hintAddStoreTitle => 'Noch ein Laden?';

  @override
  String get hintAddStoreBody =>
      'Hier kannst du weitere Läden anlegen, bei denen du einkaufst.';

  @override
  String get hintDictationTitle => 'Sag einfach, was fehlt';

  @override
  String get hintDictationBody =>
      'Tipp aufs Mikrofon und sprich: „Milch, zwei Gurken und Klopapier“.';

  @override
  String get hintAssistantTitle => 'Noch besser mit KI & Automatisierung';

  @override
  String get hintAssistantBody =>
      'Lass deinen KI-Assistenten deine Liste verwalten oder nutze die API, um Automatisierungen zu erstellen.';

  @override
  String get hintAssistantAction => 'Zugriffe verwalten';

  @override
  String get hintSiriTitle => 'Mit Siri hinzufügen';

  @override
  String get hintSiriBody =>
      'Sag „Hey Siri, füge etwas zu Snacklist hinzu“, wenn die Hände voll sind.';

  @override
  String get hintWidgetTitle => 'Liste auf dem Home-Bildschirm';

  @override
  String get hintWidgetBody =>
      'Füge das Snacklist-Widget hinzu, indem du den Home-Bildschirm deines Smartphones gedrückt hältst.';

  @override
  String get hintOwnHouseholdTitle => 'Deine eigene Liste';

  @override
  String get hintOwnHouseholdBody =>
      'Diesen Haushalt hat jemand anderes angelegt. Leg auch einen eigenen an, zum Beispiel nur für dich.';

  @override
  String get hintSecondHouseholdTitle => 'Noch eine Liste?';

  @override
  String get hintSecondHouseholdBody =>
      'Für den Verein oder die WG: Leg einen zweiten Haushalt an.';

  @override
  String get hintAddHouseholdAction => 'Haushalt erstellen';

  @override
  String get hintDismissedNotice => 'Alle Tipps unter Mehr → Tipps.';

  @override
  String get hintsTitle => 'Tipps';

  @override
  String get checklistTitle => 'Erste Schritte';

  @override
  String get checklistDismiss => 'Erste Schritte ausblenden';

  @override
  String checklistProgress(int done, int total) {
    return '$done von $total';
  }

  @override
  String get checklistStarted => 'Liste angelegt';

  @override
  String get checklistJoined => 'Haushalt beigetreten';

  @override
  String checklistInvite(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'partner': 'Partner einladen',
      'family': 'Familie einladen',
      'flat': 'Mitbewohner einladen',
      'club': 'Mitglieder einladen',
      'other': 'Jemanden einladen',
    });
    return '$_temp0';
  }

  @override
  String checklistInviteBody(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'club': 'Alle sehen dieselbe Liste und können selbst etwas draufsetzen.',
      'other': 'Sieht deine Artikel sofort und kann selbst etwas draufsetzen.',
    });
    return '$_temp0';
  }

  @override
  String get checklistShop => 'Einmal einkaufen';

  @override
  String get checklistAssistant => 'KI-Assistenten verbinden';

  @override
  String get checklistAssistantBody =>
      'Mehr → Zugänge. Er setzt Dinge auf eure Liste.';

  @override
  String get checklistOpen => 'Öffnen';

  @override
  String checklistDone(String step) {
    return '$step, erledigt';
  }

  @override
  String get tabHistory => 'Verlauf';

  @override
  String get historyShowByStore => 'Nach Laden anzeigen';

  @override
  String get historyShowByDate => 'Nach Datum anzeigen';

  @override
  String get tripAdd => 'Einkauf eintragen';

  @override
  String get tripAddShort => 'Eintragen';

  @override
  String get tripEdit => 'Einkauf bearbeiten';

  @override
  String tripAddAt(String store) {
    return 'Einkauf bei $store eintragen';
  }

  @override
  String get historyEmptyTitle => 'Noch keine Einkäufe';

  @override
  String get historyEmptyBody =>
      'Trag nach dem Einkauf ein, was du gekauft hast. So findet ihr später, wann ihr wo was geholt habt.';

  @override
  String get historyLoadFailed => 'Der Verlauf konnte nicht geladen werden.';

  @override
  String get historyThisWeek => 'Diese Woche';

  @override
  String get historyLastWeek => 'Letzte Woche';

  @override
  String historyDayFilter(DateTime day) {
    final intl.DateFormat dayDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dayString = dayDateFormat.format(day);

    return 'Einkäufe am $dayString';
  }

  @override
  String get historyDayClear => 'Alle Einkäufe zeigen';

  @override
  String get historyDayEmpty => 'Keine Einkäufe an diesem Tag';

  @override
  String historyDayLabel(String date, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einkäufe',
      one: '1 Einkauf',
    );
    return '$date, $_temp0';
  }

  @override
  String get historyStoreEmpty => 'Noch kein Einkauf';

  @override
  String get historyLockedTitle =>
      'Ältere Einkäufe siehst du mit Snacklist Premium';

  @override
  String historyLockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ältere Einkäufe',
      one: '1 älterer Einkauf',
    );
    return '$_temp0';
  }

  @override
  String historyDayLocked(String date) {
    return '$date, ältere Einkäufe mit Snacklist Premium';
  }

  @override
  String get tripStoreMissing => 'Wähle einen Laden.';

  @override
  String get tripStoreGone => 'Dieser Laden wurde gelöscht.';

  @override
  String get previousMonth => 'Vorheriger Monat';

  @override
  String get nextMonth => 'Nächster Monat';

  @override
  String get dayToday => 'Heute';

  @override
  String get dayYesterday => 'Gestern';

  @override
  String get tripStore => 'Laden';

  @override
  String get tripDay => 'Wann';

  @override
  String get tripOtherDay => 'Anderer Tag';

  @override
  String get tripItems => 'Gekauft';

  @override
  String get tripItemName => 'Artikel';

  @override
  String get tripAddItem => 'Artikel hinzufügen';

  @override
  String tripRemoveItem(String name) {
    return '$name entfernen';
  }

  @override
  String get tripDelete => 'Einkauf löschen';

  @override
  String get tripDeleteTitle => 'Einkauf löschen?';

  @override
  String get tripDeleteBody =>
      'Der Einkauf verschwindet für alle im Haushalt aus dem Verlauf.';

  @override
  String get tripDeleteFailed =>
      'Der Einkauf konnte nicht gelöscht werden. Versuch es noch mal.';

  @override
  String get tripSaveFailed =>
      'Der Einkauf konnte nicht gespeichert werden. Versuch es noch mal.';

  @override
  String tripItemCount(int count) {
    return '$count Artikel';
  }

  @override
  String tripSummaryMore(String names, int count) {
    return '$names und $count mehr';
  }

  @override
  String tripPromptAt(String store) {
    return 'Einkauf bei $store eintragen?';
  }

  @override
  String get tripPrompt => 'Einkauf eintragen?';

  @override
  String tripPromptTicked(int count, String names) {
    return '$count Artikel abgehakt: $names';
  }

  @override
  String get tripPromptLog => 'Eintragen';

  @override
  String get tripLogged => 'Einkauf eingetragen';

  @override
  String get priceAdd => 'Preis';

  @override
  String priceChipEmpty(String name) {
    return 'Preis für $name';
  }

  @override
  String priceChipSet(String name, String amount) {
    return 'Preis für $name: $amount, ändern';
  }

  @override
  String get priceField => 'Preis';

  @override
  String get weightField => 'Gewicht in kg';

  @override
  String get pricePerPiece => 'pro Stück';

  @override
  String get pricePerKg => 'pro kg';

  @override
  String get pricePerLitre => 'pro l';

  @override
  String get priceUnitLitre => 'l';

  @override
  String get volumeField => 'Menge in l';

  @override
  String get volumeErrorEmpty => 'Gib die Menge ein.';

  @override
  String get volumeErrorZero => 'Die Menge muss über 0 ml liegen.';

  @override
  String get volumeErrorTooLarge => 'Höchstens 50 l.';

  @override
  String get priceLine => 'Gesamt';

  @override
  String get priceBasisLabel => 'Preis gilt';

  @override
  String get priceUnitPiece => 'Stück';

  @override
  String get priceUnitKg => 'kg';

  @override
  String get priceUnitLabel => 'Einheit';

  @override
  String get priceCountLess => 'Eins weniger';

  @override
  String get priceCountMore => 'Eins mehr';

  @override
  String priceCount(int count) {
    return 'Menge $count';
  }

  @override
  String priceTogether(String amount) {
    return 'Zusammen $amount';
  }

  @override
  String priceUnitIs(String amount, String per) {
    return 'Das sind $amount $per';
  }

  @override
  String priceTotalAfter(String amount) {
    return 'Summe danach $amount';
  }

  @override
  String priceDearer(String amount) {
    return '$amount teurer als zuletzt';
  }

  @override
  String priceCheaper(String amount) {
    return '$amount billiger als zuletzt';
  }

  @override
  String get priceSame => 'Wie zuletzt';

  @override
  String get priceErrorEmpty => 'Gib einen Preis ein.';

  @override
  String priceErrorTooLarge(String min, String max) {
    return 'Zwischen $min und $max pro Artikel.';
  }

  @override
  String get weightErrorEmpty => 'Gib das Gewicht ein.';

  @override
  String get weightErrorZero => 'Das Gewicht muss über 0 g liegen.';

  @override
  String get weightErrorTooLarge => 'Höchstens 50 kg.';

  @override
  String get priceRemove => 'Preis entfernen';

  @override
  String get tripTotal => 'Einkaufssumme';

  @override
  String tripCounts(int priced, int open) {
    return '$priced mit Preis · $open offen';
  }

  @override
  String tripTotalLabel(String amount, int priced, int open) {
    return 'Einkaufssumme $amount, $priced mit Preis, $open offen';
  }

  @override
  String storeSubtotal(String store, String amount) {
    return 'Summe $store $amount';
  }

  @override
  String get currencyTitle => 'Währung';

  @override
  String get currencyHint =>
      'Für Preise und die Einkaufssumme, für alle im Haushalt';

  @override
  String get currencyPick => 'Währung wählen';

  @override
  String get listSwitch => 'Liste oder Haushalt wechseln';

  @override
  String get switcherHouseholds => 'Haushalte';

  @override
  String switcherBack(String page) {
    return 'Zurück: $page';
  }

  @override
  String get switcherInvite => 'Einladen';

  @override
  String switcherOpenInvites(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einladungen offen',
      one: '1 Einladung offen',
    );
    return '$_temp0';
  }

  @override
  String get switcherOpenInvitesTitle => 'Offene Einladungen';

  @override
  String get shopAskTitle => 'Kaufst du gerade ein?';

  @override
  String get shopAskBody =>
      'Dann läuft eine Uhr mit, und am Ende siehst du, was geplant war und was dazukam.';

  @override
  String get shopAskYes => 'Ja, Einkauf starten';

  @override
  String get shopAskNo => 'Nein, nur abgehakt';

  @override
  String get shopAskMistake => 'Aus Versehen abgehakt?';

  @override
  String get shopAskTakeBack => 'Zurücknehmen';

  @override
  String get shopRunning => 'Einkauf läuft';

  @override
  String get shopPaused => 'Pausiert';

  @override
  String shopAutoPaused(String time) {
    return 'Pause · seit $time nichts abgehakt';
  }

  @override
  String get shopPause => 'Pause';

  @override
  String get shopResume => 'Weiter';

  @override
  String get shopEnd => 'Beenden';

  @override
  String shopEndAt(String time) {
    return 'Beenden um $time';
  }

  @override
  String shopClockLabel(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'seit $minutes Minuten',
      one: 'seit 1 Minute',
      zero: 'seit weniger als einer Minute',
    );
    return '$_temp0';
  }

  @override
  String get shopAutoEndedTitle => 'Einkauf automatisch beendet';

  @override
  String shopAutoEndedBody(String time) {
    return '4 Stunden lang wurde nichts abgehakt. Er endet beim letzten Abhaken um $time.';
  }

  @override
  String get shopKeepGoing => 'Doch weiter';

  @override
  String get shopShowSummary => 'Übersicht ansehen';

  @override
  String get shopSummaryTitle => 'Geplant und gekauft';

  @override
  String shopSummaryWhen(String day, String from, String to) {
    return '$day, $from bis $to';
  }

  @override
  String shopMinutes(int minutes) {
    return '$minutes Min.';
  }

  @override
  String get shopUnderAMinute => 'Unter 1 Min.';

  @override
  String shopHoursMinutes(int hours, int minutes) {
    return '$hours Std. $minutes Min.';
  }

  @override
  String shopShoppedFor(String duration) {
    return '$duration eingekauft';
  }

  @override
  String shopLede(int bought, int planned) {
    return '$bought von $planned von der Liste gekauft';
  }

  @override
  String shopLedeExtra(int count) {
    return '$count zusätzlich';
  }

  @override
  String shopLedeNoList(int count) {
    return 'Ohne Liste losgegangen · $count gekauft';
  }

  @override
  String shopAutoEndHint(String time) {
    return 'Beendet beim letzten Abhaken um $time, automatisch.';
  }

  @override
  String get shopPlannedSection => 'Beim Start auf der Liste';

  @override
  String get shopExtraSection => 'Seit dem Start dazugekommen';

  @override
  String get shopPlannedEmpty => 'Die Liste war leer.';

  @override
  String get shopExtraEmpty => 'Nichts. Alles stand auf der Liste.';

  @override
  String get shopNotBought => 'nicht gekauft';

  @override
  String get shopBought => 'gekauft';

  @override
  String shopBy(String name) {
    return 'von $name';
  }

  @override
  String get shopMarkPlanned => 'War geplant';

  @override
  String get shopMarkPlannedHint =>
      '„War geplant“ zählt einen Artikel zur Liste, wenn er abgesprochen war, aber nicht draufstand.';

  @override
  String shopPlannedPrice(String amount) {
    return 'geplant $amount';
  }

  @override
  String shopMore(String amount) {
    return '$amount mehr';
  }

  @override
  String shopLess(String amount) {
    return '$amount weniger';
  }

  @override
  String get shopAsPlanned => 'wie geplant';

  @override
  String get shopPaid => 'Bezahlt';

  @override
  String get shopPaidTotal => 'Insgesamt bezahlt';

  @override
  String shopCompared(String amount, String difference) {
    return 'Geplant $amount · $difference';
  }

  @override
  String shopComparedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bei $count Artikeln',
      one: 'bei 1 Artikel',
    );
    return '$_temp0';
  }

  @override
  String shopWithoutPrice(int count) {
    return '$count ohne Preis';
  }

  @override
  String shopWithoutPlan(int count) {
    return '$count ohne geplanten Preis';
  }

  @override
  String get shopTotalsNote =>
      'Bezahlt zählt nur Artikel mit Preis. Der Unterschied vergleicht nur Artikel mit geplantem und bezahltem Preis.';

  @override
  String get shopKeepShopping => 'Weiter einkaufen';

  @override
  String get shopNotSaved => 'Der Einkauf ist noch nicht gespeichert.';

  @override
  String shopTicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artikel abgehakt',
      one: '1 Artikel abgehakt',
    );
    return '$_temp0';
  }

  @override
  String get shopLockedTitle => 'Was war geplant, was kam dazu?';

  @override
  String get shopLockedBody =>
      'Snacklist Premium zeigt nach jedem Einkauf, was auf der Liste stand und was unterwegs dazukam, auch von anderen im Haushalt.';

  @override
  String get shopLockedButton => 'Snacklist Premium ansehen';

  @override
  String get shopLoadFailed => 'Die Übersicht konnte nicht geladen werden.';

  @override
  String get shopStartByHand => 'Einkauf starten';

  @override
  String get shopStartByHandHint =>
      'Die Uhr läuft ab jetzt, die Liste, wie sie jetzt ist, gilt als geplant.';

  @override
  String get shopByOther => 'von jemand anderem';

  @override
  String get shopMarkFailed =>
      '„War geplant“ konnte nicht gespeichert werden. Versuch es noch mal.';

  @override
  String get subtotalsTotal => 'Gesamt';

  @override
  String subtotalsUnpriced(int count) {
    return '$count ohne Preis';
  }

  @override
  String get subtotalsAllBought => 'alles gekauft';

  @override
  String subtotalsBought(String amount) {
    return '$amount gekauft';
  }

  @override
  String subtotalsOpen(String amount) {
    return '$amount offen';
  }

  @override
  String get subtotalsJump => 'Zum Laden in der Liste';

  @override
  String moneyAtLeast(String amount) {
    return 'mind. $amount';
  }

  @override
  String moneyAtLeastSpoken(String amount) {
    return 'mindestens $amount';
  }

  @override
  String moneyEstimate(String amount) {
    return '≈ $amount';
  }

  @override
  String moneyEstimateSpoken(String amount) {
    return 'etwa $amount';
  }
}
