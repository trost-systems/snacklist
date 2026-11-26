import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'Snacklist'**
  String get appTitle;

  /// No description provided for @addFieldHint.
  ///
  /// In de, this message translates to:
  /// **'Was brauchst du?'**
  String get addFieldHint;

  /// No description provided for @addButton.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get addButton;

  /// No description provided for @emptyList.
  ///
  /// In de, this message translates to:
  /// **'Die Liste ist leer. Tippe unten ein, was fehlt.'**
  String get emptyList;

  /// No description provided for @sortingItem.
  ///
  /// In de, this message translates to:
  /// **'Wird einsortiert …'**
  String get sortingItem;

  /// No description provided for @recentlyUsed.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt verwendet'**
  String get recentlyUsed;

  /// No description provided for @readd.
  ///
  /// In de, this message translates to:
  /// **'Wieder auf die Liste'**
  String get readd;

  /// No description provided for @itemDeleted.
  ///
  /// In de, this message translates to:
  /// **'{name} gelöscht'**
  String itemDeleted(String name);

  /// No description provided for @itemTicked.
  ///
  /// In de, this message translates to:
  /// **'{name} abgehakt'**
  String itemTicked(String name);

  /// No description provided for @alreadyOnList.
  ///
  /// In de, this message translates to:
  /// **'{name} steht schon auf der Liste'**
  String alreadyOnList(String name);

  /// No description provided for @dedupeMerge.
  ///
  /// In de, this message translates to:
  /// **'Zusammenführen'**
  String get dedupeMerge;

  /// No description provided for @dedupeMerged.
  ///
  /// In de, this message translates to:
  /// **'Zusammengeführt: {item}'**
  String dedupeMerged(String item);

  /// No description provided for @mergeRefused.
  ///
  /// In de, this message translates to:
  /// **'{name} konnte nicht zusammengeführt werden'**
  String mergeRefused(String name);

  /// No description provided for @dictationStart.
  ///
  /// In de, this message translates to:
  /// **'Diktieren'**
  String get dictationStart;

  /// No description provided for @dictationStop.
  ///
  /// In de, this message translates to:
  /// **'Diktat beenden'**
  String get dictationStop;

  /// No description provided for @dictationListening.
  ///
  /// In de, this message translates to:
  /// **'Ich höre zu …'**
  String get dictationListening;

  /// No description provided for @dictationUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Spracheingabe ist nicht verfügbar. Erlaube Mikrofon und Spracherkennung in den Einstellungen.'**
  String get dictationUnavailable;

  /// The device can't recognize speech offline in the app's language. Dictation listens in the app's language, so each translation names its own language (job 256).
  ///
  /// In de, this message translates to:
  /// **'Diktieren geht nur offline, damit deine Stimme auf dem Gerät bleibt. Dafür fehlt hier die deutsche Offline-Spracherkennung. Lade sie in den Systemeinstellungen herunter oder tippe den Eintrag ein.'**
  String get dictationNoOfflineSpeech;

  /// Android lacks offline speech recognition in the app's language and was asked to download it (or is downloading it). Dictation listens in the app's language, so each translation names its own language (job 256).
  ///
  /// In de, this message translates to:
  /// **'Diktieren geht nur offline, damit deine Stimme auf dem Gerät bleibt. Snacklist hat Android gebeten, die deutsche Offline-Spracherkennung herunterzuladen. Versuch es noch einmal, sobald sie installiert ist, oder tippe den Eintrag ein.'**
  String get dictationOfflineSpeechDownloading;

  /// No description provided for @dictationNothingHeard.
  ///
  /// In de, this message translates to:
  /// **'Ich habe nichts gehört.'**
  String get dictationNothingHeard;

  /// No description provided for @dictationNothingUnderstood.
  ///
  /// In de, this message translates to:
  /// **'Ich habe nichts verstanden, was auf die Liste soll.'**
  String get dictationNothingUnderstood;

  /// No description provided for @dictationSplitFailed.
  ///
  /// In de, this message translates to:
  /// **'Keine Verbindung. Der Text steht im Feld; prüfe ihn und tippe auf Hinzufügen.'**
  String get dictationSplitFailed;

  /// No description provided for @dictationAdded.
  ///
  /// In de, this message translates to:
  /// **'Hinzugefügt: {items}.'**
  String dictationAdded(String items);

  /// No description provided for @dictationAlreadyOnList.
  ///
  /// In de, this message translates to:
  /// **'Schon auf der Liste: {items}.'**
  String dictationAlreadyOnList(String items);

  /// After a dictated sentence with more than 30 items: only the first 30 were added (job 111). Same words as Siri's answer (voice/copy.ts tooMany).
  ///
  /// In de, this message translates to:
  /// **'Mehr als dreißig auf einmal gehen nicht; sag den Rest bitte noch einmal.'**
  String get dictationTooMany;

  /// No description provided for @undo.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get undo;

  /// No description provided for @editSheet.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get editSheet;

  /// No description provided for @fieldName.
  ///
  /// In de, this message translates to:
  /// **'Bezeichnung'**
  String get fieldName;

  /// No description provided for @fieldBrand.
  ///
  /// In de, this message translates to:
  /// **'Marke'**
  String get fieldBrand;

  /// No description provided for @brandNone.
  ///
  /// In de, this message translates to:
  /// **'ohne Marke'**
  String get brandNone;

  /// No description provided for @itemQuantity.
  ///
  /// In de, this message translates to:
  /// **'Menge'**
  String get itemQuantity;

  /// No description provided for @fieldProperties.
  ///
  /// In de, this message translates to:
  /// **'Eigenschaften'**
  String get fieldProperties;

  /// No description provided for @propertiesExample.
  ///
  /// In de, this message translates to:
  /// **'z. B. Bio, 1 l'**
  String get propertiesExample;

  /// No description provided for @quantityMinus.
  ///
  /// In de, this message translates to:
  /// **'Eins weniger'**
  String get quantityMinus;

  /// No description provided for @quantityPlus.
  ///
  /// In de, this message translates to:
  /// **'Eins mehr'**
  String get quantityPlus;

  /// No description provided for @noStore.
  ///
  /// In de, this message translates to:
  /// **'Ohne Laden'**
  String get noStore;

  /// Screen-reader name of the store chip in the edit and add sheets
  ///
  /// In de, this message translates to:
  /// **'Laden: {name}'**
  String chipStore(String name);

  /// Screen-reader name of the category chip
  ///
  /// In de, this message translates to:
  /// **'Kategorie: {name}'**
  String chipCategory(String name);

  /// No description provided for @categoryAuto.
  ///
  /// In de, this message translates to:
  /// **'Kategorie: automatisch'**
  String get categoryAuto;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// List: the sync indicator's title and its collapsed pill's word while offline
  ///
  /// In de, this message translates to:
  /// **'Offline'**
  String get syncOffline;

  /// No description provided for @syncOfflineLine.
  ///
  /// In de, this message translates to:
  /// **'Änderungen werden synchronisiert, sobald du wieder online bist.'**
  String get syncOfflineLine;

  /// List: the offline indicator for screen readers; must start with the title and a colon (e2e)
  ///
  /// In de, this message translates to:
  /// **'Offline: Änderungen werden synchronisiert, sobald du wieder online bist.'**
  String get syncOfflineLabel;

  /// No description provided for @syncFailing.
  ///
  /// In de, this message translates to:
  /// **'Sync gestört'**
  String get syncFailing;

  /// List: the collapsed failing pill's one word
  ///
  /// In de, this message translates to:
  /// **'Gestört'**
  String get syncFailingWord;

  /// No description provided for @syncFailingLine.
  ///
  /// In de, this message translates to:
  /// **'Deine Änderungen sind auf dem Gerät gespeichert.'**
  String get syncFailingLine;

  /// List: the failing indicator for screen readers; must start with the title and a colon (e2e)
  ///
  /// In de, this message translates to:
  /// **'Sync gestört: Deine Änderungen sind auf dem Gerät gespeichert.'**
  String get syncFailingLabel;

  /// No description provided for @syncRetrying.
  ///
  /// In de, this message translates to:
  /// **'Wird erneut versucht'**
  String get syncRetrying;

  /// No description provided for @syncDetails.
  ///
  /// In de, this message translates to:
  /// **'Details anzeigen'**
  String get syncDetails;

  /// List: announced to screen readers when a retry went through; nothing shows
  ///
  /// In de, this message translates to:
  /// **'Synchronisiert'**
  String get syncSynced;

  /// No description provided for @syncStillFailing.
  ///
  /// In de, this message translates to:
  /// **'Immer noch gestört'**
  String get syncStillFailing;

  /// No description provided for @syncFailed.
  ///
  /// In de, this message translates to:
  /// **'Änderung abgelehnt: {name}'**
  String syncFailed(String name);

  /// No description provided for @inviteMember.
  ///
  /// In de, this message translates to:
  /// **'Leute einladen'**
  String get inviteMember;

  /// Invite screen (invite-partner route): title
  ///
  /// In de, this message translates to:
  /// **'Gemeinsam einkaufen'**
  String get inviteScreenTitle;

  /// No description provided for @signOut.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get signOut;

  /// No description provided for @inviteTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitglied einladen'**
  String get inviteTitle;

  /// No description provided for @inviteBody.
  ///
  /// In de, this message translates to:
  /// **'Gib diesen Code in der App ein oder teile den Link. Die Einladung gilt 7 Tage und für eine Person.'**
  String get inviteBody;

  /// No description provided for @inviteCodeLabel.
  ///
  /// In de, this message translates to:
  /// **'Code'**
  String get inviteCodeLabel;

  /// No description provided for @inviteLinkLabel.
  ///
  /// In de, this message translates to:
  /// **'Link'**
  String get inviteLinkLabel;

  /// No description provided for @copy.
  ///
  /// In de, this message translates to:
  /// **'Kopieren'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In de, this message translates to:
  /// **'Kopiert'**
  String get copied;

  /// No description provided for @close.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get close;

  /// No description provided for @signInTitle.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get signInTitle;

  /// No description provided for @email.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get email;

  /// No description provided for @password.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get password;

  /// No description provided for @signIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In de, this message translates to:
  /// **'Registrieren'**
  String get signUp;

  /// No description provided for @sendMagicLink.
  ///
  /// In de, this message translates to:
  /// **'Anmeldelink per E-Mail senden'**
  String get sendMagicLink;

  /// No description provided for @magicLinkSent.
  ///
  /// In de, this message translates to:
  /// **'Wir haben dir einen Anmeldelink geschickt. Öffne ihn auf diesem Gerät.'**
  String get magicLinkSent;

  /// No description provided for @signUpCheckEmail.
  ///
  /// In de, this message translates to:
  /// **'Bitte bestätige deine E-Mail-Adresse über den Link, den wir dir geschickt haben.'**
  String get signUpCheckEmail;

  /// No description provided for @invalidEmail.
  ///
  /// In de, this message translates to:
  /// **'Bitte eine gültige E-Mail-Adresse eingeben'**
  String get invalidEmail;

  /// No description provided for @passwordTooShort.
  ///
  /// In de, this message translates to:
  /// **'Mindestens 6 Zeichen'**
  String get passwordTooShort;

  /// No description provided for @authFailed.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlgeschlagen: {message}'**
  String authFailed(String message);

  /// No description provided for @signInWithGoogle.
  ///
  /// In de, this message translates to:
  /// **'Mit Google anmelden'**
  String get signInWithGoogle;

  /// No description provided for @signInWithApple.
  ///
  /// In de, this message translates to:
  /// **'Mit Apple anmelden'**
  String get signInWithApple;

  /// No description provided for @signInCanceled.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung abgebrochen'**
  String get signInCanceled;

  /// No description provided for @continueWithEmail.
  ///
  /// In de, this message translates to:
  /// **'Weiter mit E-Mail'**
  String get continueWithEmail;

  /// No description provided for @orWithEmail.
  ///
  /// In de, this message translates to:
  /// **'oder mit E-Mail'**
  String get orWithEmail;

  /// No description provided for @onboardingTitle.
  ///
  /// In de, this message translates to:
  /// **'Willkommen bei Snacklist'**
  String get onboardingTitle;

  /// No description provided for @onboardingBody.
  ///
  /// In de, this message translates to:
  /// **'Snacklist teilt eine Einkaufsliste mit allen in deinem Haushalt. Erstelle einen neuen Haushalt oder nimm eine Einladung an.'**
  String get onboardingBody;

  /// No description provided for @householdName.
  ///
  /// In de, this message translates to:
  /// **'Name des Haushalts'**
  String get householdName;

  /// No description provided for @householdNameDefault.
  ///
  /// In de, this message translates to:
  /// **'Unser Haushalt'**
  String get householdNameDefault;

  /// Hint in the empty name field when creating a further household from the switcher (job 169b).
  ///
  /// In de, this message translates to:
  /// **'z. B. Eltern, WG, Verein'**
  String get householdNameHintFurther;

  /// No description provided for @createHousehold.
  ///
  /// In de, this message translates to:
  /// **'Haushalt erstellen'**
  String get createHousehold;

  /// No description provided for @inviteCode.
  ///
  /// In de, this message translates to:
  /// **'Einladungscode'**
  String get inviteCode;

  /// No description provided for @joinHousehold.
  ///
  /// In de, this message translates to:
  /// **'Haushalt beitreten'**
  String get joinHousehold;

  /// Title of the join screen when already in a household; shorter than the More row, which fits 360 px
  ///
  /// In de, this message translates to:
  /// **'Haushalt beitreten'**
  String get joinTitle;

  /// No description provided for @invalidInvite.
  ///
  /// In de, this message translates to:
  /// **'Dieser Code ist ungültig oder abgelaufen.'**
  String get invalidInvite;

  /// No description provided for @genericError.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen: {message}'**
  String genericError(String message);

  /// No description provided for @loading.
  ///
  /// In de, this message translates to:
  /// **'Lädt …'**
  String get loading;

  /// No description provided for @consentTitle.
  ///
  /// In de, this message translates to:
  /// **'Zugriff erlauben?'**
  String get consentTitle;

  /// No description provided for @consentSignedInAs.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet als {email}'**
  String consentSignedInAs(String email);

  /// No description provided for @consentHousehold.
  ///
  /// In de, this message translates to:
  /// **'Haushalt: {name}'**
  String consentHousehold(String name);

  /// No description provided for @consentWants.
  ///
  /// In de, this message translates to:
  /// **'{client} möchte:'**
  String consentWants(String client);

  /// OAuth consent: the list permission and that the client's provider receives the list (legal review H-17)
  ///
  /// In de, this message translates to:
  /// **'Einträge deiner Einkaufsliste lesen. Kann auch Einträge hinzufügen, ändern, abhaken und löschen{listsStores, select, on{, Listen und Läden anlegen und umbenennen und die Reihenfolge in einem Laden festlegen} other{}}. {client} und sein Anbieter erhalten dabei die Inhalte eurer Liste.'**
  String consentListAccess(String client, String listsStores);

  /// No description provided for @scopeOpenid.
  ///
  /// In de, this message translates to:
  /// **'Deine Anmeldung bestätigen'**
  String get scopeOpenid;

  /// No description provided for @scopeEmail.
  ///
  /// In de, this message translates to:
  /// **'Deine E-Mail-Adresse'**
  String get scopeEmail;

  /// No description provided for @scopeProfile.
  ///
  /// In de, this message translates to:
  /// **'Dein Name und Profil'**
  String get scopeProfile;

  /// No description provided for @scopePhone.
  ///
  /// In de, this message translates to:
  /// **'Deine Telefonnummer'**
  String get scopePhone;

  /// No description provided for @scopeOfflineAccess.
  ///
  /// In de, this message translates to:
  /// **'Dauerhaft angemeldet bleiben'**
  String get scopeOfflineAccess;

  /// No description provided for @consentAllow.
  ///
  /// In de, this message translates to:
  /// **'Erlauben'**
  String get consentAllow;

  /// No description provided for @consentDeny.
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get consentDeny;

  /// Title of the MCP consent page once the user allowed; the browser then goes to the client
  ///
  /// In de, this message translates to:
  /// **'Verbunden'**
  String get consentConnectedTitle;

  /// No description provided for @consentDeclinedTitle.
  ///
  /// In de, this message translates to:
  /// **'Nicht verbunden'**
  String get consentDeclinedTitle;

  /// MCP consent page after Allow, while the client (e.g. Claude) finishes the connection on its side
  ///
  /// In de, this message translates to:
  /// **'Fertig, du kannst zu {client} zurückkehren.'**
  String consentDone(String client);

  /// No description provided for @consentDoneNoClient.
  ///
  /// In de, this message translates to:
  /// **'Fertig, du kannst zu deiner App zurückkehren.'**
  String get consentDoneNoClient;

  /// No description provided for @consentDeclined.
  ///
  /// In de, this message translates to:
  /// **'Abgelehnt, du kannst zu {client} zurückkehren.'**
  String consentDeclined(String client);

  /// No description provided for @consentInvalid.
  ///
  /// In de, this message translates to:
  /// **'Diese Anfrage ist ungültig oder abgelaufen. Starte die Verbindung in deiner App neu.'**
  String get consentInvalid;

  /// Title of the MCP consent page when the authorization is unknown or expired
  ///
  /// In de, this message translates to:
  /// **'Verbindung abgelaufen'**
  String get consentErrorTitle;

  /// Button on the failed MCP consent page
  ///
  /// In de, this message translates to:
  /// **'Zurück zur Liste'**
  String get consentBackToList;

  /// No description provided for @accessTitle.
  ///
  /// In de, this message translates to:
  /// **'Zugänge'**
  String get accessTitle;

  /// No description provided for @mcpServer.
  ///
  /// In de, this message translates to:
  /// **'MCP-Server'**
  String get mcpServer;

  /// No description provided for @mcpServerBody.
  ///
  /// In de, this message translates to:
  /// **'Für Claude, ChatGPT und andere KI-Assistenten. Verbinde per Anmeldung (OAuth) oder mit einem Zugriffsschlüssel.'**
  String get mcpServerBody;

  /// No description provided for @accessTokens.
  ///
  /// In de, this message translates to:
  /// **'Zugriffsschlüssel'**
  String get accessTokens;

  /// No description provided for @noTokens.
  ///
  /// In de, this message translates to:
  /// **'Kein aktiver Zugriffsschlüssel.'**
  String get noTokens;

  /// No description provided for @tokenHint.
  ///
  /// In de, this message translates to:
  /// **'…{hint}'**
  String tokenHint(String hint);

  /// No description provided for @createdOn.
  ///
  /// In de, this message translates to:
  /// **'Erstellt am {date}'**
  String createdOn(DateTime date);

  /// No description provided for @lastUsedOn.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt benutzt {date}'**
  String lastUsedOn(DateTime date);

  /// No description provided for @neverUsed.
  ///
  /// In de, this message translates to:
  /// **'Noch nie benutzt'**
  String get neverUsed;

  /// No description provided for @createToken.
  ///
  /// In de, this message translates to:
  /// **'Zugriffsschlüssel erstellen'**
  String get createToken;

  /// No description provided for @create.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get create;

  /// No description provided for @tokenName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get tokenName;

  /// No description provided for @tokenNameHint.
  ///
  /// In de, this message translates to:
  /// **'z. B. Claude oder Kurzbefehle'**
  String get tokenNameHint;

  /// No description provided for @tokenCreated.
  ///
  /// In de, this message translates to:
  /// **'Zugriffsschlüssel erstellt'**
  String get tokenCreated;

  /// No description provided for @tokenShownOnce.
  ///
  /// In de, this message translates to:
  /// **'Kopiere den Zugriffsschlüssel jetzt. Er wird nicht noch einmal angezeigt.'**
  String get tokenShownOnce;

  /// No description provided for @done.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get done;

  /// No description provided for @revokeToken.
  ///
  /// In de, this message translates to:
  /// **'{name} widerrufen'**
  String revokeToken(String name);

  /// No description provided for @revokeTokenTitle.
  ///
  /// In de, this message translates to:
  /// **'Zugriffsschlüssel widerrufen?'**
  String get revokeTokenTitle;

  /// No description provided for @revokeTokenBody.
  ///
  /// In de, this message translates to:
  /// **'Apps, die ihn benutzen, verlieren sofort den Zugriff.'**
  String get revokeTokenBody;

  /// No description provided for @revoke.
  ///
  /// In de, this message translates to:
  /// **'Widerrufen'**
  String get revoke;

  /// No description provided for @tooManyTokens.
  ///
  /// In de, this message translates to:
  /// **'Höchstens 20 aktive Zugriffsschlüssel.'**
  String get tooManyTokens;

  /// No description provided for @connectedApps.
  ///
  /// In de, this message translates to:
  /// **'Verbundene Apps'**
  String get connectedApps;

  /// No description provided for @noConnectedApps.
  ///
  /// In de, this message translates to:
  /// **'Noch keine App verbunden.'**
  String get noConnectedApps;

  /// No description provided for @siriHeader.
  ///
  /// In de, this message translates to:
  /// **'Siri'**
  String get siriHeader;

  /// No description provided for @siriThisIphone.
  ///
  /// In de, this message translates to:
  /// **'Siri (dieses iPhone)'**
  String get siriThisIphone;

  /// No description provided for @siriOtherIphone.
  ///
  /// In de, this message translates to:
  /// **'Siri (anderes iPhone)'**
  String get siriOtherIphone;

  /// Zugänge, Siri card on this iPhone (job 80): one example sentence, no hint that Siri ever needed setting up
  ///
  /// In de, this message translates to:
  /// **'Sag zum Beispiel: „Hey Siri, etwas auf Snacklist setzen“.'**
  String get siriSayHint;

  /// No description provided for @siriShowPhrases.
  ///
  /// In de, this message translates to:
  /// **'Siri-Sätze anzeigen'**
  String get siriShowPhrases;

  /// No description provided for @siriOldShortcutHint.
  ///
  /// In de, this message translates to:
  /// **'Den alten Kurzbefehl brauchst du nicht mehr. Seinen Zugriffsschlüssel „{name}“ kannst du unten löschen.'**
  String siriOldShortcutHint(String name);

  /// No description provided for @siriPhrasesTitle.
  ///
  /// In de, this message translates to:
  /// **'Siri-Sätze'**
  String get siriPhrasesTitle;

  /// No description provided for @siriPhrasesEnglish.
  ///
  /// In de, this message translates to:
  /// **'Auf Englisch'**
  String get siriPhrasesEnglish;

  /// No description provided for @siriPhrasesGerman.
  ///
  /// In de, this message translates to:
  /// **'Auf Deutsch'**
  String get siriPhrasesGerman;

  /// No description provided for @siriPhrase.
  ///
  /// In de, this message translates to:
  /// **'„{phrase}“'**
  String siriPhrase(String phrase);

  /// No description provided for @revokeSiriTitle.
  ///
  /// In de, this message translates to:
  /// **'Siri-Zugang widerrufen?'**
  String get revokeSiriTitle;

  /// No description provided for @revokeSiriBody.
  ///
  /// In de, this message translates to:
  /// **'Siri kann auf dem iPhone dann nichts mehr hinzufügen. Beim nächsten Start von Snacklist dort wird Siri neu eingerichtet.'**
  String get revokeSiriBody;

  /// No description provided for @connectedOn.
  ///
  /// In de, this message translates to:
  /// **'Verbunden am {date}'**
  String connectedOn(DateTime date);

  /// No description provided for @disconnect.
  ///
  /// In de, this message translates to:
  /// **'Trennen'**
  String get disconnect;

  /// No description provided for @disconnectApp.
  ///
  /// In de, this message translates to:
  /// **'{name} trennen'**
  String disconnectApp(String name);

  /// No description provided for @disconnectTitle.
  ///
  /// In de, this message translates to:
  /// **'{name} trennen?'**
  String disconnectTitle(String name);

  /// No description provided for @disconnectBody.
  ///
  /// In de, this message translates to:
  /// **'Die App verliert sofort den Zugriff auf deine Liste.'**
  String get disconnectBody;

  /// No description provided for @categoriesHint.
  ///
  /// In de, this message translates to:
  /// **'In dieser Reihenfolge stehen die Kategorien unter „Ohne Laden“ und bei Läden ohne eigene Reihenfolge. Tippe auf eine Kategorie, um sie umzubenennen.'**
  String get categoriesHint;

  /// No description provided for @categoryName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get categoryName;

  /// No description provided for @renameCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie umbenennen'**
  String get renameCategory;

  /// No description provided for @addCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie hinzufügen'**
  String get addCategory;

  /// No description provided for @deleteCategory.
  ///
  /// In de, this message translates to:
  /// **'{name} löschen'**
  String deleteCategory(String name);

  /// No description provided for @moveItemsTo.
  ///
  /// In de, this message translates to:
  /// **'Artikel verschieben nach'**
  String get moveItemsTo;

  /// No description provided for @dragCategory.
  ///
  /// In de, this message translates to:
  /// **'{name} verschieben'**
  String dragCategory(String name);

  /// No description provided for @categoryPosition.
  ///
  /// In de, this message translates to:
  /// **'{position} von {count}'**
  String categoryPosition(int position, int count);

  /// No description provided for @categoryNameTaken.
  ///
  /// In de, this message translates to:
  /// **'Eine Kategorie „{name}“ gibt es schon.'**
  String categoryNameTaken(String name);

  /// No description provided for @catalogSaveFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Änderung konnte nicht gespeichert werden.'**
  String get catalogSaveFailed;

  /// No description provided for @tooManyLists.
  ///
  /// In de, this message translates to:
  /// **'Hier passen höchstens 50 Listen rein.'**
  String get tooManyLists;

  /// No description provided for @storeLayoutHint.
  ///
  /// In de, this message translates to:
  /// **'Ordne die Kategorien so, wie du durch den Laden gehst. Tippe auf eine Kategorie, um sie umzubenennen.'**
  String get storeLayoutHint;

  /// No description provided for @newItemsFrom.
  ///
  /// In de, this message translates to:
  /// **'{count} neu von {name}'**
  String newItemsFrom(int count, String name);

  /// No description provided for @newItems.
  ///
  /// In de, this message translates to:
  /// **'{count} neu'**
  String newItems(int count);

  /// No description provided for @newItem.
  ///
  /// In de, this message translates to:
  /// **'Neu'**
  String get newItem;

  /// No description provided for @storeSectionLabel.
  ///
  /// In de, this message translates to:
  /// **'{store}, {count, plural, =1{1 Artikel} other{{count} Artikel}}'**
  String storeSectionLabel(String store, int count);

  /// No description provided for @itemsWord.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Artikel} other{Artikel}}'**
  String itemsWord(int count);

  /// No description provided for @expandSection.
  ///
  /// In de, this message translates to:
  /// **'Aufklappen'**
  String get expandSection;

  /// No description provided for @collapseSection.
  ///
  /// In de, this message translates to:
  /// **'Zuklappen'**
  String get collapseSection;

  /// No description provided for @listHint.
  ///
  /// In de, this message translates to:
  /// **'Tippen hakt ab · Halten bearbeitet. Vertippt? Unten unter „Zuletzt verwendet“ zurückholen.'**
  String get listHint;

  /// No description provided for @reorderNeedsConnection.
  ///
  /// In de, this message translates to:
  /// **'Die Reihenfolge lässt sich nur mit Verbindung ändern.'**
  String get reorderNeedsConnection;

  /// No description provided for @suggestion.
  ///
  /// In de, this message translates to:
  /// **'Vorschlag: {label}'**
  String suggestion(String label);

  /// No description provided for @dueSuggestions.
  ///
  /// In de, this message translates to:
  /// **'Brauchen wir wieder?'**
  String get dueSuggestions;

  /// Settings section header and list menu entry for account export and deletion.
  ///
  /// In de, this message translates to:
  /// **'Konto'**
  String get account;

  /// No description provided for @accountExport.
  ///
  /// In de, this message translates to:
  /// **'Meine Daten exportieren'**
  String get accountExport;

  /// No description provided for @accountExportBody.
  ///
  /// In de, this message translates to:
  /// **'Alles, was über dich gespeichert ist, als JSON-Datei.'**
  String get accountExportBody;

  /// No description provided for @accountDelete.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get accountDelete;

  /// No description provided for @accountDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen?'**
  String get accountDeleteTitle;

  /// No description provided for @accountDeleteWhat.
  ///
  /// In de, this message translates to:
  /// **'Dein Konto, dein Profil, deine Zugriffsschlüssel und deine verbundenen Apps werden endgültig gelöscht. Das lässt sich nicht rückgängig machen.'**
  String get accountDeleteWhat;

  /// No description provided for @accountDeleteKept.
  ///
  /// In de, this message translates to:
  /// **'Der Haushalt „{household}“ bleibt für {names} mit der ganzen Liste erhalten. Deine Einträge bleiben dort, aber ohne deinen Namen.'**
  String accountDeleteKept(String household, String names);

  /// No description provided for @accountDeleteKeptUnnamed.
  ///
  /// In de, this message translates to:
  /// **'Der Haushalt „{household}“ bleibt für die anderen Mitglieder mit der ganzen Liste erhalten. Deine Einträge bleiben dort, aber ohne deinen Namen.'**
  String accountDeleteKeptUnnamed(String household);

  /// Joins the last two names of a list, e.g. 'Lea und Max'.
  ///
  /// In de, this message translates to:
  /// **'{first} und {last}'**
  String namesAnd(String first, String last);

  /// No description provided for @accountDeleteDeleted.
  ///
  /// In de, this message translates to:
  /// **'Du bist das letzte Mitglied. Deshalb wird der Haushalt „{household}“ mit Liste, Verlauf, Kategorien und Läden gelöscht.'**
  String accountDeleteDeleted(String household);

  /// No description provided for @accountDeleteNone.
  ///
  /// In de, this message translates to:
  /// **'Du bist in keinem Haushalt, geteilte Daten gibt es nicht.'**
  String get accountDeleteNone;

  /// No description provided for @accountDeleteExportHint.
  ///
  /// In de, this message translates to:
  /// **'Mit „Meine Daten exportieren“ unter Konto kannst du vorher eine Kopie sichern.'**
  String get accountDeleteExportHint;

  /// Account deletion: the deleting account has Snacklist Premium itself (Legal N-362)
  ///
  /// In de, this message translates to:
  /// **'Du hast Snacklist Premium. Es gehört zu deinem Konto und endet, wenn du es löschst. Hast du ein Jahresabo, rechnen Apple bzw. Google weiter ab: Kündige es vorher im App Store oder bei Google Play.'**
  String get accountDeletePremium;

  /// names: quoted and joined, like „Ferien“ und „Büro“
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Dein archivierter Haushalt {names} wird mit deinem Konto gelöscht.} other{Deine archivierten Haushalte {names} werden mit deinem Konto gelöscht.}}'**
  String accountDeleteArchived(int count, String names);

  /// A household name inside a sentence
  ///
  /// In de, this message translates to:
  /// **'„{name}“'**
  String quotedName(String name);

  /// No description provided for @accountDeletePremiumAck.
  ///
  /// In de, this message translates to:
  /// **'Ich weiß: Premium endet. Ich bekomme mein Geld nicht von selbst zurück.'**
  String get accountDeletePremiumAck;

  /// No description provided for @accountDeleteConfirmLabel.
  ///
  /// In de, this message translates to:
  /// **'Zum Bestätigen LÖSCHEN eingeben'**
  String get accountDeleteConfirmLabel;

  /// No description provided for @accountDeleteConfirm.
  ///
  /// In de, this message translates to:
  /// **'Endgültig löschen'**
  String get accountDeleteConfirm;

  /// No description provided for @accountDeleteOffline.
  ///
  /// In de, this message translates to:
  /// **'Keine Internetverbindung. Dein Konto wurde nicht gelöscht. Versuche es erneut, sobald du online bist.'**
  String get accountDeleteOffline;

  /// No description provided for @accountDeleteFailed.
  ///
  /// In de, this message translates to:
  /// **'Löschen fehlgeschlagen ({code}). Dein Konto wurde nicht gelöscht.'**
  String accountDeleteFailed(String code);

  /// No description provided for @accountDeleteCanceled.
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen. Dein Konto wurde nicht gelöscht.'**
  String get accountDeleteCanceled;

  /// No description provided for @accountFateOffline.
  ///
  /// In de, this message translates to:
  /// **'Keine Internetverbindung. Was mit deinem Haushalt passiert, konnte nicht geladen werden.'**
  String get accountFateOffline;

  /// No description provided for @accountFateFailed.
  ///
  /// In de, this message translates to:
  /// **'Was mit deinem Haushalt passiert, konnte nicht geladen werden ({code}).'**
  String accountFateFailed(String code);

  /// No description provided for @accountDeletedNotice.
  ///
  /// In de, this message translates to:
  /// **'Dein Konto wurde gelöscht.'**
  String get accountDeletedNotice;

  /// No description provided for @accountDeletedApple.
  ///
  /// In de, this message translates to:
  /// **'Falls du dich mit Apple angemeldet hattest: Entferne „Snacklist“ auf deinem iPhone unter Einstellungen › [dein Name] › Anmelden & Sicherheit › Mit Apple anmelden.'**
  String get accountDeletedApple;

  /// No description provided for @exportDone.
  ///
  /// In de, this message translates to:
  /// **'Daten exportiert'**
  String get exportDone;

  /// No description provided for @exportDoneAt.
  ///
  /// In de, this message translates to:
  /// **'Daten exportiert: {path}'**
  String exportDoneAt(String path);

  /// No description provided for @exportOffline.
  ///
  /// In de, this message translates to:
  /// **'Keine Internetverbindung. Deine Daten wurden nicht exportiert.'**
  String get exportOffline;

  /// No description provided for @exportFailed.
  ///
  /// In de, this message translates to:
  /// **'Export fehlgeschlagen ({code}).'**
  String exportFailed(String code);

  /// The List tab
  ///
  /// In de, this message translates to:
  /// **'Liste'**
  String get tabList;

  /// The More tab: settings, sign-out, legal
  ///
  /// In de, this message translates to:
  /// **'Mehr'**
  String get tabMore;

  /// Under the open add sheet, where the tabs were
  ///
  /// In de, this message translates to:
  /// **'Antippen fügt hinzu · ↵ nimmt den ersten Vorschlag'**
  String get addSheetHint;

  /// Screen-reader name of the add sheet's store chip while Snacklist picks the store and knows none yet
  ///
  /// In de, this message translates to:
  /// **'Laden: automatisch'**
  String get storeAuto;

  /// The add sheet's store chip while Snacklist picks the store and knows none yet; next to the automatic mark
  ///
  /// In de, this message translates to:
  /// **'Laden'**
  String get chipStoreShort;

  /// The add sheet's category chip while Snacklist picks the category and knows none yet; next to the automatic mark
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get chipCategoryShort;

  /// Screen-reader name of the add sheet's store chip showing the store Snacklist picked
  ///
  /// In de, this message translates to:
  /// **'Laden: automatisch, {name}'**
  String storeAutoValue(String name);

  /// Screen-reader name of the add sheet's category chip showing the category Snacklist picked
  ///
  /// In de, this message translates to:
  /// **'Kategorie: automatisch, {name}'**
  String categoryAutoValue(String name);

  /// The add sheet with nothing typed and nothing due
  ///
  /// In de, this message translates to:
  /// **'Tippe, um Vorschläge zu sehen'**
  String get typeToSuggest;

  /// Source of the first add suggestion
  ///
  /// In de, this message translates to:
  /// **'Wie getippt'**
  String get suggestionTyped;

  /// Source label of an add suggestion
  ///
  /// In de, this message translates to:
  /// **'Schon mal gekauft'**
  String get suggestionHistory;

  /// Source label of an add suggestion
  ///
  /// In de, this message translates to:
  /// **'Andere Packung'**
  String get suggestionPack;

  /// Source label of an add suggestion
  ///
  /// In de, this message translates to:
  /// **'Andere Sorte'**
  String get suggestionVariant;

  /// Source label of an add suggestion
  ///
  /// In de, this message translates to:
  /// **'Andere Größe'**
  String get suggestionSize;

  /// Source label of an add suggestion
  ///
  /// In de, this message translates to:
  /// **'Andere Marke'**
  String get suggestionBrand;

  /// Source label of an add suggestion
  ///
  /// In de, this message translates to:
  /// **'Aus dem Katalog'**
  String get suggestionCatalog;

  /// Source label of a due usual in the add sheet
  ///
  /// In de, this message translates to:
  /// **'Wieder fällig'**
  String get suggestionDue;

  /// Source label of an item used in the last 30 days, shown in the add sheet before anything is typed
  ///
  /// In de, this message translates to:
  /// **'Zuletzt verwendet'**
  String get suggestionRecent;

  /// The add sheet's note after an add
  ///
  /// In de, this message translates to:
  /// **'Hinzugefügt: {name} → {store}'**
  String addedTo(String name, String store);

  /// The add sheet's note after an add without a store
  ///
  /// In de, this message translates to:
  /// **'Hinzugefügt: {name}'**
  String addedItem(String name);

  /// Clears the add field
  ///
  /// In de, this message translates to:
  /// **'Eingabe leeren'**
  String get clearInput;

  /// Open items, under the list title
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Artikel} other{{count} Artikel}}'**
  String listItemCount(int count);

  /// More: section
  ///
  /// In de, this message translates to:
  /// **'Haushalt'**
  String get household;

  /// More: the stores screen
  ///
  /// In de, this message translates to:
  /// **'Läden'**
  String get storesTitle;

  /// List tab header: opens the stores and categories (job 78)
  ///
  /// In de, this message translates to:
  /// **'Anpassen'**
  String get listEdit;

  /// Stores screen: under the pinned Ohne Laden row
  ///
  /// In de, this message translates to:
  /// **'Kategorien für Artikel ohne Laden'**
  String get noStoreRowHint;

  /// Stores screen: the add button and its dialog
  ///
  /// In de, this message translates to:
  /// **'Laden hinzufügen'**
  String get storeAdd;

  /// Delete category dialog: categories belong to the whole household
  ///
  /// In de, this message translates to:
  /// **'Sie verschwindet aus allen Läden.'**
  String get deleteCategoryEverywhere;

  /// Stores screen hint
  ///
  /// In de, this message translates to:
  /// **'Ziehe die Läden in die Reihenfolge, in der sie auf der Liste stehen. Tippe auf einen Laden, um ihn umzubenennen und seine Kategorien zu ordnen.'**
  String get storesHint;

  /// Drag handle of a store
  ///
  /// In de, this message translates to:
  /// **'{store} verschieben'**
  String dragStore(String store);

  /// + row in the store picker and on the stores screen
  ///
  /// In de, this message translates to:
  /// **'Neuer Laden'**
  String get storeNew;

  /// a11y label of the + row
  ///
  /// In de, this message translates to:
  /// **'Neuen Laden anlegen'**
  String get storeNewLabel;

  /// the inline new-store or rename field
  ///
  /// In de, this message translates to:
  /// **'Name des Ladens'**
  String get storeNameHint;

  /// check button of the inline new-store field
  ///
  /// In de, this message translates to:
  /// **'Laden anlegen'**
  String get storeCreateConfirm;

  /// screen-reader announcement after create-and-select in the store picker
  ///
  /// In de, this message translates to:
  /// **'{store} angelegt und ausgewählt'**
  String storeAddedAndSelected(String store);

  /// screen-reader announcement after adding a store on the stores screen
  ///
  /// In de, this message translates to:
  /// **'{store} angelegt'**
  String storeAdded(String store);

  /// search field on top of the store picker
  ///
  /// In de, this message translates to:
  /// **'Läden durchsuchen'**
  String get storeSearch;

  /// rename action of a store
  ///
  /// In de, this message translates to:
  /// **'{store} umbenennen'**
  String storeRename(String store);

  /// delete action of a store
  ///
  /// In de, this message translates to:
  /// **'{store} löschen'**
  String storeDelete(String store);

  /// delete confirmation title
  ///
  /// In de, this message translates to:
  /// **'{store} löschen?'**
  String storeDeleteTitle(String store);

  /// adding a store, or renaming one, onto a name the household has (any case)
  ///
  /// In de, this message translates to:
  /// **'Einen Laden „{name}“ gibt es schon.'**
  String storeNameTaken(String name);

  /// store add/rename/delete while offline
  ///
  /// In de, this message translates to:
  /// **'Läden lassen sich nur mit Verbindung anlegen, umbenennen oder löschen.'**
  String get storesNeedConnection;

  /// stores screen of a household without stores
  ///
  /// In de, this message translates to:
  /// **'Noch keine Läden. Leg einen an, dann sortiert die Liste deine Artikel nach seinem Laufweg.'**
  String get storesEmpty;

  /// delete confirmation: how many open items lose their store
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{In diesem Laden sind keine offenen Artikel.} =1{1 offener Artikel kommt zu „Ohne Laden“.} other{{count} offene Artikel kommen zu „Ohne Laden“.}} Sein Laufweg geht mit.'**
  String storeDeleteBody(int count);

  /// More: the settings page (theme, language)
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// Settings: section with the theme segments (system, light, dark); also names the group
  ///
  /// In de, this message translates to:
  /// **'Darstellung'**
  String get appearance;

  /// Settings: theme segment, the app follows the device's light or dark setting
  ///
  /// In de, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// Settings: theme segment, always light
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get themeLight;

  /// Settings: theme segment, always dark
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get themeDark;

  /// Settings: section, row and page title
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get language;

  /// Language option: follow the device
  ///
  /// In de, this message translates to:
  /// **'Wie Gerät'**
  String get languageSystem;

  /// Under the device option: the language the device gives now, in its own name
  ///
  /// In de, this message translates to:
  /// **'Gerade {language}'**
  String languageSystemNow(String language);

  /// Settings: the language row while it follows the device
  ///
  /// In de, this message translates to:
  /// **'Wie Gerät ({language})'**
  String languageSystemPicked(String language);

  /// More: legal notice
  ///
  /// In de, this message translates to:
  /// **'Impressum'**
  String get imprint;

  /// The sign-in footer: link to the privacy policy
  ///
  /// In de, this message translates to:
  /// **'Datenschutz'**
  String get privacy;

  /// More: open-source licenses
  ///
  /// In de, this message translates to:
  /// **'Lizenzen'**
  String get licenses;

  /// More, the legal rows: the link to the privacy policy on the site
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung'**
  String get privacyPolicy;

  /// More: update card title when an over-the-air patch is downloaded (no update check yet, job 85)
  ///
  /// In de, this message translates to:
  /// **'Update bereit'**
  String get updatePatchTitle;

  /// More: update card body, patch downloaded
  ///
  /// In de, this message translates to:
  /// **'Snacklist hat Verbesserungen geladen. Starte die App neu, um sie zu nutzen.'**
  String get updatePatchBody;

  /// More: update card button, patch downloaded
  ///
  /// In de, this message translates to:
  /// **'Neu starten'**
  String get updatePatchAction;

  /// More: update card title when the store has a newer version
  ///
  /// In de, this message translates to:
  /// **'Neue Version da'**
  String get updateStoreTitle;

  /// More: update card body, newer store version
  ///
  /// In de, this message translates to:
  /// **'Version {version} ist im Store. Aktualisiere, um alles Neue zu bekommen.'**
  String updateStoreBody(String version);

  /// More: update card button, opens the store
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get updateStoreAction;

  /// More: tooltip of the update card close button
  ///
  /// In de, this message translates to:
  /// **'Später'**
  String get updateLater;

  /// More: bottom line
  ///
  /// In de, this message translates to:
  /// **'Version {version}'**
  String appVersion(String version);

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'Obst & Gemüse'**
  String get categoryProduce;

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'Brot & Backwaren'**
  String get categoryBakery;

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'Kühlregal'**
  String get categoryChilled;

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'Fleisch/Wurst/Fisch'**
  String get categoryMeat;

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'Vorrat & Konserven'**
  String get categoryPantry;

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'Süßes & Snacks'**
  String get categorySweets;

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'Getränke'**
  String get categoryDrinks;

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'Tiefkühl'**
  String get categoryFrozen;

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'Haushalt'**
  String get categoryHousehold;

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'👶 Drogerie'**
  String get categoryDrugstore;

  /// Seeded Baumarkt category, exactly as public.hardware_categories names it in German
  ///
  /// In de, this message translates to:
  /// **'Farben & Lacke'**
  String get categoryPaint;

  /// Seeded Baumarkt category, exactly as public.hardware_categories names it in German
  ///
  /// In de, this message translates to:
  /// **'Sanitär'**
  String get categoryPlumbing;

  /// Seeded Baumarkt category, exactly as public.hardware_categories names it in German
  ///
  /// In de, this message translates to:
  /// **'Elektro & Leuchtmittel'**
  String get categoryElectrical;

  /// Seeded Baumarkt category, exactly as public.hardware_categories names it in German
  ///
  /// In de, this message translates to:
  /// **'Werkzeug'**
  String get categoryTools;

  /// Seeded Baumarkt category, exactly as public.hardware_categories names it in German
  ///
  /// In de, this message translates to:
  /// **'Schrauben & Befestigung'**
  String get categoryFasteners;

  /// Seeded Baumarkt category, exactly as public.hardware_categories names it in German
  ///
  /// In de, this message translates to:
  /// **'Holz & Baustoffe'**
  String get categoryBuilding;

  /// Seeded Baumarkt category, exactly as public.hardware_categories names it in German
  ///
  /// In de, this message translates to:
  /// **'Garten & Pflanzen'**
  String get categoryGarden;

  /// Seeded category, exactly as public.seed_household names it in German
  ///
  /// In de, this message translates to:
  /// **'Sonstiges'**
  String get categoryOther;

  /// Analytics consent screen after the first sign-in: title. approved by Peter 2026-10-30 (legal review H-03)
  ///
  /// In de, this message translates to:
  /// **'Darf Snacklist Nutzungsdaten erfassen?'**
  String get analyticsConsentTitle;

  /// Analytics consent screen: who asks, why, what is stored and sent and what never is, how to withdraw. Ends right before analyticsConsentPrivacyLink, which follows after a space and is closed by a full stop. Version 2026-11-18 (consentTextVersion, docs/consent/2026-11-18.md): changing it needs a new version. Approved by Peter 2026-11-01 (Legal 12:55); 2026-11-10 swaps only the name (job 174); 2026-11-11 names examples of the usage data (job 178, Legal N-125), wording approved by Peter 2026-11-11 with PR #363; 2026-11-14 also names Siri (Legal N-146: the server sends siri_add and siri_read); 2026-11-18 also names connected apps, MCP and API keys, Legal's verbatim N-251 (the server sends api_key_used, N-147b)
  ///
  /// In de, this message translates to:
  /// **'Snacklist (Anbieter: Peter Trost) möchte verstehen, welche Funktionen genutzt werden, Fehler finden, messen, ob sich Snacklist trägt, und neue Funktionen schrittweise freischalten. Dafür speichert Snacklist eine zufällige Kennung auf diesem Gerät und sendet damit pseudonyme Nutzungsdaten (etwa zu Einträgen, Haushalten und der Einrichtung, welche Tipps du siehst und wie du Siri, verbundene Apps und KI-Assistenten über MCP und API-Schlüssel nutzt), Fehlerberichte, die Kennung deines Haushalts und technische Angaben zu Gerät oder Browser an unseren Dienstleister PostHog (Server in der EU). Listeninhalte, Namen und E-Mail-Adressen werden nie gesendet. Du kannst jederzeit unter Mehr → Nutzungsdaten widerrufen. Mehr in der'**
  String get analyticsConsentBody;

  /// Analytics consent screen: the link to the privacy policy that ends analyticsConsentBody. approved by Peter 2026-10-30 (legal review H-03)
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung'**
  String get analyticsConsentPrivacyLink;

  /// Analytics consent: allow; as prominent as decline, nothing pre-selected. approved by Peter 2026-11-01 (Legal 12:45)
  ///
  /// In de, this message translates to:
  /// **'Erlauben'**
  String get analyticsAccept;

  /// Analytics consent: don't allow; as prominent as allow. approved by Peter 2026-11-01 (Legal 12:45)
  ///
  /// In de, this message translates to:
  /// **'Nicht erlauben'**
  String get analyticsDecline;

  /// More: the row and page with the usage-data switch; the consent text and privacy policy name this path (Mehr → Nutzungsdaten)
  ///
  /// In de, this message translates to:
  /// **'Nutzungsdaten'**
  String get analyticsSection;

  /// More: analytics switch. approved by Peter 2026-10-30 (legal review H-03)
  ///
  /// In de, this message translates to:
  /// **'Nutzungsdaten und Fehlerberichte senden'**
  String get analyticsToggle;

  /// More: below the analytics switch. Turning it off deletes the install id. approved by Peter 2026-10-30 (legal review H-03); shortened by Legal N-298 (2026-11-19, job 317) once switching on asks the consent question first
  ///
  /// In de, this message translates to:
  /// **'Gilt für dieses Gerät. Ausschalten löscht die Kennung auf diesem Gerät.'**
  String get analyticsToggleHint;

  /// More, debug builds and the tester group internal only: copies the analytics install id, so a PostHog feature flag can be turned on for this one install (job 190)
  ///
  /// In de, this message translates to:
  /// **'Installations-ID kopieren: {id}'**
  String copyInstallId(String id);

  /// More, debug builds and the tester group internal only: raises a test exception for error tracking
  ///
  /// In de, this message translates to:
  /// **'Testfehler senden'**
  String get sendTestError;

  /// More: opens the feedback form; also the form's title
  ///
  /// In de, this message translates to:
  /// **'Feedback senden'**
  String get feedbackRow;

  /// More: opens Snacklist's page in the App Store or Google Play, to rate it
  ///
  /// In de, this message translates to:
  /// **'Snacklist bewerten'**
  String get rateApp;

  /// More: opens the help and contact page on snacklist.app in the browser
  ///
  /// In de, this message translates to:
  /// **'Hilfe & Kontakt'**
  String get helpRow;

  /// Feedback form: label of the text field
  ///
  /// In de, this message translates to:
  /// **'Deine Nachricht'**
  String get feedbackMessage;

  /// Feedback form: hint in the empty text field
  ///
  /// In de, this message translates to:
  /// **'Was ist dir aufgefallen?'**
  String get feedbackMessageHint;

  /// Feedback form: category chip
  ///
  /// In de, this message translates to:
  /// **'Bug'**
  String get feedbackCategoryBug;

  /// Feedback form: category chip
  ///
  /// In de, this message translates to:
  /// **'Idee'**
  String get feedbackCategoryIdea;

  /// Feedback form: category chip
  ///
  /// In de, this message translates to:
  /// **'Sonstiges'**
  String get feedbackCategoryOther;

  /// Feedback form: label above the category chips
  ///
  /// In de, this message translates to:
  /// **'Art (optional)'**
  String get feedbackCategories;

  /// Feedback form: checkbox, off by default
  ///
  /// In de, this message translates to:
  /// **'Snacklist Support darf mich dazu kontaktieren'**
  String get feedbackContact;

  /// Feedback form: what is sent along with the note
  ///
  /// In de, this message translates to:
  /// **'App-Version, Gerät und Sprache. Keine Listeneinträge.'**
  String get feedbackAttached;

  /// Feedback form: before the attached line
  ///
  /// In de, this message translates to:
  /// **'Wird mitgeschickt:'**
  String get feedbackAttachedTitle;

  /// Feedback form: send button
  ///
  /// In de, this message translates to:
  /// **'Senden'**
  String get feedbackSend;

  /// Feedback form: button after a failed send
  ///
  /// In de, this message translates to:
  /// **'Erneut senden'**
  String get feedbackRetry;

  /// Feedback form: while the note is on its way (screen readers)
  ///
  /// In de, this message translates to:
  /// **'Wird gesendet …'**
  String get feedbackSending;

  /// Snackbar after the note arrived
  ///
  /// In de, this message translates to:
  /// **'Danke!'**
  String get feedbackThanks;

  /// Feedback form: error after a failed send; text, category and checkbox stay
  ///
  /// In de, this message translates to:
  /// **'Nicht gesendet. Prüfe die Verbindung und versuch es noch einmal.'**
  String get feedbackFailed;

  /// Job 267 (flag feedback-fb2): Feedback form, error when storage turned the screenshot down (a daily or overall limit, its size or type); switching the screenshot off sends the note
  ///
  /// In de, this message translates to:
  /// **'Das Bildschirmfoto wurde nicht angenommen. Schalte es aus, dann geht deine Nachricht ohne Bild.'**
  String get feedbackScreenshotRefused;

  /// Feedback form: the note is too long
  ///
  /// In de, this message translates to:
  /// **'Höchstens {max} Zeichen'**
  String feedbackTooLong(int max);

  /// Feedback form: characters used, shown near the limit
  ///
  /// In de, this message translates to:
  /// **'{count} / {max}'**
  String feedbackCounter(int count, int max);

  /// Feedback form: close button
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get feedbackClose;

  /// Feedback form with the feedback-fb2 flag (job 267), while a screenshot is attached and switched on: the facts always sent, without "no list items" (the screenshot can show some); screen name and screenshot follow as switches
  ///
  /// In de, this message translates to:
  /// **'App-Version, Gerät und Sprache.'**
  String get feedbackAttachedBasics;

  /// Feedback form opened by shaking (job 267): switch that sends the name of the screen (only its name, no picture); the name follows on the next line
  ///
  /// In de, this message translates to:
  /// **'Bildschirmname'**
  String get feedbackScreenName;

  /// Feedback form (job 267): switch that sends the marked-up screenshot shown below it
  ///
  /// In de, this message translates to:
  /// **'Bildschirmfoto'**
  String get feedbackScreenshot;

  /// Feedback form (job 267): under the screenshot switch; the screenshot is not redacted automatically
  ///
  /// In de, this message translates to:
  /// **'Zeigt alles, was auf dem Bildschirm war, auch Einträge und Namen aus deinem Haushalt. Verdecke vorher, was wir nicht sehen sollen.'**
  String get feedbackScreenshotNote;

  /// Feedback form (job 267): screen-reader label of the screenshot preview
  ///
  /// In de, this message translates to:
  /// **'Vorschau des Bildschirmfotos'**
  String get feedbackScreenshotPreview;

  /// Feedback form from More (job 267): marks up the screen shown before More and attaches it
  ///
  /// In de, this message translates to:
  /// **'Bildschirmfoto hinzufügen'**
  String get feedbackAddScreenshot;

  /// Bottom sheet after shaking the phone (job 267): title
  ///
  /// In de, this message translates to:
  /// **'Problem mit diesem Bildschirm melden?'**
  String get feedbackShakeTitle;

  /// Shake sheet (job 267): opens the screenshot to mark up, then the feedback form
  ///
  /// In de, this message translates to:
  /// **'Mit Bildschirmfoto'**
  String get feedbackShakeWithScreenshot;

  /// Shake sheet (job 267): opens the feedback form without a picture
  ///
  /// In de, this message translates to:
  /// **'Ohne Bildschirmfoto'**
  String get feedbackShakeWithout;

  /// Shake sheet (job 267): small line at the bottom, where the shake switch is
  ///
  /// In de, this message translates to:
  /// **'Schütteln ausschalten: Mehr › Einstellungen'**
  String get feedbackShakeOffHint;

  /// Screenshot markup (job 267): hint above the tools
  ///
  /// In de, this message translates to:
  /// **'Markiere, was nicht stimmt. Verdecke, was niemand sehen soll.'**
  String get feedbackAnnotateHint;

  /// Screenshot markup (job 267): free drawing tool
  ///
  /// In de, this message translates to:
  /// **'Stift'**
  String get feedbackToolPen;

  /// Screenshot markup (job 267): rectangle tool
  ///
  /// In de, this message translates to:
  /// **'Rechteck'**
  String get feedbackToolRectangle;

  /// Screenshot markup (job 267): text tool
  ///
  /// In de, this message translates to:
  /// **'Text'**
  String get feedbackToolText;

  /// Screenshot markup (job 290, Legal C1): tool that paints a filled, opaque box over what nobody should see; flattened into the PNG before upload
  ///
  /// In de, this message translates to:
  /// **'Verdecken'**
  String get feedbackToolCover;

  /// Screenshot markup (job 267): screen-reader name of the pen / rectangle / text control
  ///
  /// In de, this message translates to:
  /// **'Werkzeug'**
  String get feedbackAnnotateTools;

  /// Screenshot markup (job 267): removes the last rectangle or text
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get feedbackAnnotateUndo;

  /// Screenshot markup (job 267): hint in the text placed on the screenshot
  ///
  /// In de, this message translates to:
  /// **'Text eingeben'**
  String get feedbackAnnotateTextHint;

  /// Screenshot markup (job 267): attaches the marked-up screenshot and opens the form
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get feedbackAnnotateDone;

  /// Settings (job 267): section label above the shake switch
  ///
  /// In de, this message translates to:
  /// **'Feedback'**
  String get settingsFeedback;

  /// Settings (job 267, iOS and Android): switch, on by default
  ///
  /// In de, this message translates to:
  /// **'Schütteln für Feedback'**
  String get shakeToFeedback;

  /// Settings (job 267): under the shake switch
  ///
  /// In de, this message translates to:
  /// **'Schüttle das Handy, um ein Problem mit dem Bildschirm zu melden.'**
  String get shakeToFeedbackHint;

  /// More (flag feedback-fb4, job 268): the row that opens Feedback & ideas; also that page's title
  ///
  /// In de, this message translates to:
  /// **'Feedback & Ideen'**
  String get feedbackHubRow;

  /// More (job 268): read with the Feedback & ideas row, for its badge: notes with a new reply or status since the user last opened them
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Neuigkeit} other{{count} Neuigkeiten}}'**
  String feedbackHubUnread(int count);

  /// Feedback & ideas (job 268): the button that opens the feedback form. Never a person's name
  ///
  /// In de, this message translates to:
  /// **'An Snacklist Support schreiben'**
  String get feedbackWrite;

  /// Feedback & ideas (job 268): section title above the user's own notes
  ///
  /// In de, this message translates to:
  /// **'Deine Notizen'**
  String get feedbackYourNotes;

  /// Feedback & ideas (job 268): shown while the user has sent no note
  ///
  /// In de, this message translates to:
  /// **'Noch keine Notizen. Was du schreibst, steht danach hier, mit Status und Antwort.'**
  String get feedbackNoNotes;

  /// Feedback & ideas (job 268): the notes did not load; a retry button follows
  ///
  /// In de, this message translates to:
  /// **'Konnte nicht geladen werden.'**
  String get feedbackLoadFailed;

  /// Feedback & ideas (job 268): status chip of a note nobody has opened yet
  ///
  /// In de, this message translates to:
  /// **'Gesendet'**
  String get feedbackStatusSent;

  /// Feedback & ideas (job 268): status chip of a note Snacklist Support has read
  ///
  /// In de, this message translates to:
  /// **'Gelesen'**
  String get feedbackStatusRead;

  /// Feedback & ideas (job 268): status chip of a planned note, and of a planned idea
  ///
  /// In de, this message translates to:
  /// **'Geplant'**
  String get feedbackStatusPlanned;

  /// Feedback & ideas (job 268): status chip of a note fixed in an app version
  ///
  /// In de, this message translates to:
  /// **'Behoben in {version}'**
  String feedbackStatusFixedIn(String version);

  /// Feedback & ideas (job 268): status chip of a fixed note without a version
  ///
  /// In de, this message translates to:
  /// **'Behoben'**
  String get feedbackStatusFixed;

  /// Feedback & ideas (job 268): marker on a note with a reply the user has not opened
  ///
  /// In de, this message translates to:
  /// **'Neue Antwort'**
  String get feedbackNewReply;

  /// Feedback & ideas (job 268): marker on a note whose status changed since the user opened it, without a reply
  ///
  /// In de, this message translates to:
  /// **'Neuer Status'**
  String get feedbackNewStatus;

  /// Feedback & ideas (job 268): section title above the listed ideas. Never a person's name
  ///
  /// In de, this message translates to:
  /// **'Ideen, die wir abwägen'**
  String get feedbackIdeas;

  /// Feedback & ideas (job 268): status of an idea that is still weighed
  ///
  /// In de, this message translates to:
  /// **'Wird überlegt'**
  String get feedbackIdeaConsidering;

  /// Feedback & ideas (job 268): screen reader label of an idea's +1 toggle: the idea and every household's +1s, never who gave them
  ///
  /// In de, this message translates to:
  /// **'{title}: +1, {count, plural, =1{1 Stimme} other{{count} Stimmen}}'**
  String feedbackVote(String title, int count);

  /// Feedback & ideas (job 268): under the ideas. Who voted moved to the privacy policy §10 (Legal N-300, 2026-11-19, job 317)
  ///
  /// In de, this message translates to:
  /// **'Ideen schreibt Snacklist Support.'**
  String get feedbackIdeasNote;

  /// Feedback & ideas (job 268): snackbar after a +1 the server refused or never got; the +1 is undone
  ///
  /// In de, this message translates to:
  /// **'Deine Stimme ist nicht angekommen. Versuch es noch einmal.'**
  String get feedbackVoteFailed;

  /// Feedback & ideas (job 268): title of one note's page
  ///
  /// In de, this message translates to:
  /// **'Deine Notiz'**
  String get feedbackNoteTitle;

  /// Feedback & ideas (job 268): when a note was written or answered
  ///
  /// In de, this message translates to:
  /// **'{date}, {time}'**
  String feedbackWhen(DateTime date, DateTime time);

  /// Feedback & ideas (job 268): under the user's own note once it was read. Never a person's name
  ///
  /// In de, this message translates to:
  /// **'{when} · gelesen'**
  String feedbackWhenRead(String when);

  /// Feedback & ideas (job 268): under a reply. Never a person's name
  ///
  /// In de, this message translates to:
  /// **'Snacklist Support · {when}'**
  String feedbackReplyFrom(String when);

  /// Feedback & ideas (job 268): link from a fixed note to the changelog entry of its version
  ///
  /// In de, this message translates to:
  /// **'Was ist neu in {version}'**
  String feedbackWhatsNew(String version);

  /// Feedback & ideas (job 268): a note's page for an id that is not among the user's notes
  ///
  /// In de, this message translates to:
  /// **'Diese Notiz gibt es nicht.'**
  String get feedbackNoteMissing;

  /// No description provided for @onboardingCreateHint.
  ///
  /// In de, this message translates to:
  /// **'Eine neue Liste, zu der du danach Leute einlädst.'**
  String get onboardingCreateHint;

  /// No description provided for @onboardingJoin.
  ///
  /// In de, this message translates to:
  /// **'Einladung annehmen'**
  String get onboardingJoin;

  /// No description provided for @onboardingJoinHint.
  ///
  /// In de, this message translates to:
  /// **'Du hast einen Link oder einen Code bekommen.'**
  String get onboardingJoinHint;

  /// No description provided for @householdNameInvalid.
  ///
  /// In de, this message translates to:
  /// **'Gib einen Namen mit 1 bis 80 Zeichen ein.'**
  String get householdNameInvalid;

  /// No description provided for @storesChoice.
  ///
  /// In de, this message translates to:
  /// **'Läden'**
  String get storesChoice;

  /// onboarding: hint above the store choices
  ///
  /// In de, this message translates to:
  /// **'Wähl die Läden, in denen ihr einkauft. In dieser Reihenfolge stehen sie in der Liste.'**
  String get onboardingStoresHint;

  /// onboarding: the row that opens a field for a store not in the list
  ///
  /// In de, this message translates to:
  /// **'Eigenen Laden hinzufügen'**
  String get storeAddOwn;

  /// The hardware store offered as a store to pick (onboarding, new household). Not a chain: the name the store gets.
  ///
  /// In de, this message translates to:
  /// **'Baumarkt'**
  String get storeHardware;

  /// No description provided for @skipStores.
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get skipStores;

  /// No description provided for @skipStoresHint.
  ///
  /// In de, this message translates to:
  /// **'Ohne Läden starten. Du kannst sie später unter Liste → Anpassen anlegen.'**
  String get skipStoresHint;

  /// No description provided for @householdOffline.
  ///
  /// In de, this message translates to:
  /// **'Keine Internetverbindung. Versuche es erneut, sobald du online bist.'**
  String get householdOffline;

  /// The server refused to archive a household (its archive switch is off); nothing changed
  ///
  /// In de, this message translates to:
  /// **'Archivieren ist gerade nicht möglich. Dein Haushalt bleibt, wie er ist.'**
  String get householdArchiveDisabled;

  /// No description provided for @tooManyAttempts.
  ///
  /// In de, this message translates to:
  /// **'Zu viele Versuche. Bitte später noch einmal.'**
  String get tooManyAttempts;

  /// No description provided for @inviteCheck.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get inviteCheck;

  /// No description provided for @invitePreview.
  ///
  /// In de, this message translates to:
  /// **'Einladung in den Haushalt'**
  String get invitePreview;

  /// No description provided for @invitePartnerBody.
  ///
  /// In de, this message translates to:
  /// **'Teile den Link oder den Code mit den Leuten, mit denen du einkaufst. Die Einladung gilt 7 Tage und für eine Person.'**
  String get invitePartnerBody;

  /// No description provided for @later.
  ///
  /// In de, this message translates to:
  /// **'Später'**
  String get later;

  /// No description provided for @toTheList.
  ///
  /// In de, this message translates to:
  /// **'Weiter zur Liste'**
  String get toTheList;

  /// Guided start (job 168b), first screen: tagline under the wordmark
  ///
  /// In de, this message translates to:
  /// **'Eure Einkaufsliste. Live auf jedem Handy.'**
  String get startTagline;

  /// Guided start, first screen: welcome line
  ///
  /// In de, this message translates to:
  /// **'Willkommen! In zwei Minuten steht eure gemeinsame Liste, mit allem, was gerade fehlt.'**
  String get startWelcome;

  /// Guided start, first screen: primary button that starts the setup
  ///
  /// In de, this message translates to:
  /// **'Los geht\'s'**
  String get startGo;

  /// Guided start, first screen: secondary button to the sign-in
  ///
  /// In de, this message translates to:
  /// **'Ich habe schon ein Konto'**
  String get startLogIn;

  /// Sign-in screen: link back to the guided start
  ///
  /// In de, this message translates to:
  /// **'Neu bei Snacklist? Los geht\'s'**
  String get loginNew;

  /// Sign-in screen for an invite, under the logo: why a joiner needs an account (job 356, flag joiner-direct-list). New joiner sign-in copy, pending Legal
  ///
  /// In de, this message translates to:
  /// **'Ein Konto brauchst du, damit die gemeinsame Liste mit dem Haushalt synchron bleibt, zu dem du eingeladen wurdest.'**
  String get joinerAccountWhy;

  /// Guided start: progress under the title
  ///
  /// In de, this message translates to:
  /// **'Schritt {step} von {count}'**
  String onboardingProgress(int step, int count);

  /// Guided start: back to the previous step
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get onboardingBack;

  /// Guided start: next step
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get onboardingNext;

  /// Guided start: skip this question
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get onboardingSkip;

  /// Guided start: tooltip of the X on every step
  ///
  /// In de, this message translates to:
  /// **'Einrichtung verlassen'**
  String get onboardingExit;

  /// Guided start, leave dialog: title
  ///
  /// In de, this message translates to:
  /// **'Einrichtung verlassen?'**
  String get onboardingExitTitle;

  /// Guided start, leave dialog: body
  ///
  /// In de, this message translates to:
  /// **'Was du bisher eingegeben hast, bleibt auf diesem Gerät gespeichert.'**
  String get onboardingExitBody;

  /// Guided start, leave dialog: go to the sign-in, keeping the progress
  ///
  /// In de, this message translates to:
  /// **'Stattdessen anmelden'**
  String get onboardingExitLogIn;

  /// Guided start, leave dialog: drop everything entered (asks again)
  ///
  /// In de, this message translates to:
  /// **'Fortschritt verwerfen'**
  String get onboardingExitDiscard;

  /// Guided start, leave dialog: close the dialog
  ///
  /// In de, this message translates to:
  /// **'Weiter einrichten'**
  String get onboardingExitStay;

  /// Guided start, step who: title
  ///
  /// In de, this message translates to:
  /// **'Mit wem kaufst du ein?'**
  String get whoTitle;

  /// Guided start, step who: body
  ///
  /// In de, this message translates to:
  /// **'Wähl alles, was passt. Danach richten sich Name, Einladung und deine ersten Tipps.'**
  String get whoBody;

  /// Household kind: a couple
  ///
  /// In de, this message translates to:
  /// **'Partner·in'**
  String get kindPartner;

  /// Household kind: a family
  ///
  /// In de, this message translates to:
  /// **'Familie'**
  String get kindFamily;

  /// Household kind: a shared flat
  ///
  /// In de, this message translates to:
  /// **'WG'**
  String get kindFlat;

  /// Household kind: a club, association or team
  ///
  /// In de, this message translates to:
  /// **'Verein oder Team'**
  String get kindClub;

  /// Household kind: the user alone
  ///
  /// In de, this message translates to:
  /// **'Nur ich'**
  String get kindSolo;

  /// Household kind: something else, with a text field
  ///
  /// In de, this message translates to:
  /// **'Andere'**
  String get kindOther;

  /// Guided start, step who: label of the field shown for Andere
  ///
  /// In de, this message translates to:
  /// **'Mit wem noch?'**
  String get whoOtherLabel;

  /// Guided start, step who: example in the Andere field
  ///
  /// In de, this message translates to:
  /// **'z. B. Nachbarn'**
  String get whoOtherHint;

  /// Guided start, step who: shown when several kinds are picked; first is the first pick's label
  ///
  /// In de, this message translates to:
  /// **'Wir starten mit „{first}“. Die anderen merken wir uns für später.'**
  String whoSeveral(String first);

  /// Guided start, step name: title
  ///
  /// In de, this message translates to:
  /// **'Wie soll euer Haushalt heißen?'**
  String get nameTitle;

  /// Guided start, step name: body
  ///
  /// In de, this message translates to:
  /// **'Den Namen sehen alle, die du einlädst. Du kannst ihn später ändern.'**
  String get nameBody;

  /// Suggested household name for a family
  ///
  /// In de, this message translates to:
  /// **'Unsere Familie'**
  String get householdNameFamily;

  /// Suggested household name for a shared flat
  ///
  /// In de, this message translates to:
  /// **'Unsere WG'**
  String get householdNameFlat;

  /// Suggested household name for a club or team
  ///
  /// In de, this message translates to:
  /// **'Unser Verein'**
  String get householdNameClub;

  /// Suggested household name for the user alone
  ///
  /// In de, this message translates to:
  /// **'Meine Liste'**
  String get householdNameSolo;

  /// Guided start, step stores: title
  ///
  /// In de, this message translates to:
  /// **'Wo kauft ihr ein?'**
  String get storesStepTitle;

  /// Guided start, step need: title
  ///
  /// In de, this message translates to:
  /// **'Was fehlt gerade?'**
  String get needTitle;

  /// Guided start, step need: body
  ///
  /// In de, this message translates to:
  /// **'Tipp an, was auf die Liste soll, oder schreib es unten hin.'**
  String get needBody;

  /// Guided start, step need: the staple chips, comma-separated, in this order; each becomes a list item as written
  ///
  /// In de, this message translates to:
  /// **'Milch,Brot,Eier,Butter,Käse,Bananen,Äpfel,Tomaten,Nudeln,Kaffee,Joghurt,Klopapier'**
  String get needStaples;

  /// Guided start, step need: label of the field for own items
  ///
  /// In de, this message translates to:
  /// **'Noch etwas?'**
  String get needFieldLabel;

  /// Guided start, step need: example in the field
  ///
  /// In de, this message translates to:
  /// **'z. B. 2 Gurken'**
  String get needFieldHint;

  /// Guided start, step need: button next to the field
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get needAdd;

  /// Guided start, step need: heading over what was added
  ///
  /// In de, this message translates to:
  /// **'Auf deiner Liste ({count})'**
  String needListTitle(int count);

  /// Guided start, step need: tooltip of the X on an added item
  ///
  /// In de, this message translates to:
  /// **'{name} entfernen'**
  String needRemove(String name);

  /// Guided start, step need: next button with the number of items
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Weiter} =1{Weiter mit 1 Artikel} other{Weiter mit {count} Artikeln}}'**
  String needNext(int count);

  /// Guided start, step account: title
  ///
  /// In de, this message translates to:
  /// **'Konto erstellen'**
  String get accountStepTitle;

  /// Guided start, step account: body above the sign-in methods
  ///
  /// In de, this message translates to:
  /// **'Fast geschafft. Mit einem Konto speichern wir eure Liste, und du kannst jemanden einladen.'**
  String get accountStepBody;

  /// Guided start, after sign-in: while the household is created and the items are added
  ///
  /// In de, this message translates to:
  /// **'Wir richten euren Haushalt ein …'**
  String get setupBusy;

  /// Guided start, step invite: title for a couple
  ///
  /// In de, this message translates to:
  /// **'Partner·in einladen'**
  String get inviteStepPartner;

  /// Guided start, step invite: title for a family
  ///
  /// In de, this message translates to:
  /// **'Familie einladen'**
  String get inviteStepFamily;

  /// Guided start, step invite: title for a shared flat
  ///
  /// In de, this message translates to:
  /// **'Mitbewohner einladen'**
  String get inviteStepFlat;

  /// Guided start, step invite: title for a club
  ///
  /// In de, this message translates to:
  /// **'Mitglieder einladen'**
  String get inviteStepClub;

  /// Guided start, step invite: title for anyone else
  ///
  /// In de, this message translates to:
  /// **'Jemanden einladen'**
  String get inviteStepOther;

  /// Guided start, step invite: body
  ///
  /// In de, this message translates to:
  /// **'Teile den Link mit der Person, mit der du einkaufst. Jede Einladung gilt 7 Tage und für eine Person.'**
  String get inviteStepBody;

  /// Guided start, step invite: body for a club
  ///
  /// In de, this message translates to:
  /// **'Schick jedem Mitglied einen eigenen Link. Alle sehen dieselbe Liste.'**
  String get inviteStepBodyClub;

  /// Guided start, step invite: how many items the invitee sees at once (shown from 1)
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Artikel wartet schon auf der Liste.} other{{count} Artikel warten schon auf der Liste.}}'**
  String inviteStepWaiting(int count);

  /// Guided start, step invite: makes one more invite (one per person)
  ///
  /// In de, this message translates to:
  /// **'Weitere Einladung'**
  String get inviteAnother;

  /// Invite card: the invite was accepted while the screen is open
  ///
  /// In de, this message translates to:
  /// **'Beigetreten'**
  String get inviteJoined;

  /// Invite card: who accepted the invite
  ///
  /// In de, this message translates to:
  /// **'{name} ist beigetreten'**
  String inviteJoinedName(String name);

  /// No description provided for @inviteShareTextCodeOnly.
  ///
  /// In de, this message translates to:
  /// **'Komm in unseren Snacklist-Haushalt. Code: {code}'**
  String inviteShareTextCodeOnly(String code);

  /// No description provided for @share.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get share;

  /// No description provided for @copyLink.
  ///
  /// In de, this message translates to:
  /// **'Link kopieren'**
  String get copyLink;

  /// No description provided for @copyCode.
  ///
  /// In de, this message translates to:
  /// **'Code kopieren'**
  String get copyCode;

  /// No description provided for @linkCopied.
  ///
  /// In de, this message translates to:
  /// **'Link kopiert'**
  String get linkCopied;

  /// No description provided for @codeCopied.
  ///
  /// In de, this message translates to:
  /// **'Code kopiert'**
  String get codeCopied;

  /// No description provided for @invitesTitle.
  ///
  /// In de, this message translates to:
  /// **'Einladungen'**
  String get invitesTitle;

  /// No description provided for @newInvite.
  ///
  /// In de, this message translates to:
  /// **'Neue Einladung'**
  String get newInvite;

  /// No description provided for @inviteValidUntil.
  ///
  /// In de, this message translates to:
  /// **'gültig bis {date}, {time} Uhr'**
  String inviteValidUntil(DateTime date, DateTime time);

  /// No description provided for @inviteRevoke.
  ///
  /// In de, this message translates to:
  /// **'Widerrufen'**
  String get inviteRevoke;

  /// No description provided for @inviteRevokeLabel.
  ///
  /// In de, this message translates to:
  /// **'Einladung {code} widerrufen'**
  String inviteRevokeLabel(String code);

  /// No description provided for @retry.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get retry;

  /// More: the one-time purchase; the product name, the same in every language
  ///
  /// In de, this message translates to:
  /// **'Snacklist Lifetime'**
  String get lifetimeTitle;

  /// More: under Snacklist Lifetime while not unlocked
  ///
  /// In de, this message translates to:
  /// **'Snacklist unterstützen'**
  String get lifetimeRowHint;

  /// No description provided for @lifetimeBody.
  ///
  /// In de, this message translates to:
  /// **'Ein Kauf, für dein Konto: Snacklist Lifetime unterstützt die Entwicklung von Snacklist.'**
  String get lifetimeBody;

  /// Snacklist Lifetime: the buy button; the store's sheet shows the price (no store call before this tap, H-67)
  ///
  /// In de, this message translates to:
  /// **'Weiter zum Kauf'**
  String get lifetimeBuy;

  /// Snacklist Lifetime: under Buy; the page shows no price, the store's sheet does
  ///
  /// In de, this message translates to:
  /// **'Den Preis zeigen dir der App Store oder Google Play, bevor du kaufst.'**
  String get lifetimePriceInStore;

  /// No description provided for @lifetimeRestore.
  ///
  /// In de, this message translates to:
  /// **'Kauf wiederherstellen'**
  String get lifetimeRestore;

  /// Snacklist Lifetime: Ask to Buy or a Play payment that completes later
  ///
  /// In de, this message translates to:
  /// **'Wartet auf Bestätigung'**
  String get lifetimePending;

  /// No description provided for @lifetimePendingBody.
  ///
  /// In de, this message translates to:
  /// **'Snacklist Lifetime wird freigeschaltet, sobald der Kauf bestätigt ist. Das kann etwas dauern.'**
  String get lifetimePendingBody;

  /// Snacklist Lifetime: bought or restored, waiting for the unlock from the server
  ///
  /// In de, this message translates to:
  /// **'Wird freigeschaltet …'**
  String get lifetimeUnlocking;

  /// Snacklist Lifetime: bought, but the server's unlock has not arrived within a minute
  ///
  /// In de, this message translates to:
  /// **'Dein Kauf ist angekommen, die Freischaltung dauert nur länger als sonst. Sie erscheint hier von selbst; bitte nicht noch einmal kaufen.'**
  String get lifetimeUnlockDelayed;

  /// Snacklist Lifetime: the household has two or more store purchases; the refund help link is on the page
  ///
  /// In de, this message translates to:
  /// **'Snacklist Lifetime wurde mehr als einmal gekauft. Einen der Käufe kannst du dir erstatten lassen.'**
  String get lifetimeBoughtTwice;

  /// No description provided for @lifetimeCanceled.
  ///
  /// In de, this message translates to:
  /// **'Kauf abgebrochen.'**
  String get lifetimeCanceled;

  /// Snacklist Lifetime: the store has no product yet
  ///
  /// In de, this message translates to:
  /// **'Snacklist Lifetime ist bald verfügbar.'**
  String get lifetimeComingSoon;

  /// No description provided for @lifetimeStoreOffline.
  ///
  /// In de, this message translates to:
  /// **'Der Store ist gerade nicht erreichbar. Prüfe die Verbindung.'**
  String get lifetimeStoreOffline;

  /// No description provided for @lifetimeUsedElsewhere.
  ///
  /// In de, this message translates to:
  /// **'Dieser Kauf gehört zu einem anderen Konto oder zu einem früheren Haushalt und bleibt dort. Hier schaltet er nichts frei.'**
  String get lifetimeUsedElsewhere;

  /// No description provided for @lifetimeNothingRestored.
  ///
  /// In de, this message translates to:
  /// **'Kein früherer Kauf gefunden.'**
  String get lifetimeNothingRestored;

  /// No description provided for @lifetimeStoreFailed.
  ///
  /// In de, this message translates to:
  /// **'Der Kauf hat nicht geklappt ({code}).'**
  String lifetimeStoreFailed(String code);

  /// Snacklist Lifetime: the household's unlock is not known yet (loading or offline); no Buy button meanwhile
  ///
  /// In de, this message translates to:
  /// **'Wir prüfen, ob dein Haushalt Snacklist Lifetime schon hat …'**
  String get lifetimeChecking;

  /// A small link to the refund help
  ///
  /// In de, this message translates to:
  /// **'Doppelt gekauft? So bekommst du dein Geld zurück'**
  String get lifetimeRefundLink;

  /// No description provided for @refundHelpTitle.
  ///
  /// In de, this message translates to:
  /// **'Kauf zurückfordern'**
  String get refundHelpTitle;

  /// No description provided for @refundHelpBody.
  ///
  /// In de, this message translates to:
  /// **'Snacklist Lifetime gehört zu deinem Konto. Käufe im App Store erstattet nur Apple. Bei Google Play beantragst du die Erstattung in den ersten 48 Stunden bei Google; danach schreib uns an support@snacklist.app, wir prüfen jede Anfrage einzeln. Deine gesetzlichen Rechte bleiben unberührt.'**
  String get refundHelpBody;

  /// No description provided for @refundHelpApple.
  ///
  /// In de, this message translates to:
  /// **'iPhone: Öffne reportaproblem.apple.com, melde dich mit deinem Apple Account an, wähle „Rückerstattung anfordern“ und dann Snacklist Lifetime.'**
  String get refundHelpApple;

  /// No description provided for @refundHelpGoogle.
  ///
  /// In de, this message translates to:
  /// **'Android, in den ersten 48 Stunden: Öffne Google Play, tippe auf dein Profilbild, dann „Zahlungen und Abos“, „Budget und Bestellverlauf“, wähle Snacklist Lifetime und „Problem melden“. Danach schreib uns mit der Bestellnummer (beginnt mit „GPA.“) oder der E-Mail-Adresse deines Google-Kontos.'**
  String get refundHelpGoogle;

  /// No description provided for @refundHelpReason.
  ///
  /// In de, this message translates to:
  /// **'Als Grund kannst du schreiben: „Ich habe Snacklist Lifetime mehr als einmal gekauft.“'**
  String get refundHelpReason;

  /// No description provided for @refundHelpAppleLink.
  ///
  /// In de, this message translates to:
  /// **'Bei Apple anfragen'**
  String get refundHelpAppleLink;

  /// No description provided for @refundHelpGoogleLink.
  ///
  /// In de, this message translates to:
  /// **'Bei Google anfragen'**
  String get refundHelpGoogleLink;

  /// Refund help: opens the FAQ on snacklist.app/support with the refund question (H-76)
  ///
  /// In de, this message translates to:
  /// **'Mehr in den häufigen Fragen'**
  String get refundHelpFaqLink;

  /// No description provided for @joinTargetUnlocked.
  ///
  /// In de, this message translates to:
  /// **'Dieser Haushalt hat eine frühere Freischaltung. Snacklist Premium selbst gilt für dein Konto.'**
  String get joinTargetUnlocked;

  /// No description provided for @joinRefundLink.
  ///
  /// In de, this message translates to:
  /// **'Du hast Snacklist Lifetime vor Kurzem gekauft? So forderst du den Kauf zurück'**
  String get joinRefundLink;

  /// No description provided for @joinLifetimeRefundLink.
  ///
  /// In de, this message translates to:
  /// **'Erstattung bei Apple oder Google anfragen'**
  String get joinLifetimeRefundLink;

  /// No description provided for @archivedTitle.
  ///
  /// In de, this message translates to:
  /// **'Archivierte Haushalte'**
  String get archivedTitle;

  /// No description provided for @archivedEmpty.
  ///
  /// In de, this message translates to:
  /// **'Du hast keinen Haushalt archiviert.'**
  String get archivedEmpty;

  /// No description provided for @archivedUnlocked.
  ///
  /// In de, this message translates to:
  /// **'Mit früherer Freischaltung'**
  String get archivedUnlocked;

  /// Archived households: the household is deleted 24 months after archiving unless re-enabled
  ///
  /// In de, this message translates to:
  /// **'Wird am {date} gelöscht'**
  String archivedDeletesOn(DateTime date);

  /// No description provided for @archivedRestore.
  ///
  /// In de, this message translates to:
  /// **'Wieder aktivieren'**
  String get archivedRestore;

  /// No description provided for @archivedRestoreTitle.
  ///
  /// In de, this message translates to:
  /// **'„{household}“ wieder aktivieren?'**
  String archivedRestoreTitle(String household);

  /// No description provided for @archivedRestoreBody.
  ///
  /// In de, this message translates to:
  /// **'Du bist wieder Mitglied von „{household}“. Deine anderen Haushalte bleiben.'**
  String archivedRestoreBody(String household);

  /// More: the Premium page and its row; the product name, the same in every language
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium'**
  String get premiumTitle;

  /// Premium page (PW-P4, job 87): the hero's title. Legal N-348 (job 383): Premium is per account; the title must never promise sharing
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium für dich'**
  String get premiumHeroTitle;

  /// Premium page (PW-P4, job 87): under the hero title; Premium is per account (Legal Review N-345)
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium gilt für dich, in jedem Haushalt, in dem du Mitglied bist.'**
  String get premiumHeroBody;

  /// FINAL (Legal Review N-67, 2026-11-04; Peter 2026-10-31: no assistant brand named): Premium page, benefit line, AI assistants over MCP
  ///
  /// In de, this message translates to:
  /// **'KI-Assistenten, die MCP unterstützen, mit eurer Liste verbinden (bis zu 1.000 Anfragen pro Konto und Tag, 60 pro Minute)'**
  String get premiumBenefitAi;

  /// Premium page (PW-P4, job 87): benefit line, the public API; only while the public-api flag is on
  ///
  /// In de, this message translates to:
  /// **'Eigene Automationen mit der Snacklist API (bis zu 1.000 Anfragen pro Konto und Tag, 60 pro Minute)'**
  String get premiumBenefitApi;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: an active yearly plan that renews
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium aktiv (jährlich, verlängert sich am {date})'**
  String premiumStatusRenews(DateTime date);

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: an active yearly plan with auto-renew off
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium aktiv (jährlich, läuft am {date} aus)'**
  String premiumStatusEnds(DateTime date);

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the household has Lifetime
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium Lifetime'**
  String get premiumStatusLifetime;

  /// Handoff 5(c), Legal Review final rule: the total price incl. VAT, e.g. „29,99 € einmalig, inkl. MwSt.“. Premium page, a plan tile: under the store's price, {period} is „pro Jahr“ or „einmalig“; only for a price in euros
  ///
  /// In de, this message translates to:
  /// **'{period}, inkl. MwSt.'**
  String premiumWithVat(String period);

  /// FINAL (Legal Review, approved by Peter 2026-11-03 20:32, handoff 2026-11-03-pm-revenuecat-final section 4): use exactly as written. Premium page: link under the free unlock's status to the privacy policy's section #premium-beta
  ///
  /// In de, this message translates to:
  /// **'Mehr dazu in der Datenschutzerklärung'**
  String get premiumBetaPrivacyLink;

  /// FINAL (Legal Review, approved by Peter 2026-11-03 20:32, handoff 2026-11-03-pm-revenuecat-final section 4): use exactly as written. Premium page: under the free unlock's status
  ///
  /// In de, this message translates to:
  /// **'Du zahlst nichts, und nichts verlängert sich automatisch. Bevor die kostenlose Freischaltung endet, sagen wir dir mindestens 4 Wochen vorher Bescheid.'**
  String get premiumBetaBody;

  /// FINAL (Legal Review, approved by Peter 2026-11-03 20:32, handoff 2026-11-03-pm-revenuecat-final section 4): use exactly as written. Premium page: status of a household with a free unlock (testers, app review) once sales started (premium_offer on)
  ///
  /// In de, this message translates to:
  /// **'Kostenlos freigeschaltet (Test und App-Prüfung)'**
  String get premiumStatusFree;

  /// FINAL (Legal Review, approved by Peter 2026-11-03 20:32, handoff 2026-11-03-pm-revenuecat-final section 4): use exactly as written. Premium page: status of a household with a free unlock (promotional grant) while sales have not started (premium_offer off)
  ///
  /// In de, this message translates to:
  /// **'In der Beta kostenlos freigeschaltet, bis Snacklist Premium startet'**
  String get premiumStatusBeta;

  /// DRAFT for Legal Review (job 371): Premium page: status of an account that existed before launch, with its own free lifetime unlock (a promotional grant to the account, as thanks for the beta)
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium Lifetime, kostenlos als Dank für die Beta'**
  String get premiumStatusBetaLifetime;

  /// DRAFT for Legal Review (job 371): Premium page: under premiumStatusBetaLifetime, what it costs, that it is not a purchase and when it ends (Legal Review N-343)
  ///
  /// In de, this message translates to:
  /// **'Du zahlst nichts, und nichts verlängert sich automatisch. Es ist kein Kauf. Die Freischaltung gilt für dein Konto, solange es besteht und wir Snacklist betreiben. Löschst du das Konto, endet sie. Es gibt nichts zu erstatten, weil du nichts gezahlt hast.'**
  String get premiumBetaLifetimeBody;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the household's rows are loading or offline; no Buy
  ///
  /// In de, this message translates to:
  /// **'Wir prüfen, ob du Snacklist Premium schon hast …'**
  String get premiumChecking;

  /// Job 419 (Terms §6): under a household's free unlock (beta or tester grant) when the user has no Premium of their own: the household's unlock is not the user's Snacklist Premium, so MCP and the API do not open for them
  ///
  /// In de, this message translates to:
  /// **'Diese Freischaltung gilt für euren Haushalt. Snacklist Premium selbst gilt für dein Konto.'**
  String get premiumHouseholdOnly;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the yearly plan's card title, offered first
  ///
  /// In de, this message translates to:
  /// **'Jährlich'**
  String get premiumYearlyTitle;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49, 87). Premium page, yearly tile: the billing period under the store's price, followed by „inkl. MwSt.“ for a euro price
  ///
  /// In de, this message translates to:
  /// **'pro Jahr'**
  String get premiumPerYear;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the one-time purchase's card title
  ///
  /// In de, this message translates to:
  /// **'Lifetime'**
  String get premiumLifetimeTitle;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49, 87). Premium page, Lifetime tile: under the store's price, followed by „inkl. MwSt.“ for a euro price
  ///
  /// In de, this message translates to:
  /// **'einmalig'**
  String get premiumOneTime;

  /// Wording from Legal N-302 (2026-11-19, job 317): no "für immer", Lifetime belongs to the account (privacy §14). Premium page: the line under the Lifetime tile. No amount and no ratio to the yearly price: the store sets both prices (Peter, t788u, 11 Nov 2026, supersedes Spec #4 AC9's three-years framing)
  ///
  /// In de, this message translates to:
  /// **'Einmal zahlen, kein Abo.'**
  String get premiumLifetimeValue;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the subscription disclosures next to the yearly card and its Buy button (App Store Review Guidelines 3.1.2, Google Play)
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium jährlich, Laufzeit 1 Jahr. Das Abo verlängert sich automatisch um ein Jahr, wenn du es nicht mindestens 24 Stunden vor Ende der Laufzeit kündigst. Bezahlt wird über dein Apple- bzw. Google-Konto, bei der Bestätigung des Kaufs und bei jeder Verlängerung. Verwalten und kündigen kannst du das Abo in den Abo-Einstellungen des App Store bzw. von Google Play.'**
  String get premiumYearlyTerms;

  /// Legal N-350 (job 383): shown above the buy button, before purchase; Premium belongs to the buyer's account
  ///
  /// In de, this message translates to:
  /// **'Premium gilt dann für dein Konto, in jedem Haushalt, in dem du Mitglied bist.'**
  String get premiumHousehold;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: buy the yearly plan; RevenueCat starts only on this tap (H-67)
  ///
  /// In de, this message translates to:
  /// **'Jährlich abschließen'**
  String get premiumBuyYearly;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: buy Lifetime; RevenueCat starts only on this tap (H-67)
  ///
  /// In de, this message translates to:
  /// **'Lifetime kaufen'**
  String get premiumBuyLifetime;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the store's prices could not be read (offline, store unavailable); no Buy without a price (A2-5)
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium ist gerade nicht verfügbar.'**
  String get premiumUnavailable;

  /// Premium page and More: link to the terms of use on snacklist.app (Legal L24-7: label without EULA, the Apple link has its own)
  ///
  /// In de, this message translates to:
  /// **'Nutzungsbedingungen'**
  String get premiumTermsLink;

  /// iOS only, on the Premium page and in More, right after the terms link: opens Apple's standard license agreement (EULA), which App Store rules require next to the subscription terms (Legal L24-7)
  ///
  /// In de, this message translates to:
  /// **'Lizenzvertrag von Apple (EULA)'**
  String get premiumAppleEulaLink;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: link to the privacy policy
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung'**
  String get premiumPrivacyLink;

  /// Premium page: shown after a refused yearly buy when the store account already pays a yearly plan bound to another Snacklist account
  ///
  /// In de, this message translates to:
  /// **'Dein Apple- bzw. Google-Konto zahlt schon ein Jahresabo über ein anderes Konto. Dieses Jahresabo gilt für dieses andere Konto, nicht für das, mit dem du hier angemeldet bist.'**
  String get premiumUsedElsewhereYearly;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: two yearly plans run at once (H-84); followed by the manage link
  ///
  /// In de, this message translates to:
  /// **'Es laufen zwei Jahresabos. Kündigen kann jedes nur, wer es abgeschlossen hat.'**
  String get premiumTwoYearly;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page on the web: no sales on the web
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium kaufst du in der iPhone- oder Android-App. Danach ist es auch hier für dein Konto freigeschaltet.'**
  String get premiumWeb;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Refund help: a short note for the yearly plan below the H-76 texts, which name only Lifetime (NEEDS_LEAD Job 49)
  ///
  /// In de, this message translates to:
  /// **'Für das Jahresabo gilt dasselbe. Eine Kündigung beendet nur die Verlängerung; das laufende Jahr wird nicht automatisch erstattet.'**
  String get premiumRefundYearly;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. Premium page: opens the store's subscription management (H-83)
  ///
  /// In de, this message translates to:
  /// **'Abo verwalten oder kündigen'**
  String get premiumManage;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page on the web: before the two store links
  ///
  /// In de, this message translates to:
  /// **'Dein Jahresabo verwaltest du im App Store oder bei Google Play.'**
  String get premiumManageWeb;

  /// Premium page on the web: link to Apple's subscription settings
  ///
  /// In de, this message translates to:
  /// **'App Store'**
  String get premiumManageApple;

  /// Premium page on the web: link to Google Play's subscriptions
  ///
  /// In de, this message translates to:
  /// **'Google Play'**
  String get premiumManageGoogle;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. Premium page: shown only to the subscriber while a renewal failed (H-83, H-87)
  ///
  /// In de, this message translates to:
  /// **'Apple bzw. Google konnten dein Jahresabo nicht abbuchen. Premium läuft noch bis {date}. Prüfe deine Zahlungsmethode im Store.'**
  String premiumBillingIssue(DateTime date);

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. Before buying Lifetime while a yearly plan runs, and after (H-84). The part in [brackets] is the link to the store's subscription page; the app shows it without the brackets
  ///
  /// In de, this message translates to:
  /// **'Es läuft schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird weiter abgerechnet, bis es gekündigt wird; das restliche Abojahr wird nicht automatisch erstattet. Kündigen kann nur, wer das Abo abgeschlossen hat, unter [Abos verwalten]. Snacklist kann das Abo nicht kündigen.'**
  String get premiumLifetimeWhileYearly;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. premiumLifetimeWhileYearly for the subscriber (H-84). [brackets]: the store link
  ///
  /// In de, this message translates to:
  /// **'Du hast schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird weiter abgerechnet, bis es gekündigt wird; das restliche Abojahr wird nicht automatisch erstattet. Du kannst es unter [Abo verwalten] kündigen. Snacklist kann das Abo nicht kündigen.'**
  String get premiumLifetimeWhileYearlySubscriber;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. Lifetime-while-yearly warning: opens the store sheet (RevenueCat starts only here, H-67). EN: Lead wording, PLACEHOLDER
  ///
  /// In de, this message translates to:
  /// **'Trotzdem kaufen'**
  String get premiumBuyAnyway;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. Before deleting the account, leaving, deleting or archiving a household, to the subscriber of a renewing yearly plan (H-85)
  ///
  /// In de, this message translates to:
  /// **'Dein Jahresabo für Snacklist Premium läuft weiter und wird über dein Apple- bzw. Google-Konto abgerechnet, bis du es kündigst. Löschen oder Verlassen kündigt es nicht.'**
  String get premiumBillingContinues;

  /// PLACEHOLDER (job 49): Snacklist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Lead wording for Legal Review: the same moment, to members who are not the subscriber (H-85, NEEDS_LEAD Job 49)
  ///
  /// In de, this message translates to:
  /// **'Ein Jahresabo für diesen Haushalt läuft weiter, bis es gekündigt wird.'**
  String get premiumBillingContinuesOther;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. Billing-continues dialog: opens the store's subscription page
  ///
  /// In de, this message translates to:
  /// **'Abo verwalten'**
  String get premiumManageSubscription;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. Billing-continues dialog: goes on with deleting, leaving or archiving
  ///
  /// In de, this message translates to:
  /// **'Trotzdem fortfahren'**
  String get premiumContinueAnyway;

  /// PLACEHOLDER (job 50): Snacklist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings (Zugänge), locked household: the card's title
  ///
  /// In de, this message translates to:
  /// **'Teil von Snacklist Premium'**
  String get integrationPremiumTitle;

  /// PLACEHOLDER (job 50): Snacklist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked user (job 328 review 0: per user, another member's Premium does not unlock you): why the connections are paused; nothing is removed
  ///
  /// In de, this message translates to:
  /// **'KI-Assistenten gehören zu Snacklist Premium. Deine Verbindungen bleiben gespeichert und funktionieren wieder, sobald du Snacklist Premium hast.'**
  String get integrationPremiumBody;

  /// PLACEHOLDER (job 50): Snacklist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: included in Snacklist Premium
  ///
  /// In de, this message translates to:
  /// **'KI-Assistenten, die MCP unterstützen'**
  String get integrationPremiumAi;

  /// PLACEHOLDER (job 50): Snacklist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: button that opens the Snacklist Premium page (only where it is sold)
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium freischalten'**
  String get integrationPremiumBuy;

  /// PLACEHOLDER (job 50): Snacklist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: Snacklist Premium is not sold in this build yet, no button
  ///
  /// In de, this message translates to:
  /// **'Bald verfügbar.'**
  String get integrationPremiumSoon;

  /// PLACEHOLDER (job 50): Snacklist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: shown on each existing connection or token, which stays as it is
  ///
  /// In de, this message translates to:
  /// **'Pausiert: braucht Snacklist Premium'**
  String get integrationPaused;

  /// Zugänge (More → Zugänge), job 73: label of the public REST API section
  ///
  /// In de, this message translates to:
  /// **'API'**
  String get apiHeader;

  /// Zugänge, API section (shown while the public-api flag is on): below the API's base URL
  ///
  /// In de, this message translates to:
  /// **'Für eigene Skripte und Automationen: Lies und ändere eure Liste über HTTP, mit einem API-Schlüssel.'**
  String get apiBody;

  /// Zugänge, API section: link to docs/API.md on GitHub
  ///
  /// In de, this message translates to:
  /// **'API-Dokumentation'**
  String get apiDocs;

  /// Zugänge, API section: the user has no API key yet
  ///
  /// In de, this message translates to:
  /// **'Kein aktiver API-Schlüssel.'**
  String get noApiKeys;

  /// Zugänge, API section: button and dialog title for a new API key
  ///
  /// In de, this message translates to:
  /// **'API-Schlüssel erstellen'**
  String get createApiKey;

  /// Create API key dialog: hint in the name field
  ///
  /// In de, this message translates to:
  /// **'z. B. Home Assistant'**
  String get apiKeyNameHint;

  /// An API key's scope: may read the list, change nothing. Also on the key's row
  ///
  /// In de, this message translates to:
  /// **'Nur lesen'**
  String get apiScopeRead;

  /// Create API key dialog: what the read-only choice allows
  ///
  /// In de, this message translates to:
  /// **'Liest die Liste, Kategorien und Läden. Ändert nichts.'**
  String get apiScopeReadBody;

  /// An API key's scope: may read and change the list. Also on the key's row
  ///
  /// In de, this message translates to:
  /// **'Lesen und schreiben'**
  String get apiScopeReadWrite;

  /// Create API key dialog: what the read-and-write choice allows
  ///
  /// In de, this message translates to:
  /// **'Kann auch Einträge hinzufügen, ändern, abhaken und löschen, Listen und Läden anlegen und umbenennen und die Reihenfolge in einem Laden festlegen.'**
  String get apiScopeReadWriteBody;

  /// Dialog title right after an API key was created
  ///
  /// In de, this message translates to:
  /// **'API-Schlüssel erstellt'**
  String get apiKeyCreated;

  /// The new API key's dialog: the key is shown only this once
  ///
  /// In de, this message translates to:
  /// **'Kopiere den Schlüssel jetzt. Er wird nicht noch einmal angezeigt.'**
  String get apiKeyShownOnce;

  /// Confirm dialog title before revoking an API key
  ///
  /// In de, this message translates to:
  /// **'API-Schlüssel widerrufen?'**
  String get revokeApiKeyTitle;

  /// Confirm dialog before revoking an API key
  ///
  /// In de, this message translates to:
  /// **'Skripte, die ihn benutzen, verlieren sofort den Zugriff.'**
  String get revokeApiKeyBody;

  /// Snack bar: the member already has 10 active API keys (docs/API.md, Limits)
  ///
  /// In de, this message translates to:
  /// **'Höchstens 10 aktive API-Schlüssel. Widerrufe erst einen.'**
  String get tooManyApiKeys;

  /// Snack bar: the server refused to create an API key outside the app's own sign-in (session_required)
  ///
  /// In de, this message translates to:
  /// **'API-Schlüssel kannst du nur hier in der App erstellen, während du angemeldet bist.'**
  String get apiKeySessionRequired;

  /// Snack bar: the server refused to create an API key because the public API is switched off on it (api_disabled, job 75)
  ///
  /// In de, this message translates to:
  /// **'Die API ist noch nicht freigeschaltet.'**
  String get apiDisabled;

  /// PLACEHOLDER (job 73): Snacklist Launch writes the final copy. Zugänge, API section, locked user (job 50; job 328 review 0: per user, another member's Premium does not unlock you): the keys stay, unused for now; new ones can still be made
  ///
  /// In de, this message translates to:
  /// **'Die Snacklist-API gehört zu Snacklist Premium. Deine Schlüssel bleiben und funktionieren wieder, sobald du Premium hast.'**
  String get apiPremium;

  /// Zugänge, under the access token heading while the public API is hidden (job 80)
  ///
  /// In de, this message translates to:
  /// **'Mit einem Zugriffsschlüssel baust du eigene Automationen, die eure Liste pflegen, etwa ein Skript oder einen Assistenten am MCP-Server.'**
  String get accessTokensHint;

  /// Zugänge, under the access token heading while the public-api flag is on (job 80)
  ///
  /// In de, this message translates to:
  /// **'Mit einem Zugriffsschlüssel baust du eigene Automationen am MCP-Server, die eure Liste pflegen. Für Programme ohne MCP gibt es unten die API.'**
  String get accessTokensHintWithApi;

  /// Job 169b: Zugänge, under the token hint when the user is in several households: the household a new token acts in
  ///
  /// In de, this message translates to:
  /// **'Ein neuer Zugriffsschlüssel gilt für „{household}“, den Haushalt, der gerade offen ist.'**
  String accessKeysHousehold(String household);

  /// Job 169b: as accessKeysHousehold while the public-api flag is on
  ///
  /// In de, this message translates to:
  /// **'Neue Zugriffsschlüssel und API-Schlüssel gelten für „{household}“, den Haushalt, der gerade offen ist.'**
  String accessKeysHouseholdWithApi(String household);

  /// Zugänge, connected app row and details: the newest token refresh of the app (job 80)
  ///
  /// In de, this message translates to:
  /// **'Zuletzt aktiv {date}'**
  String lastActiveOn(DateTime date);

  /// Zugänge, connected app details: the app has not used its access yet (job 80)
  ///
  /// In de, this message translates to:
  /// **'Noch nicht aktiv'**
  String get notActiveYet;

  /// Zugänge, connected app details: the browser and system the user approved the app on, e.g. Chrome · macOS (job 80)
  ///
  /// In de, this message translates to:
  /// **'Freigegeben auf {device}'**
  String appDevice(String device);

  /// Zugänge, connected app details sheet: heading of the plain-words permissions (job 80)
  ///
  /// In de, this message translates to:
  /// **'Was {name} darf'**
  String appCanTitle(String name);

  /// Connected app details: the email scope in plain words (job 80)
  ///
  /// In de, this message translates to:
  /// **'Deine E-Mail-Adresse sehen.'**
  String get appCanEmail;

  /// Connected app details: the profile scope in plain words (job 80)
  ///
  /// In de, this message translates to:
  /// **'Deinen Namen sehen.'**
  String get appCanProfile;

  /// Connected app details: the phone scope in plain words (job 80)
  ///
  /// In de, this message translates to:
  /// **'Deine Telefonnummer sehen.'**
  String get appCanPhone;

  /// Connected app details: the offline_access scope in plain words (job 80)
  ///
  /// In de, this message translates to:
  /// **'Verbunden bleiben, bis du die Verbindung trennst.'**
  String get appCanStay;

  /// Account screen (job 80): tooltip and screen reader label of the copy button next to the email address
  ///
  /// In de, this message translates to:
  /// **'E-Mail-Adresse kopieren'**
  String get copyEmail;

  /// List tab tip card (job 80): title of the tip that a hold without dragging opens an item's edit sheet
  ///
  /// In de, this message translates to:
  /// **'Artikel bearbeiten'**
  String get tipEditTitle;

  /// List tab tip card (job 80): a hold released without moving (touch or mouse) opens the edit sheet with these fields; a hold that moves drags instead
  ///
  /// In de, this message translates to:
  /// **'Halte einen Artikel gedrückt und ändere Menge, Marke, Laden und mehr.'**
  String get tipEditBody;

  /// List tab tip card (job 80): title of the tip that the amount can be typed with the item
  ///
  /// In de, this message translates to:
  /// **'Menge gleich mittippen'**
  String get tipAmountsTitle;

  /// List tab tip card (job 80): the quoted examples must parse with a Menge (app/test/tips/tips_test.dart checks them with parseEntry)
  ///
  /// In de, this message translates to:
  /// **'Schreib „2 Gurken“ oder „Milch 2 l“, und Snacklist erkennt die Menge.'**
  String get tipAmountsBody;

  /// List tab tip card (job 80): tooltip and screen reader label of the X that hides the tip
  ///
  /// In de, this message translates to:
  /// **'Tipp ausblenden'**
  String get tipDismiss;

  /// Job 169b, job 200: create_household or accept_invite refused, the user is in 20 households (public.household_cap())
  ///
  /// In de, this message translates to:
  /// **'Du bist schon in 20 Haushalten. Verlasse einen, bevor du einen neuen anlegst oder beitrittst.'**
  String get tooManyHouseholds;

  /// Job 169b: screen reader hint of the household name chip top left of the list, which opens the switcher sheet
  ///
  /// In de, this message translates to:
  /// **'Haushalt wechseln'**
  String get householdSwitch;

  /// Job 169b: title of the switcher sheet
  ///
  /// In de, this message translates to:
  /// **'Deine Haushalte'**
  String get householdsTitle;

  /// Job 169b: switcher row, how many members a household has
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Mitglied} other{{count} Mitglieder}}'**
  String householdMembers(int count);

  /// Job 169b: switcher row, how many items are not ticked yet
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{nichts offen} =1{1 offen} other{{count} offen}}'**
  String householdOpenItems(int count);

  /// Job 169b: screen reader label of the check on the switcher row of the household shown now
  ///
  /// In de, this message translates to:
  /// **'Angezeigt'**
  String get householdCurrent;

  /// Job 169b: switcher sheet row and the title of the create page opened from it
  ///
  /// In de, this message translates to:
  /// **'Neuer Haushalt'**
  String get newHousehold;

  /// Job 169b: switcher sheet row that opens the join screen
  ///
  /// In de, this message translates to:
  /// **'Mit Code beitreten'**
  String get joinWithCode;

  /// Job 169b: switcher sheet footer naming the default household; tap opens the picker
  ///
  /// In de, this message translates to:
  /// **'Siri, Alexa & KI nutzen: {household}'**
  String voiceDefaultRow(String household);

  /// Job 169b: default household picker title and the switch on the household page
  ///
  /// In de, this message translates to:
  /// **'Standard für Siri, Alexa & KI'**
  String get voiceDefaultTitle;

  /// Job 169b: under the default picker's title
  ///
  /// In de, this message translates to:
  /// **'Was du Siri, Alexa oder einem KI-Assistenten sagst, landet in diesem Haushalt.'**
  String get voiceDefaultBody;

  /// Job 169b: household page, under the default switch while it is on
  ///
  /// In de, this message translates to:
  /// **'Siri, Alexa und KI-Assistenten nutzen diesen Haushalt.'**
  String get voiceDefaultOn;

  /// Job 169b: household page, under the default switch while another household is the default
  ///
  /// In de, this message translates to:
  /// **'Siri, Alexa und KI-Assistenten nutzen gerade „{household}“.'**
  String voiceDefaultOff(String household);

  /// Job 169b: title of the household page under More
  ///
  /// In de, this message translates to:
  /// **'Haushalt'**
  String get householdPageTitle;

  /// Job 169b: household page, the button beside the name
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get householdRename;

  /// Job 169b: rename dialog title
  ///
  /// In de, this message translates to:
  /// **'Haushalt umbenennen'**
  String get householdRenameTitle;

  /// Job 169b: household page section label
  ///
  /// In de, this message translates to:
  /// **'Mitglieder'**
  String get householdMembersTitle;

  /// Job 169b: the user's own row in the members list
  ///
  /// In de, this message translates to:
  /// **'{name} (du)'**
  String householdMemberYou(String name);

  /// Job 169b: a member without a display name
  ///
  /// In de, this message translates to:
  /// **'Ohne Namen'**
  String get householdMemberUnnamed;

  /// Job 169b: household page, members list failed to load
  ///
  /// In de, this message translates to:
  /// **'Die Mitglieder konnten nicht geladen werden.'**
  String get householdMembersFailed;

  /// Job 169b: household page button and the leave dialog's confirm button
  ///
  /// In de, this message translates to:
  /// **'Haushalt verlassen'**
  String get leaveHousehold;

  /// Job 169b: leave dialog title
  ///
  /// In de, this message translates to:
  /// **'„{household}“ verlassen?'**
  String leaveTitle(String household);

  /// Job 169b: leave dialog body when others stay
  ///
  /// In de, this message translates to:
  /// **'Die anderen Mitglieder behalten die Liste. Zurück kommst du nur mit einer neuen Einladung.'**
  String get leaveShared;

  /// Job 169b: leave dialog body for the last member
  ///
  /// In de, this message translates to:
  /// **'Du bist das letzte Mitglied. Der Haushalt wird mit Liste, Verlauf, Kategorien und Läden gelöscht.'**
  String get leaveLast;

  /// Job 169b: leave dialog, last member of a household with Lifetime, archive off
  ///
  /// In de, this message translates to:
  /// **'„{household}“ hat eine frühere Freischaltung, die zum Haushalt gehört. Du bist das letzte Mitglied: Verlässt du ihn, wird der Haushalt gelöscht. Diese frühere Freischaltung endet mit ihm. Snacklist Lifetime, das zu deinem Konto gehört, bleibt davon unberührt.'**
  String leaveLifetimeEnds(String household);

  /// Job 169b: leave dialog, last member of a household with Lifetime, archive on
  ///
  /// In de, this message translates to:
  /// **'„{household}“ hat eine frühere Freischaltung, die zum Haushalt gehört. Du bist das letzte Mitglied. Archiviere den Haushalt, statt ihn zu löschen: Liste und diese frühere Freischaltung bleiben erhalten, und du kannst ihn später unter „Mehr“ wieder aktivieren. Aktivierst du ihn nicht innerhalb von 24 Monaten wieder, wird er gelöscht. Snacklist Lifetime, das zu deinem Konto gehört, bleibt davon unberührt.'**
  String leaveArchiveOffer(String household);

  /// Job 169b: leave dialog button that archives the household
  ///
  /// In de, this message translates to:
  /// **'Archivieren und verlassen'**
  String get leaveArchive;

  /// Job 169b: leave dialog button that deletes the household with its Lifetime
  ///
  /// In de, this message translates to:
  /// **'Löschen und verlassen'**
  String get leaveDelete;

  /// Job 169b: OAuth consent for a user with several households; the default is the one MCP acts in (changed in the switcher)
  ///
  /// In de, this message translates to:
  /// **'Arbeitet in deinem Standard-Haushalt „{name}“. Nennst du einen anderen deiner Haushalte, auch dort.'**
  String consentDefaultHousehold(String name);

  /// Job 169b: household page button that makes the shown household the default for Siri, Alexa and AI
  ///
  /// In de, this message translates to:
  /// **'Als Standard nutzen'**
  String get voiceDefaultMake;

  /// Job 207: household page row under the default household (behind the flag default-list-voice-target): the list Siri, Alexa and AI add to when no list is named; its subtitle names the list, a tap picks another
  ///
  /// In de, this message translates to:
  /// **'Liste für Siri, Alexa & KI'**
  String get defaultListTitle;

  /// Job 207: household sheet footer, under the row naming the default household: that household's list Siri, Alexa and AI add to when no list is named; a tap picks another
  ///
  /// In de, this message translates to:
  /// **'Liste: {list}'**
  String defaultListRow(String list);

  /// Job 169b W2: title of the invite sheet (switcher row, household page, More's Einladungen)
  ///
  /// In de, this message translates to:
  /// **'Leute einladen'**
  String get inviteSheetTitle;

  /// Job 169b W2: tooltip of the invite button on a household's row in the switcher
  ///
  /// In de, this message translates to:
  /// **'Leute in {name} einladen'**
  String inviteSheetOpen(String name);

  /// Job 169b W2: section of the invite sheet for a one-person invite
  ///
  /// In de, this message translates to:
  /// **'Für eine Person'**
  String get invitePersonTitle;

  /// No description provided for @invitePersonBody.
  ///
  /// In de, this message translates to:
  /// **'Ein Link für eine Person, 7 Tage gültig.'**
  String get invitePersonBody;

  /// Job 178 (Legal N-112): plain text on every surface that makes or shares an invite (invite sheet, Einladungen, onboarding invite steps): what the public join page shows. Wording from Legal, 2026-11-10; N-151b wording from Legal, 2026-11-13 (job 216), names exactly what the page shows; change only with Legal. Shortened by Legal N-299 (2026-11-19, job 317): the full list is in the privacy policy §5
  ///
  /// In de, this message translates to:
  /// **'Wer Link oder Code hat, sieht vor dem Beitritt deinen Namen, den Namen des Haushalts und ein paar Zahlen dazu. Gib beides nur an Personen weiter, die du einladen willst.'**
  String get inviteJoinPageHint;

  /// Job 169b W2: section of the invite sheet for the reusable group link (owner and admins)
  ///
  /// In de, this message translates to:
  /// **'Gruppenlink'**
  String get inviteGroupTitle;

  /// No description provided for @inviteGroupBody.
  ///
  /// In de, this message translates to:
  /// **'Für bis zu 50 Leute, 30 Tage gültig. Zeig den QR-Code oder teil den Link.'**
  String get inviteGroupBody;

  /// No description provided for @inviteGroupCreate.
  ///
  /// In de, this message translates to:
  /// **'Gruppenlink erstellen'**
  String get inviteGroupCreate;

  /// Job 169b W2: how many joined with the group link
  ///
  /// In de, this message translates to:
  /// **'{count} von {max} beigetreten'**
  String inviteGroupUses(int count, int max);

  /// No description provided for @inviteGroupFull.
  ///
  /// In de, this message translates to:
  /// **'Der Link ist voll: Niemand kann mehr damit beitreten.'**
  String get inviteGroupFull;

  /// No description provided for @inviteGroupRevoked.
  ///
  /// In de, this message translates to:
  /// **'Link widerrufen: Niemand kann mehr damit beitreten.'**
  String get inviteGroupRevoked;

  /// No description provided for @inviteGroupRevoke.
  ///
  /// In de, this message translates to:
  /// **'Link widerrufen'**
  String get inviteGroupRevoke;

  /// No description provided for @inviteGroupRenew.
  ///
  /// In de, this message translates to:
  /// **'Neuen Link erstellen'**
  String get inviteGroupRenew;

  /// No description provided for @inviteGroupRevokeTitle.
  ///
  /// In de, this message translates to:
  /// **'Gruppenlink widerrufen?'**
  String get inviteGroupRevokeTitle;

  /// No description provided for @inviteGroupRevokeBody.
  ///
  /// In de, this message translates to:
  /// **'Mit dem Link kann dann niemand mehr beitreten. Wer schon dabei ist, bleibt im Haushalt.'**
  String get inviteGroupRevokeBody;

  /// No description provided for @inviteGroupRevokeConfirm.
  ///
  /// In de, this message translates to:
  /// **'Widerrufen'**
  String get inviteGroupRevokeConfirm;

  /// No description provided for @inviteGroupRenewTitle.
  ///
  /// In de, this message translates to:
  /// **'Neuen Link erstellen?'**
  String get inviteGroupRenewTitle;

  /// No description provided for @inviteGroupRenewBody.
  ///
  /// In de, this message translates to:
  /// **'Der bisherige Link funktioniert dann nicht mehr. Wer schon dabei ist, bleibt im Haushalt.'**
  String get inviteGroupRenewBody;

  /// Job 169b W2: screen-reader label of the group link's QR code
  ///
  /// In de, this message translates to:
  /// **'QR-Code des Gruppenlinks'**
  String get inviteGroupQr;

  /// No description provided for @inviteJoinsTitle.
  ///
  /// In de, this message translates to:
  /// **'Wer ist beigetreten'**
  String get inviteJoinsTitle;

  /// No description provided for @inviteJoinsEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch niemand.'**
  String get inviteJoinsEmpty;

  /// Job 169b W2: when someone joined with the group link
  ///
  /// In de, this message translates to:
  /// **'am {date}'**
  String inviteJoinedOn(DateTime date);

  /// Job 169b W2: the share text by the household's kind (other: not asked); always link and code. The user sends it (N-18).
  ///
  /// In de, this message translates to:
  /// **'{kind, select, partner{Ich hab unsere Einkaufsliste in Snacklist angelegt. Komm dazu: {link} · Code: {code}} family{Unsere Familien-Einkaufsliste „{name}“ ist jetzt in Snacklist. Komm dazu: {link} · Code: {code}} flat{Unsere WG-Einkaufsliste „{name}“ ist jetzt in Snacklist. Komm dazu: {link} · Code: {code}} club{Wir planen die Einkäufe für „{name}“ in Snacklist. Mach mit: {link} · Code: {code}} solo{Ich teile meine Einkaufsliste „{name}“ in Snacklist mit dir: {link} · Code: {code}} other{Komm in unseren Snacklist-Haushalt: {link} · Code: {code}}}'**
  String inviteShareKind(String kind, String name, String link, String code);

  /// Job 169b W2: role label of the member who created the household. Gender-neutral and short: der/die Hauptadmin; ranks above Admin (names admins, can't be removed)
  ///
  /// In de, this message translates to:
  /// **'Hauptadmin'**
  String get householdRoleOwner;

  /// Job 169b W2: role label of an admin (removes members, makes group links)
  ///
  /// In de, this message translates to:
  /// **'Admin'**
  String get householdRoleAdmin;

  /// Job 169b W2: tooltip of a member row's menu on the household page
  ///
  /// In de, this message translates to:
  /// **'Optionen für {name}'**
  String memberActions(String name);

  /// No description provided for @memberMakeAdmin.
  ///
  /// In de, this message translates to:
  /// **'Zum Admin machen'**
  String get memberMakeAdmin;

  /// No description provided for @memberRemoveAdmin.
  ///
  /// In de, this message translates to:
  /// **'Adminrechte entziehen'**
  String get memberRemoveAdmin;

  /// No description provided for @memberRemove.
  ///
  /// In de, this message translates to:
  /// **'Aus dem Haushalt entfernen'**
  String get memberRemove;

  /// No description provided for @memberRemoveTitle.
  ///
  /// In de, this message translates to:
  /// **'{name} entfernen?'**
  String memberRemoveTitle(String name);

  /// No description provided for @memberRemoveBody.
  ///
  /// In de, this message translates to:
  /// **'{name} sieht die Liste von „{household}“ dann nicht mehr und kommt über bisherige Einladungen oder den jetzigen Gruppenlink nicht zurück. In den nächsten 30 Tagen holt {name} nur eine neue Einladung oder ein neuer Gruppenlink von einem Admin zurück.'**
  String memberRemoveBody(String name, String household);

  /// No description provided for @memberRemoveConfirm.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get memberRemoveConfirm;

  /// Job 169b W2: shown once per device for each removal of the last 30 days the server reports (my_household_removals), also right after signing in. Wording from Legal (job 178, N-114, 2026-11-10): the 30-day rule; change only with Legal
  ///
  /// In de, this message translates to:
  /// **'Du wurdest aus dem Haushalt „{name}“ entfernt. 30 Tage lang kommst du über alte Einladungen nicht zurück. Beitreten kannst du in dieser Zeit nur über eine neue Einladung vom Hauptadmin oder einem Admin.'**
  String householdRemovedNotice(String name);

  /// Job 178: shown when a refresh finds a household gone that nobody removed the user from in the last 30 days (left on another device, a removal long ago). Never the 30-day rule: it does not apply
  ///
  /// In de, this message translates to:
  /// **'Du bist nicht mehr Mitglied von „{name}“.'**
  String householdGoneNotice(String name);

  /// No description provided for @householdNotAdmin.
  ///
  /// In de, this message translates to:
  /// **'Das können nur Admins.'**
  String get householdNotAdmin;

  /// No description provided for @householdCannotRemove.
  ///
  /// In de, this message translates to:
  /// **'Diese Person kannst du nicht entfernen.'**
  String get householdCannotRemove;

  /// Job 169b W2: start screens; reads the clipboard only on this tap
  ///
  /// In de, this message translates to:
  /// **'Einladung einfügen'**
  String get invitePaste;

  /// No description provided for @invitePasteNothing.
  ///
  /// In de, this message translates to:
  /// **'In der Zwischenablage ist kein Einladungslink und kein Code.'**
  String get invitePasteNothing;

  /// No description provided for @invitePasteWaiting.
  ///
  /// In de, this message translates to:
  /// **'Einladung gemerkt. Melde dich an, dann trittst du bei.'**
  String get invitePasteWaiting;

  /// No description provided for @householdNotOwner.
  ///
  /// In de, this message translates to:
  /// **'Admins ernennt nur, wer den Haushalt angelegt hat.'**
  String get householdNotOwner;

  /// Job 169b K: household page section and the list tabs' group label
  ///
  /// In de, this message translates to:
  /// **'Listen'**
  String get listsTitle;

  /// Job 169b K: the list every household starts with, exactly as the server names it in German (lists.seed_key main)
  ///
  /// In de, this message translates to:
  /// **'Einkaufsliste'**
  String get listMain;

  /// Job 169b K: the tabs' + button, the household page's add row and the name dialog's title
  ///
  /// In de, this message translates to:
  /// **'Neue Liste'**
  String get listNew;

  /// Job 169b K: label of the name field when adding or renaming a list
  ///
  /// In de, this message translates to:
  /// **'Name der Liste'**
  String get listNameLabel;

  /// Job 169b K: screen reader announcement after adding a list
  ///
  /// In de, this message translates to:
  /// **'Liste „{name}“ angelegt'**
  String listAdded(String name);

  /// Job 169b K: rename dialog title
  ///
  /// In de, this message translates to:
  /// **'Liste umbenennen'**
  String get listRenameTitle;

  /// Job 169b K: household page, tooltip of a list's menu
  ///
  /// In de, this message translates to:
  /// **'Aktionen für „{name}“'**
  String listActions(String name);

  /// Job 169b K: list menu, move the list one up
  ///
  /// In de, this message translates to:
  /// **'Nach oben'**
  String get listMoveUp;

  /// Job 169b K: list menu, move the list one down
  ///
  /// In de, this message translates to:
  /// **'Nach unten'**
  String get listMoveDown;

  /// Job 169b K: delete confirmation title
  ///
  /// In de, this message translates to:
  /// **'„{name}“ löschen?'**
  String listDeleteTitle(String name);

  /// Job 169b K: delete confirmation, how many open items go with the list
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Auf der Liste ist nichts offen.} =1{Der 1 offene Artikel darauf wird mit gelöscht.} other{Die {count} offenen Artikel darauf werden mit gelöscht.}}'**
  String listDeleteBody(int count);

  /// Job 169b K: list add/rename/move/delete while offline
  ///
  /// In de, this message translates to:
  /// **'Listen lassen sich nur mit Verbindung anlegen, umbenennen, sortieren oder löschen.'**
  String get listsNeedConnection;

  /// Job 169b K: an item moved to a list where it is open already stays
  ///
  /// In de, this message translates to:
  /// **'„{name}“ steht schon auf „{list}“.'**
  String onListAlready(String name, String list);

  /// Job 169b K: edit sheet, label over the list picker
  ///
  /// In de, this message translates to:
  /// **'Liste'**
  String get editList;

  /// Job 169b L: edit sheet checkbox, the user says they bring the item
  ///
  /// In de, this message translates to:
  /// **'Ich bringe das'**
  String get claimMine;

  /// Job 169b L: edit sheet, label of the optional amount the user brings
  ///
  /// In de, this message translates to:
  /// **'Wie viel?'**
  String get claimAmount;

  /// Job 169b L: edit sheet, example in the amount field
  ///
  /// In de, this message translates to:
  /// **'z. B. 2'**
  String get claimAmountHint;

  /// Job 169b L: row line, a member brings the item
  ///
  /// In de, this message translates to:
  /// **'{name} bringt'**
  String claimBy(String name);

  /// Job 169b L: row line, a member brings an amount
  ///
  /// In de, this message translates to:
  /// **'{name} bringt {amount}'**
  String claimByAmount(String name, String amount);

  /// Job 169b L: row line, the user brings the item
  ///
  /// In de, this message translates to:
  /// **'Du bringst'**
  String get claimYou;

  /// Job 169b L: row line, the user brings an amount
  ///
  /// In de, this message translates to:
  /// **'Du bringst {amount}'**
  String claimYouAmount(String amount);

  /// Job 169b L: row line, a claimant the list cannot name yet
  ///
  /// In de, this message translates to:
  /// **'Jemand'**
  String get claimSomeone;

  /// Job 169b W3 M: the joiner's waiting screen after accept_invite answered requested
  ///
  /// In de, this message translates to:
  /// **'Anfrage gesendet: Ein Admin von „{name}“ bestätigt deinen Beitritt.'**
  String joinRequestSent(String name);

  /// Job 169b W3 M: accept_invite answered declined_recently, the user's request to this household was declined in the last 24 hours. Neutral, no blame
  ///
  /// In de, this message translates to:
  /// **'Deine Anfrage für diesen Haushalt wurde vor Kurzem abgelehnt. Du kannst nach 24 Stunden wieder anfragen.'**
  String get joinDeclinedRecently;

  /// Job 169b W3 M: waiting screen
  ///
  /// In de, this message translates to:
  /// **'Anfrage zurückziehen'**
  String get joinRequestWithdraw;

  /// Job 169b W3 M: waiting screen, for someone in a household already
  ///
  /// In de, this message translates to:
  /// **'Zur Liste'**
  String get joinRequestToList;

  /// Job 169b W3 M: waiting screen without a household: create one instead of waiting
  ///
  /// In de, this message translates to:
  /// **'Eigenen Haushalt anlegen'**
  String get joinRequestCreateOwn;

  /// Job 169b W3 M: an admin approved the user's join request; the household shows
  ///
  /// In de, this message translates to:
  /// **'Du bist jetzt in „{name}“.'**
  String joinApprovedNotice(String name);

  /// Job 169b W3 M: an admin declined the user's join request
  ///
  /// In de, this message translates to:
  /// **'Deine Anfrage für „{name}“ wurde nicht angenommen.'**
  String joinDeclinedNotice(String name);

  /// Job 169b W3 M: switcher, a household the user asked to join
  ///
  /// In de, this message translates to:
  /// **'Anfrage offen'**
  String get joinRequestPending;

  /// Job 169b W3 M: switcher, dialog title after tapping a pending request's row
  ///
  /// In de, this message translates to:
  /// **'Anfrage für „{name}“ zurückziehen?'**
  String joinRequestWithdrawFor(String name);

  /// Job 169b W3 M: household page switch (owner and admins)
  ///
  /// In de, this message translates to:
  /// **'Beitritte bestätigen'**
  String get joinApprovalToggle;

  /// Job 169b W3 M: one line under the switch
  ///
  /// In de, this message translates to:
  /// **'Neue Leute warten, bis ein Admin sie aufnimmt.'**
  String get joinApprovalHint;

  /// Job 169b W3 M: household page section (owner and admins)
  ///
  /// In de, this message translates to:
  /// **'Beitrittsanfragen'**
  String get joinRequestsTitle;

  /// Job 169b W3 M: screen reader label of the count badge
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 offene Anfrage} other{{count} offene Anfragen}}'**
  String joinRequestsCount(int count);

  /// Job 169b W3 M: household page, approval on and nobody waiting
  ///
  /// In de, this message translates to:
  /// **'Keine offenen Anfragen.'**
  String get joinRequestsNone;

  /// Job 169b W3 M: household page, the requests did not load
  ///
  /// In de, this message translates to:
  /// **'Anfragen konnten nicht geladen werden.'**
  String get joinRequestsFailed;

  /// Job 169b W3 M: household page, let a requester in
  ///
  /// In de, this message translates to:
  /// **'Aufnehmen'**
  String get joinRequestApprove;

  /// Job 169b W3 M: under a request whose group link or person invite has no use left (decide_join_request invite_full); the request stays open until the person opens a new link
  ///
  /// In de, this message translates to:
  /// **'Die Einladung zu dieser Anfrage ist voll. Schick einen neuen Link. Sobald er geöffnet ist, kannst du aufnehmen.'**
  String get joinRequestInviteFull;

  /// Job 169b W3 M: household page, turn a requester away
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get joinRequestDecline;

  /// Hint invite-partner (job 168b): title
  ///
  /// In de, this message translates to:
  /// **'Gemeinsam einkaufen'**
  String get hintInviteTitle;

  /// Hint invite-partner: shown to a household's only member after a day with 3 items
  ///
  /// In de, this message translates to:
  /// **'Lade jemanden ein, um die Liste gemeinsam zu nutzen.'**
  String get hintInviteBody;

  /// Hint invite-partner and the Erste Schritte invite item: button that opens More → Einladungen
  ///
  /// In de, this message translates to:
  /// **'Einladen'**
  String get hintInviteAction;

  /// Hint store-order (job 168b): title of the callout under Anpassen
  ///
  /// In de, this message translates to:
  /// **'Sortiert wie dein Laden'**
  String get hintStoreOrderTitle;

  /// Hint store-order: callout under the Anpassen button after the first finished shop; 'Hier' is Anpassen
  ///
  /// In de, this message translates to:
  /// **'Hier kannst du die Kategorien so sortieren, wie du durch den Laden gehst.'**
  String get hintStoreOrderBody;

  /// Hint add-store (job 168b): title of the callout under Anpassen
  ///
  /// In de, this message translates to:
  /// **'Noch ein Laden?'**
  String get hintAddStoreTitle;

  /// Hint add-store: callout under the Anpassen button for a household without a store; 'Hier' is Anpassen
  ///
  /// In de, this message translates to:
  /// **'Hier kannst du weitere Läden anlegen, bei denen du einkaufst.'**
  String get hintAddStoreBody;

  /// Hint dictation (job 168b, iPhone and Android): title of the card at the top of the list
  ///
  /// In de, this message translates to:
  /// **'Sag einfach, was fehlt'**
  String get hintDictationTitle;

  /// Hint dictation: card at the top of the list after 10 typed adds
  ///
  /// In de, this message translates to:
  /// **'Tipp aufs Mikrofon und sprich: „Milch, zwei Gurken und Klopapier“.'**
  String get hintDictationBody;

  /// Hint ai-assistant (job 168b): title
  ///
  /// In de, this message translates to:
  /// **'Noch besser mit KI & Automationen'**
  String get hintAssistantTitle;

  /// Hint ai-assistant: for clubs, or after 7 active days on the web or a computer
  ///
  /// In de, this message translates to:
  /// **'Lass deinen KI-Assistenten deine Liste verwalten oder nutze die API, um Automationen zu erstellen.'**
  String get hintAssistantBody;

  /// Hint ai-assistant: button that opens More → Zugänge
  ///
  /// In de, this message translates to:
  /// **'Zugänge verwalten'**
  String get hintAssistantAction;

  /// Hint siri (job 168b, iPhone): title
  ///
  /// In de, this message translates to:
  /// **'Mit Siri hinzufügen'**
  String get hintSiriTitle;

  /// Hint siri: a native Siri App Shortcut phrase (app/ios/Runner/AppShortcuts.xcstrings, Add to Snacklist)
  ///
  /// In de, this message translates to:
  /// **'Sag „Hey Siri, füge etwas zu Snacklist hinzu“, wenn die Hände voll sind.'**
  String get hintSiriBody;

  /// Hint home-widget (job 168b, iPhone and Android): title
  ///
  /// In de, this message translates to:
  /// **'Liste auf dem Home-Bildschirm'**
  String get hintWidgetTitle;

  /// Hint home-widget: how to place the widget, after 5 active days
  ///
  /// In de, this message translates to:
  /// **'Füge das Snacklist-Widget hinzu, indem du den Home-Bildschirm deines Smartphones gedrückt hältst.'**
  String get hintWidgetBody;

  /// Hint own-household (job 168b): title, for someone who joined another person's household
  ///
  /// In de, this message translates to:
  /// **'Deine eigene Liste'**
  String get hintOwnHouseholdTitle;

  /// Hint own-household: shows only once the app can create a second household (job 169b)
  ///
  /// In de, this message translates to:
  /// **'Diesen Haushalt hat jemand anderes angelegt. Leg auch einen eigenen an, zum Beispiel nur für dich.'**
  String get hintOwnHouseholdBody;

  /// Hint second-household (job 168b): title
  ///
  /// In de, this message translates to:
  /// **'Noch eine Liste?'**
  String get hintSecondHouseholdTitle;

  /// Hint second-household: shows only once the app can create a second household (job 169b)
  ///
  /// In de, this message translates to:
  /// **'Für den Verein oder die WG: Leg einen zweiten Haushalt an.'**
  String get hintSecondHouseholdBody;

  /// Hints own-household and second-household: button that opens the household creation flow
  ///
  /// In de, this message translates to:
  /// **'Haushalt erstellen'**
  String get hintAddHouseholdAction;

  /// Snackbar for 3 s after the X on a hint (job 168b): where every hint can be read again
  ///
  /// In de, this message translates to:
  /// **'Alle Tipps unter Mehr → Tipps.'**
  String get hintDismissedNotice;

  /// More: the row and page that list every hint (job 168b)
  ///
  /// In de, this message translates to:
  /// **'Tipps'**
  String get hintsTitle;

  /// List tab checklist card (job 168b): title; it takes the gesture card's place
  ///
  /// In de, this message translates to:
  /// **'Erste Schritte'**
  String get checklistTitle;

  /// Checklist card: tooltip and screen reader label of the X that hides it for this household
  ///
  /// In de, this message translates to:
  /// **'Erste Schritte ausblenden'**
  String get checklistDismiss;

  /// Checklist card: how many items are done, under the title
  ///
  /// In de, this message translates to:
  /// **'{done} von {total}'**
  String checklistProgress(int done, int total);

  /// Checklist item, always done: the user created the household
  ///
  /// In de, this message translates to:
  /// **'Liste angelegt'**
  String get checklistStarted;

  /// Checklist item, always done: the user joined someone else's household
  ///
  /// In de, this message translates to:
  /// **'Haushalt beigetreten'**
  String get checklistJoined;

  /// Checklist item: invite someone; kind is the household's answer to Mit wem kaufst du ein? (partner, family, flat, club, other)
  ///
  /// In de, this message translates to:
  /// **'{kind, select, partner{Partner·in einladen} family{Familie einladen} flat{Mitbewohner einladen} club{Mitglieder einladen} other{Jemanden einladen}}'**
  String checklistInvite(String kind);

  /// Checklist item invite: the line under it; done once a second member joined
  ///
  /// In de, this message translates to:
  /// **'{kind, select, club{Alle sehen dieselbe Liste und können selbst etwas draufsetzen.} other{Sieht deine Artikel sofort und kann selbst etwas draufsetzen.}}'**
  String checklistInviteBody(String kind);

  /// Checklist item: done once the user ticks an item off or saves an edit; listHint is the line under it
  ///
  /// In de, this message translates to:
  /// **'Einmal einkaufen'**
  String get checklistShop;

  /// Checklist item for clubs: connect an AI assistant
  ///
  /// In de, this message translates to:
  /// **'KI-Assistenten verbinden'**
  String get checklistAssistant;

  /// Checklist item KI-Assistenten verbinden: the line under it
  ///
  /// In de, this message translates to:
  /// **'Mehr → Zugänge. Er setzt Dinge auf eure Liste.'**
  String get checklistAssistantBody;

  /// Checklist item KI-Assistenten verbinden: button that opens More → Zugänge
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get checklistOpen;

  /// Checklist: screen reader label of a done item; step is its title
  ///
  /// In de, this message translates to:
  /// **'{step}, erledigt'**
  String checklistDone(String step);

  /// The History tab (job 199, flag grocery-log): the household's logged shopping trips; also the screen's title
  ///
  /// In de, this message translates to:
  /// **'Verlauf'**
  String get tabHistory;

  /// History header: tooltip of the button that switches the journal by date to the view by store
  ///
  /// In de, this message translates to:
  /// **'Nach Laden anzeigen'**
  String get historyShowByStore;

  /// History header: tooltip of the button that switches the view by store back to the journal by date
  ///
  /// In de, this message translates to:
  /// **'Nach Datum anzeigen'**
  String get historyShowByDate;

  /// History: title of the sheet for a new trip and the buttons that open it; also the header button's screen reader label
  ///
  /// In de, this message translates to:
  /// **'Einkauf eintragen'**
  String get tripAdd;

  /// History header: the short label of the button that opens Einkauf eintragen
  ///
  /// In de, this message translates to:
  /// **'Eintragen'**
  String get tripAddShort;

  /// History: title of the sheet for an existing trip
  ///
  /// In de, this message translates to:
  /// **'Einkauf bearbeiten'**
  String get tripEdit;

  /// History by store: tooltip of a store's + button, which opens the sheet with that store picked
  ///
  /// In de, this message translates to:
  /// **'Einkauf bei {store} eintragen'**
  String tripAddAt(String store);

  /// History without any trip: the title. Never promise that it is free
  ///
  /// In de, this message translates to:
  /// **'Noch keine Einkäufe'**
  String get historyEmptyTitle;

  /// History without any trip: the line under the title
  ///
  /// In de, this message translates to:
  /// **'Trag nach dem Einkauf ein, was du gekauft hast. So findet ihr später, wann ihr wo was geholt habt.'**
  String get historyEmptyBody;

  /// History: the trips could not be loaded; a retry button follows
  ///
  /// In de, this message translates to:
  /// **'Der Verlauf konnte nicht geladen werden.'**
  String get historyLoadFailed;

  /// History journal: section of the trips since Monday
  ///
  /// In de, this message translates to:
  /// **'Diese Woche'**
  String get historyThisWeek;

  /// History journal: section of last Monday-to-Sunday week's trips
  ///
  /// In de, this message translates to:
  /// **'Letzte Woche'**
  String get historyLastWeek;

  /// History journal: above the trips of the calendar day the user tapped
  ///
  /// In de, this message translates to:
  /// **'Einkäufe am {day}'**
  String historyDayFilter(DateTime day);

  /// History journal: tooltip of the X that ends showing one day's trips
  ///
  /// In de, this message translates to:
  /// **'Alle Einkäufe zeigen'**
  String get historyDayClear;

  /// History journal: the tapped calendar day has no trip
  ///
  /// In de, this message translates to:
  /// **'Keine Einkäufe an diesem Tag'**
  String get historyDayEmpty;

  /// History calendar: screen reader label of a day with trips; date is like Donnerstag, 12. November
  ///
  /// In de, this message translates to:
  /// **'{date}, {count, plural, =1{1 Einkauf} other{{count} Einkäufe}}'**
  String historyDayLabel(String date, int count);

  /// History by store: a store without any trip
  ///
  /// In de, this message translates to:
  /// **'Noch kein Einkauf'**
  String get historyStoreEmpty;

  /// History, Free with trips older than 4 weeks: the quiet locked row at the end of the journal and the store view, and under the calendar. Opens the Premium page where it is sold. No prices; never say the history is free
  ///
  /// In de, this message translates to:
  /// **'Ältere Einkäufe siehst du mit Snacklist Premium'**
  String get historyLockedTitle;

  /// History, locked row: how many older trips are kept but not shown
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 älterer Einkauf} other{{count} ältere Einkäufe}}'**
  String historyLockedCount(int count);

  /// History calendar: screen reader label of a day before the 4-week window (Free); date is like Donnerstag, 12. Oktober
  ///
  /// In de, this message translates to:
  /// **'{date}, ältere Einkäufe mit Snacklist Premium'**
  String historyDayLocked(String date);

  /// Trip sheet: under the store chips after Speichern while no store is picked, not even Ohne Laden
  ///
  /// In de, this message translates to:
  /// **'Wähle einen Laden.'**
  String get tripStoreMissing;

  /// Trip sheet: under the store chips when the trip's store was deleted from the household; its chip keeps the saved name
  ///
  /// In de, this message translates to:
  /// **'Dieser Laden wurde gelöscht.'**
  String get tripStoreGone;

  /// History calendar: tooltip of the button to the month before
  ///
  /// In de, this message translates to:
  /// **'Vorheriger Monat'**
  String get previousMonth;

  /// History calendar: tooltip of the button to the month after; off at the current month
  ///
  /// In de, this message translates to:
  /// **'Nächster Monat'**
  String get nextMonth;

  /// A trip's day when it is today
  ///
  /// In de, this message translates to:
  /// **'Heute'**
  String get dayToday;

  /// A trip's day when it was yesterday
  ///
  /// In de, this message translates to:
  /// **'Gestern'**
  String get dayYesterday;

  /// Trip sheet: label above the store choice
  ///
  /// In de, this message translates to:
  /// **'Laden'**
  String get tripStore;

  /// Trip sheet: label above the day choice
  ///
  /// In de, this message translates to:
  /// **'Wann'**
  String get tripDay;

  /// Trip sheet: the day choice that opens a date picker
  ///
  /// In de, this message translates to:
  /// **'Anderer Tag'**
  String get tripOtherDay;

  /// Trip sheet: label above the bought items
  ///
  /// In de, this message translates to:
  /// **'Gekauft'**
  String get tripItems;

  /// Trip sheet: placeholder of an item's name field
  ///
  /// In de, this message translates to:
  /// **'Artikel'**
  String get tripItemName;

  /// Trip sheet: button that adds an item row
  ///
  /// In de, this message translates to:
  /// **'Artikel hinzufügen'**
  String get tripAddItem;

  /// Trip sheet: screen reader label of the X that removes an item row
  ///
  /// In de, this message translates to:
  /// **'{name} entfernen'**
  String tripRemoveItem(String name);

  /// Trip sheet, editing: button that deletes the trip after a confirmation
  ///
  /// In de, this message translates to:
  /// **'Einkauf löschen'**
  String get tripDelete;

  /// Trip delete confirmation: title
  ///
  /// In de, this message translates to:
  /// **'Einkauf löschen?'**
  String get tripDeleteTitle;

  /// Trip delete confirmation: body
  ///
  /// In de, this message translates to:
  /// **'Der Einkauf verschwindet für alle im Haushalt aus dem Verlauf.'**
  String get tripDeleteBody;

  /// Trip sheet, above its buttons: deleting a trip failed; the sheet stays open
  ///
  /// In de, this message translates to:
  /// **'Der Einkauf konnte nicht gelöscht werden. Versuch es noch mal.'**
  String get tripDeleteFailed;

  /// Trip sheet, above its buttons: saving a trip failed; the sheet stays open with what was typed
  ///
  /// In de, this message translates to:
  /// **'Der Einkauf konnte nicht gespeichert werden. Versuch es noch mal.'**
  String get tripSaveFailed;

  /// History: how many items a trip has
  ///
  /// In de, this message translates to:
  /// **'{count} Artikel'**
  String tripItemCount(int count);

  /// History: a trip's first three item names and how many more
  ///
  /// In de, this message translates to:
  /// **'{names} und {count} mehr'**
  String tripSummaryMore(String names, int count);

  /// Job 190: ghost chip on a row without today's price, after a plus icon
  ///
  /// In de, this message translates to:
  /// **'Preis'**
  String get priceAdd;

  /// Job 190: screen reader label of the chip that opens the price of an item without one
  ///
  /// In de, this message translates to:
  /// **'Preis für {name}'**
  String priceChipEmpty(String name);

  /// Job 190: screen reader label of a row's price chip; amount is the formatted line total
  ///
  /// In de, this message translates to:
  /// **'Preis für {name}: {amount}, ändern'**
  String priceChipSet(String name, String amount);

  /// Job 190: price field in the open row, its screen reader name
  ///
  /// In de, this message translates to:
  /// **'Preis'**
  String get priceField;

  /// Job 190: weight field for prices per kg, its screen reader name
  ///
  /// In de, this message translates to:
  /// **'Gewicht in kg'**
  String get weightField;

  /// Job 190: basis toggle, the typed price is per piece
  ///
  /// In de, this message translates to:
  /// **'pro Stück'**
  String get pricePerPiece;

  /// Job 190: basis toggle, the typed price is per kg
  ///
  /// In de, this message translates to:
  /// **'pro kg'**
  String get pricePerKg;

  /// Job 190: basis toggle and hint, the price is per litre
  ///
  /// In de, this message translates to:
  /// **'pro l'**
  String get pricePerLitre;

  /// Job 190: unit choice, litre
  ///
  /// In de, this message translates to:
  /// **'l'**
  String get priceUnitLitre;

  /// Job 190: volume field for prices per litre, its screen reader name
  ///
  /// In de, this message translates to:
  /// **'Menge in l'**
  String get volumeField;

  /// Job 190: volume field error
  ///
  /// In de, this message translates to:
  /// **'Gib die Menge ein.'**
  String get volumeErrorEmpty;

  /// Job 190: volume field error
  ///
  /// In de, this message translates to:
  /// **'Die Menge muss über 0 ml liegen.'**
  String get volumeErrorZero;

  /// Job 190: volume field error
  ///
  /// In de, this message translates to:
  /// **'Höchstens 50 l.'**
  String get volumeErrorTooLarge;

  /// Job 190: basis toggle, the typed price is the line's total
  ///
  /// In de, this message translates to:
  /// **'Gesamt'**
  String get priceLine;

  /// Job 190: screen reader name of the basis toggle
  ///
  /// In de, this message translates to:
  /// **'Preis gilt'**
  String get priceBasisLabel;

  /// Job 190: unit choice
  ///
  /// In de, this message translates to:
  /// **'Stück'**
  String get priceUnitPiece;

  /// Job 190: unit choice
  ///
  /// In de, this message translates to:
  /// **'kg'**
  String get priceUnitKg;

  /// Job 190: screen reader name of the unit choice
  ///
  /// In de, this message translates to:
  /// **'Einheit'**
  String get priceUnitLabel;

  /// Job 190: quantity stepper, minus button
  ///
  /// In de, this message translates to:
  /// **'Eins weniger'**
  String get priceCountLess;

  /// Job 190: quantity stepper, plus button
  ///
  /// In de, this message translates to:
  /// **'Eins mehr'**
  String get priceCountMore;

  /// Job 190: quantity stepper value for screen readers
  ///
  /// In de, this message translates to:
  /// **'Menge {count}'**
  String priceCount(int count);

  /// Job 190: hint under the price field when a unit price is typed
  ///
  /// In de, this message translates to:
  /// **'Zusammen {amount}'**
  String priceTogether(String amount);

  /// Job 190: hint under the price field when a total is typed; per is pro Stück, pro Pack or pro kg
  ///
  /// In de, this message translates to:
  /// **'Das sind {amount} {per}'**
  String priceUnitIs(String amount, String per);

  /// Job 190: hint, the list's total once this price is saved
  ///
  /// In de, this message translates to:
  /// **'Summe danach {amount}'**
  String priceTotalAfter(String amount);

  /// Job 190: hint, unit price compared with last time's
  ///
  /// In de, this message translates to:
  /// **'{amount} teurer als zuletzt'**
  String priceDearer(String amount);

  /// Job 190: hint, unit price compared with last time's
  ///
  /// In de, this message translates to:
  /// **'{amount} billiger als zuletzt'**
  String priceCheaper(String amount);

  /// Job 190: hint, unit price the same as last time
  ///
  /// In de, this message translates to:
  /// **'Wie zuletzt'**
  String get priceSame;

  /// Job 190: price field error
  ///
  /// In de, this message translates to:
  /// **'Gib einen Preis ein.'**
  String get priceErrorEmpty;

  /// Job 190: price field error for a line beyond the limits; min and max are -9999,00 and 9999,00 in the household currency
  ///
  /// In de, this message translates to:
  /// **'Zwischen {min} und {max} pro Artikel.'**
  String priceErrorTooLarge(String min, String max);

  /// Job 190: weight field error
  ///
  /// In de, this message translates to:
  /// **'Gib das Gewicht ein.'**
  String get weightErrorEmpty;

  /// Job 190: weight field error
  ///
  /// In de, this message translates to:
  /// **'Das Gewicht muss über 0 g liegen.'**
  String get weightErrorZero;

  /// Job 190: weight field error
  ///
  /// In de, this message translates to:
  /// **'Höchstens 50 kg.'**
  String get weightErrorTooLarge;

  /// Job 190: button in the open row that clears the item's price
  ///
  /// In de, this message translates to:
  /// **'Preis entfernen'**
  String get priceRemove;

  /// Job 190: total bar title
  ///
  /// In de, this message translates to:
  /// **'Einkaufssumme'**
  String get tripTotal;

  /// Job 190: total bar, items with a price and open items without one
  ///
  /// In de, this message translates to:
  /// **'{priced} mit Preis · {open} offen'**
  String tripCounts(int priced, int open);

  /// Job 190: total bar for screen readers
  ///
  /// In de, this message translates to:
  /// **'Einkaufssumme {amount}, {priced} mit Preis, {open} offen'**
  String tripTotalLabel(String amount, int priced, int open);

  /// Job 190: line at the end of a store section
  ///
  /// In de, this message translates to:
  /// **'Summe {store} {amount}'**
  String storeSubtotal(String store, String amount);

  /// Job 190: household page section and row
  ///
  /// In de, this message translates to:
  /// **'Währung'**
  String get currencyTitle;

  /// Job 190: household page, under the currency
  ///
  /// In de, this message translates to:
  /// **'Für Preise und die Einkaufssumme, für alle im Haushalt'**
  String get currencyHint;

  /// Job 190: title of the currency picker
  ///
  /// In de, this message translates to:
  /// **'Währung wählen'**
  String get currencyPick;

  /// Job 229 (flag list-declutter): screen reader hint of the switcher top left of the list, which shows the household and the list and opens the switcher sheet
  ///
  /// In de, this message translates to:
  /// **'Liste oder Haushalt wechseln'**
  String get listSwitch;

  /// Job 229: switcher sheet, the back row from a household's page to the households
  ///
  /// In de, this message translates to:
  /// **'Haushalte'**
  String get switcherHouseholds;

  /// Job 229: switcher sheet, screen reader label of the back row; page is where it goes ("Haushalte" or the household's name)
  ///
  /// In de, this message translates to:
  /// **'Zurück: {page}'**
  String switcherBack(String page);

  /// Job 229: switcher sheet, the labeled button beside the household's name that opens the invite sheet
  ///
  /// In de, this message translates to:
  /// **'Einladen'**
  String get switcherInvite;

  /// Job 229: switcher sheet, the members row after the member count, e.g. "3 Mitglieder · 1 Einladung offen"
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Einladung offen} other{{count} Einladungen offen}}'**
  String switcherOpenInvites(int count);

  /// Job 229: switcher sheet's members page, section of the person invites not used yet
  ///
  /// In de, this message translates to:
  /// **'Offene Einladungen'**
  String get switcherOpenInvitesTitle;

  /// Job 234 trip mode: the sheet after an own tick while no trip runs
  ///
  /// In de, this message translates to:
  /// **'Kaufst du gerade ein?'**
  String get shopAskTitle;

  /// No description provided for @shopAskBody.
  ///
  /// In de, this message translates to:
  /// **'Dann läuft eine Uhr mit, und am Ende siehst du, was geplant war und was dazukam.'**
  String get shopAskBody;

  /// No description provided for @shopAskYes.
  ///
  /// In de, this message translates to:
  /// **'Ja, Einkauf starten'**
  String get shopAskYes;

  /// No description provided for @shopAskNo.
  ///
  /// In de, this message translates to:
  /// **'Nein, nur abgehakt'**
  String get shopAskNo;

  /// Job 234: above the take-back link in the sheet
  ///
  /// In de, this message translates to:
  /// **'Aus Versehen abgehakt?'**
  String get shopAskMistake;

  /// No description provided for @shopAskTakeBack.
  ///
  /// In de, this message translates to:
  /// **'Zurücknehmen'**
  String get shopAskTakeBack;

  /// Job 234: the running trip's strip
  ///
  /// In de, this message translates to:
  /// **'Einkauf läuft'**
  String get shopRunning;

  /// No description provided for @shopPaused.
  ///
  /// In de, this message translates to:
  /// **'Pausiert'**
  String get shopPaused;

  /// Job 234: the strip after 45 minutes without a tick; time is the last tick, HH:MM
  ///
  /// In de, this message translates to:
  /// **'Pause · seit {time} nichts abgehakt'**
  String shopAutoPaused(String time);

  /// No description provided for @shopPause.
  ///
  /// In de, this message translates to:
  /// **'Pause'**
  String get shopPause;

  /// No description provided for @shopResume.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get shopResume;

  /// No description provided for @shopEnd.
  ///
  /// In de, this message translates to:
  /// **'Beenden'**
  String get shopEnd;

  /// Job 234: auto-paused, ends the trip at the last tick
  ///
  /// In de, this message translates to:
  /// **'Beenden um {time}'**
  String shopEndAt(String time);

  /// Job 234: the stopwatch for screen readers, read per minute
  ///
  /// In de, this message translates to:
  /// **'{minutes, plural, =0{seit weniger als einer Minute} =1{seit 1 Minute} other{seit {minutes} Minuten}}'**
  String shopClockLabel(int minutes);

  /// Job 234: the list's card after the 4-hour rule ended a trip
  ///
  /// In de, this message translates to:
  /// **'Einkauf automatisch beendet'**
  String get shopAutoEndedTitle;

  /// No description provided for @shopAutoEndedBody.
  ///
  /// In de, this message translates to:
  /// **'4 Stunden lang wurde nichts abgehakt. Er endet beim letzten Abhaken um {time}.'**
  String shopAutoEndedBody(String time);

  /// No description provided for @shopKeepGoing.
  ///
  /// In de, this message translates to:
  /// **'Doch weiter'**
  String get shopKeepGoing;

  /// No description provided for @shopShowSummary.
  ///
  /// In de, this message translates to:
  /// **'Übersicht ansehen'**
  String get shopShowSummary;

  /// Job 234: the trip summary page's title
  ///
  /// In de, this message translates to:
  /// **'Geplant und gekauft'**
  String get shopSummaryTitle;

  /// Job 234: summary head, the trip's day and times
  ///
  /// In de, this message translates to:
  /// **'{day}, {from} bis {to}'**
  String shopSummaryWhen(String day, String from, String to);

  /// No description provided for @shopMinutes.
  ///
  /// In de, this message translates to:
  /// **'{minutes} Min.'**
  String shopMinutes(int minutes);

  /// Job 234: a trip shorter than half a minute, before shopShoppedFor's „eingekauft“
  ///
  /// In de, this message translates to:
  /// **'Unter 1 Min.'**
  String get shopUnderAMinute;

  /// No description provided for @shopHoursMinutes.
  ///
  /// In de, this message translates to:
  /// **'{hours} Std. {minutes} Min.'**
  String shopHoursMinutes(int hours, int minutes);

  /// Job 234: summary title; duration is shopMinutes or shopHoursMinutes
  ///
  /// In de, this message translates to:
  /// **'{duration} eingekauft'**
  String shopShoppedFor(String duration);

  /// No description provided for @shopLede.
  ///
  /// In de, this message translates to:
  /// **'{bought} von {planned} von der Liste gekauft'**
  String shopLede(int bought, int planned);

  /// No description provided for @shopLedeExtra.
  ///
  /// In de, this message translates to:
  /// **'{count} zusätzlich'**
  String shopLedeExtra(int count);

  /// No description provided for @shopLedeNoList.
  ///
  /// In de, this message translates to:
  /// **'Ohne Liste losgegangen · {count} gekauft'**
  String shopLedeNoList(int count);

  /// No description provided for @shopAutoEndHint.
  ///
  /// In de, this message translates to:
  /// **'Beendet beim letzten Abhaken um {time}, automatisch.'**
  String shopAutoEndHint(String time);

  /// No description provided for @shopPlannedSection.
  ///
  /// In de, this message translates to:
  /// **'Beim Start auf der Liste'**
  String get shopPlannedSection;

  /// No description provided for @shopExtraSection.
  ///
  /// In de, this message translates to:
  /// **'Seit dem Start dazugekommen'**
  String get shopExtraSection;

  /// No description provided for @shopPlannedEmpty.
  ///
  /// In de, this message translates to:
  /// **'Die Liste war leer.'**
  String get shopPlannedEmpty;

  /// No description provided for @shopExtraEmpty.
  ///
  /// In de, this message translates to:
  /// **'Nichts. Alles stand auf der Liste.'**
  String get shopExtraEmpty;

  /// No description provided for @shopNotBought.
  ///
  /// In de, this message translates to:
  /// **'nicht gekauft'**
  String get shopNotBought;

  /// Job 234: a summary row's state for screen readers
  ///
  /// In de, this message translates to:
  /// **'gekauft'**
  String get shopBought;

  /// Job 234: an extra another member wrote onto the list
  ///
  /// In de, this message translates to:
  /// **'von {name}'**
  String shopBy(String name);

  /// No description provided for @shopMarkPlanned.
  ///
  /// In de, this message translates to:
  /// **'War geplant'**
  String get shopMarkPlanned;

  /// No description provided for @shopMarkPlannedHint.
  ///
  /// In de, this message translates to:
  /// **'„War geplant“ zählt einen Artikel zur Liste, wenn er abgesprochen war, aber nicht draufstand.'**
  String get shopMarkPlannedHint;

  /// No description provided for @shopPlannedPrice.
  ///
  /// In de, this message translates to:
  /// **'geplant {amount}'**
  String shopPlannedPrice(String amount);

  /// No description provided for @shopMore.
  ///
  /// In de, this message translates to:
  /// **'{amount} mehr'**
  String shopMore(String amount);

  /// No description provided for @shopLess.
  ///
  /// In de, this message translates to:
  /// **'{amount} weniger'**
  String shopLess(String amount);

  /// No description provided for @shopAsPlanned.
  ///
  /// In de, this message translates to:
  /// **'wie geplant'**
  String get shopAsPlanned;

  /// No description provided for @shopPaid.
  ///
  /// In de, this message translates to:
  /// **'Bezahlt'**
  String get shopPaid;

  /// No description provided for @shopPaidTotal.
  ///
  /// In de, this message translates to:
  /// **'Insgesamt bezahlt'**
  String get shopPaidTotal;

  /// Job 234: under a paid total; difference is shopMore, shopLess or shopAsPlanned
  ///
  /// In de, this message translates to:
  /// **'Geplant {amount} · {difference}'**
  String shopCompared(String amount, String difference);

  /// No description provided for @shopComparedCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{bei 1 Artikel} other{bei {count} Artikeln}}'**
  String shopComparedCount(int count);

  /// No description provided for @shopWithoutPrice.
  ///
  /// In de, this message translates to:
  /// **'{count} ohne Preis'**
  String shopWithoutPrice(int count);

  /// No description provided for @shopWithoutPlan.
  ///
  /// In de, this message translates to:
  /// **'{count} ohne geplanten Preis'**
  String shopWithoutPlan(int count);

  /// No description provided for @shopTotalsNote.
  ///
  /// In de, this message translates to:
  /// **'Bezahlt zählt nur Artikel mit Preis. Der Unterschied vergleicht nur Artikel mit geplantem und bezahltem Preis.'**
  String get shopTotalsNote;

  /// No description provided for @shopKeepShopping.
  ///
  /// In de, this message translates to:
  /// **'Weiter einkaufen'**
  String get shopKeepShopping;

  /// No description provided for @shopNotSaved.
  ///
  /// In de, this message translates to:
  /// **'Der Einkauf ist noch nicht gespeichert.'**
  String get shopNotSaved;

  /// Job 234: Free summary, how many items were ticked off
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Artikel abgehakt} other{{count} Artikel abgehakt}}'**
  String shopTicked(int count);

  /// No description provided for @shopLockedTitle.
  ///
  /// In de, this message translates to:
  /// **'Was war geplant, was kam dazu?'**
  String get shopLockedTitle;

  /// No description provided for @shopLockedBody.
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium zeigt nach jedem Einkauf, was auf der Liste stand und was unterwegs dazukam, auch von anderen im Haushalt.'**
  String get shopLockedBody;

  /// No description provided for @shopLockedButton.
  ///
  /// In de, this message translates to:
  /// **'Snacklist Premium ansehen'**
  String get shopLockedButton;

  /// No description provided for @shopLoadFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Übersicht konnte nicht geladen werden.'**
  String get shopLoadFailed;

  /// Job 234: Mehr's row, shown while no trip runs
  ///
  /// In de, this message translates to:
  /// **'Einkauf starten'**
  String get shopStartByHand;

  /// No description provided for @shopStartByHandHint.
  ///
  /// In de, this message translates to:
  /// **'Die Uhr läuft ab jetzt, die Liste, wie sie jetzt ist, gilt als geplant.'**
  String get shopStartByHandHint;

  /// Job 234: an extra from a member who left the household
  ///
  /// In de, this message translates to:
  /// **'von jemand anderem'**
  String get shopByOther;

  /// Job 234: snackbar when marking a summary row failed
  ///
  /// In de, this message translates to:
  /// **'„War geplant“ konnte nicht gespeichert werden. Versuch es noch mal.'**
  String get shopMarkFailed;

  /// Job 237 (flag list-declutter, ST3): the list's summary block above „Zuletzt verwendet“, its last line
  ///
  /// In de, this message translates to:
  /// **'Gesamt'**
  String get subtotalsTotal;

  /// Job 237 (flag list-declutter, ST3): the list's summary block above „Zuletzt verwendet“: a line's items without a price
  ///
  /// In de, this message translates to:
  /// **'{count} ohne Preis'**
  String subtotalsUnpriced(int count);

  /// Job 242 (flag list-declutter, Peter's ST-Q6 answer): the summary block's Gesamt without a trip, how many items have a price; next to subtotalsUnpriced
  ///
  /// In de, this message translates to:
  /// **'{count} mit Preis'**
  String subtotalsPriced(int count);

  /// Job 237 (flag list-declutter, ST3): the list's summary block above „Zuletzt verwendet“: a store whose items were all bought on the running trip
  ///
  /// In de, this message translates to:
  /// **'alles gekauft'**
  String get subtotalsAllBought;

  /// Job 237 (flag list-declutter, ST3): the list's summary block above „Zuletzt verwendet“, while a trip runs: what was bought on it
  ///
  /// In de, this message translates to:
  /// **'{amount} gekauft'**
  String subtotalsBought(String amount);

  /// Job 237 (flag list-declutter, ST3): the list's summary block above „Zuletzt verwendet“, while a trip runs: what is still open
  ///
  /// In de, this message translates to:
  /// **'{amount} offen'**
  String subtotalsOpen(String amount);

  /// Job 237 (flag list-declutter, ST3): the list's summary block above „Zuletzt verwendet“: screen reader hint of a store line, which scrolls to its section
  ///
  /// In de, this message translates to:
  /// **'Zum Laden in der Liste'**
  String get subtotalsJump;

  /// Job 237: a sum with items without a price, e.g. „mind. 32,08 €“
  ///
  /// In de, this message translates to:
  /// **'mind. {amount}'**
  String moneyAtLeast(String amount);

  /// Job 237: moneyAtLeast for screen readers
  ///
  /// In de, this message translates to:
  /// **'mindestens {amount}'**
  String moneyAtLeastSpoken(String amount);

  /// Job 237: a price per kg or l on the planned weight, or a sum holding one, e.g. „≈ 1,51 €“
  ///
  /// In de, this message translates to:
  /// **'≈ {amount}'**
  String moneyEstimate(String amount);

  /// Job 237: moneyEstimate for screen readers
  ///
  /// In de, this message translates to:
  /// **'etwa {amount}'**
  String moneyEstimateSpoken(String amount);

  /// Job 248: the switcher sheet's row for Siri, Alexa and AI, first line; the default household and its list follow on their own lines; a tap opens the household step
  ///
  /// In de, this message translates to:
  /// **'Siri, Alexa & KI nutzen:'**
  String get voiceDefaultLabel;

  /// Job 248 review: what screen readers hear for the household line of the switcher sheet's row for Siri, Alexa and AI (the list line reads defaultListRow)
  ///
  /// In de, this message translates to:
  /// **'Haushalt: {household}'**
  String voiceDefaultHouseholdName(String household);

  /// Job 248: back row of the switcher sheet's list step for Siri, Alexa and AI: back to its household step
  ///
  /// In de, this message translates to:
  /// **'Siri, Alexa & KI'**
  String get voiceDefaultBack;

  /// Job 248: under the title of the switcher sheet's list step for Siri, Alexa and AI
  ///
  /// In de, this message translates to:
  /// **'Was du sagst, ohne eine Liste zu nennen, landet in „{household}“ auf dieser Liste.'**
  String voiceDefaultListBody(String household);

  /// Job 271 JH2: the start screen's second button, to the sign-in
  ///
  /// In de, this message translates to:
  /// **'Ich habe schon ein Konto'**
  String get jh2StartHaveAccount;

  /// Job 271 JH2: the household-name step's second button, to the code step
  ///
  /// In de, this message translates to:
  /// **'Bestehendem Haushalt beitreten'**
  String get jh2JoinExisting;

  /// Job 271 JH2: heading of the guided start's code step
  ///
  /// In de, this message translates to:
  /// **'Gib deinen Einladungscode ein'**
  String get jh2JoinCodeHeading;

  /// Job 271 JH2: the line under the code step's heading
  ///
  /// In de, this message translates to:
  /// **'Die 8 Zeichen aus der Einladung. Sobald alle drin sind, siehst du den Haushalt.'**
  String get jh2JoinCodeHelp;

  /// Job 271 JH2: the code step's button, on once the household shows
  ///
  /// In de, this message translates to:
  /// **'Beitreten'**
  String get jh2JoinCodeJoin;

  /// Job 271 JH2: the code step's preview title, as the join page's
  ///
  /// In de, this message translates to:
  /// **'{inviter} lädt dich zu „{household}“ ein'**
  String jh2InvitedBy(String inviter, String household);

  /// Job 271 JH2: the preview title without the inviter's name
  ///
  /// In de, this message translates to:
  /// **'Du bist zu „{household}“ eingeladen'**
  String jh2InvitedTo(String household);

  /// Job 271 JH2: the preview title without the household's name
  ///
  /// In de, this message translates to:
  /// **'{inviter} lädt dich in einen Haushalt ein'**
  String jh2InvitedByInviter(String inviter);

  /// Job 271 JH2: the invite sign-in sheet's heading, and the preview title without either name
  ///
  /// In de, this message translates to:
  /// **'Du bist in einen Haushalt eingeladen'**
  String get jh2InvitedToHousehold;

  /// Job 271 JH2: the preview's member count, as the join page's
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Mitglied} other{{count} Mitglieder}}'**
  String jh2PreviewMembers(int count);

  /// Job 271 JH2: the preview's open-item count, as the join page's
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 offener Eintrag} other{{count} offene Einträge}}'**
  String jh2PreviewOpenItems(int count);

  /// Job 271 JH2: the code step for any code that leads nowhere (made up, expired, revoked, used, full): one answer for all
  ///
  /// In de, this message translates to:
  /// **'Diese Einladung gilt nicht mehr. Bitte um eine neue Einladung.'**
  String get jh2CodeUnavailable;

  /// Job 271 JH2: the code step when the lookup is rate-limited
  ///
  /// In de, this message translates to:
  /// **'Gerade zu viele Versuche. Versuch es später noch einmal.'**
  String get jh2CodeRateLimited;

  /// Job 271 JH2: the invite sign-in sheet's line
  ///
  /// In de, this message translates to:
  /// **'Hast du schon ein Snacklist-Konto?'**
  String get jh2InviteSheetBody;

  /// Job 271 JH2: the invite sign-in sheet's first button: the email form with sign-up first
  ///
  /// In de, this message translates to:
  /// **'Konto erstellen'**
  String get jh2InviteSheetCreate;

  /// Job 271 JH2: the joiner's wait for an admin's approval
  ///
  /// In de, this message translates to:
  /// **'Deine Anfrage liegt bei „{name}“. Ein Admin sieht dort deinen Namen und lässt dich rein. Deine Liste öffnet sich von selbst, sobald das passiert.'**
  String jh2JoinRequestWaiting(String name);

  /// Job 271 JH2: the wait's text button without a household: the guided start instead of waiting
  ///
  /// In de, this message translates to:
  /// **'Lieber eigene Liste anlegen'**
  String get jh2JoinRequestOwnList;

  /// Job 271 (JH-Q7): screen-reader label of a one-person invite's QR code, its link
  ///
  /// In de, this message translates to:
  /// **'QR-Code dieser Einladung'**
  String get inviteQrPerson;

  /// Job 271: the only text of the web app's card in a phone's browser that opens the installed app (Peter's copy, addendum 1)
  ///
  /// In de, this message translates to:
  /// **'Snacklist funktioniert in der App besser.'**
  String get openAppText;

  /// Job 271: the open-the-app card's button; opens the installed app (never „App holen“)
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get openAppAction;

  /// Job 276: the heading of the list's section with the items added while the add sheet is open
  ///
  /// In de, this message translates to:
  /// **'Gerade hinzugefügt'**
  String get justAdded;

  /// Job 276: the screen-reader name of the thin line above the add field while suggestions load
  ///
  /// In de, this message translates to:
  /// **'Vorschläge laden'**
  String get suggestionsLoading;

  /// Job 276: read after a dimmed suggestion row that still answers an older text
  ///
  /// In de, this message translates to:
  /// **'älterer Vorschlag, lädt noch'**
  String get suggestionStale;

  /// Job 297: the name step's heading after the sign-in
  ///
  /// In de, this message translates to:
  /// **'Wie sollen wir dich nennen?'**
  String get yourNameTitle;

  /// Job 297: the name step's text under its heading
  ///
  /// In de, this message translates to:
  /// **'Alle in deinem Haushalt sehen diesen Namen. Wen du einlädst, sieht deinen Vornamen. Du kannst ihn später ändern.'**
  String get yourNameBody;

  /// Job 297: the name field's label, the name step's title bar, Konto's row and the edit sheet's title
  ///
  /// In de, this message translates to:
  /// **'Dein Name'**
  String get yourNameLabel;

  /// Job 297: the empty name field's hint
  ///
  /// In de, this message translates to:
  /// **'z. B. Lea'**
  String get yourNameHint;

  /// Job 297: under the name field when the name is empty or too long
  ///
  /// In de, this message translates to:
  /// **'Gib einen Namen mit 1 bis 80 Zeichen ein.'**
  String get yourNameInvalid;

  /// Job 297: the name step's button while the field holds the Google or Apple name unchanged
  ///
  /// In de, this message translates to:
  /// **'Ja, das bin ich'**
  String get yourNameConfirm;

  /// Job 297: the name step's button to skip it, only for members of a household
  ///
  /// In de, this message translates to:
  /// **'Jetzt nicht'**
  String get yourNameNotNow;

  /// Job 297: the name step when reading the name failed; a retry button follows
  ///
  /// In de, this message translates to:
  /// **'Dein Name konnte nicht geladen werden.'**
  String get yourNameLoadFailed;

  /// Job 297: saving the name failed for lack of a connection
  ///
  /// In de, this message translates to:
  /// **'Keine Internetverbindung. Dein Name wurde nicht gespeichert.'**
  String get yourNameOffline;

  /// Job 297: Konto's name row while the name is still the e-mail address' first part
  ///
  /// In de, this message translates to:
  /// **'Namen eintragen'**
  String get yourNameAdd;

  /// Job 297: the text of the sheet that changes the name
  ///
  /// In de, this message translates to:
  /// **'Alle in deinem Haushalt sehen diesen Namen. Wen du einlädst, sieht deinen Vornamen.'**
  String get yourNameEditBody;

  /// Job 297: the notice after the sheet saved the name
  ///
  /// In de, this message translates to:
  /// **'Name gespeichert'**
  String get yourNameSaved;

  /// More (flag report-content-entry, job 281): subtitle of the feedback row (Feedback & ideas or Send feedback); Legal N-226's second label route
  ///
  /// In de, this message translates to:
  /// **'Auch: Inhalte melden'**
  String get reportEntryAlso;

  /// Job 281: the button in Feedback & ideas (and at the top of the feedback form without FB4) that opens the report form; also the form's title
  ///
  /// In de, this message translates to:
  /// **'Inhalt melden'**
  String get reportContent;

  /// Job 281: under the Report content button
  ///
  /// In de, this message translates to:
  /// **'Nur wir lesen die Meldung, niemand in deinem Haushalt.'**
  String get reportEntryHint;

  /// Report form (Legal B.4, verbatim): the intro at the top
  ///
  /// In de, this message translates to:
  /// **'Hier meldest du Inhalte in Snacklist, die du für rechtswidrig hältst, zum Beispiel einen Eintrag, eine Liste, einen Haushaltsnamen oder ein Foto. Für Fragen oder Fehler nutze bitte Feedback oder support@snacklist.app. Dieses Formular ist kein Notruf: Ist jemand in akuter Gefahr, ruf sofort den örtlichen Notruf an, in der EU die 112.'**
  String get reportIntro;

  /// Report form (Legal B.4): tag after a required question, shown in brackets
  ///
  /// In de, this message translates to:
  /// **'Pflicht'**
  String get reportRequired;

  /// Report form (Legal B.4): tag after the name and e-mail labels, shown in brackets
  ///
  /// In de, this message translates to:
  /// **'empfohlen'**
  String get reportRecommended;

  /// Report form (Legal B.4): question 1, the kind of report
  ///
  /// In de, this message translates to:
  /// **'Worum geht es?'**
  String get reportAbout;

  /// Report form (Legal B.4): kind of report, sent as hate
  ///
  /// In de, this message translates to:
  /// **'Beleidigung, Bedrohung oder Hetze'**
  String get reportCategoryHate;

  /// Report form (Legal B.4): kind of report, sent as personal_rights
  ///
  /// In de, this message translates to:
  /// **'Verletzung meiner Persönlichkeitsrechte oder Privatsphäre (z. B. Foto von mir)'**
  String get reportCategoryPersonalRights;

  /// Report form (Legal B.4): kind of report, sent as ip
  ///
  /// In de, this message translates to:
  /// **'Urheber- oder Markenrecht'**
  String get reportCategoryIp;

  /// Report form (Legal B.4): kind of report, sent as csam; hides name and e-mail
  ///
  /// In de, this message translates to:
  /// **'Darstellung sexuellen Kindesmissbrauchs'**
  String get reportCategoryCsam;

  /// Report form (Legal B.4): kind of report, sent as danger
  ///
  /// In de, this message translates to:
  /// **'Gefahr für Leben oder Sicherheit'**
  String get reportCategoryDanger;

  /// Report form (Legal B.4): kind of report, sent as other
  ///
  /// In de, this message translates to:
  /// **'Anderer Rechtsverstoß'**
  String get reportCategoryOther;

  /// Report form (Legal B.4): question 2; also the title of the picker sheet
  ///
  /// In de, this message translates to:
  /// **'Wo ist der Inhalt?'**
  String get reportWhere;

  /// Report form (Legal B.4, the app's sentence, N-260 cut 2): help under question 2 once something is picked
  ///
  /// In de, this message translates to:
  /// **'In der App wählen wir den Eintrag, die Liste oder das Foto für dich aus – bitte prüfe die Auswahl.'**
  String get reportWhereHelp;

  /// Report form (job 278 prototype): help under question 2 before anything is picked
  ///
  /// In de, this message translates to:
  /// **'Wähle den Eintrag, die Liste oder den Haushaltsnamen. Je genauer, desto schneller finden wir ihn.'**
  String get reportWhereChooseHelp;

  /// Report form (Legal N-260, verbatim): help with the text field after Somewhere else was picked
  ///
  /// In de, this message translates to:
  /// **'Beschreibe, wo er ist: Name des Haushalts und der Liste und der genaue Text des Eintrags. Je genauer, desto schneller finden wir ihn.'**
  String get reportWhereElsewhereHelp;

  /// Report form (job 278 prototype): opens the picker for question 2
  ///
  /// In de, this message translates to:
  /// **'Auswählen'**
  String get reportWhereChoose;

  /// Report form (job 278 prototype): opens the picker again once something is picked
  ///
  /// In de, this message translates to:
  /// **'Ändern'**
  String get reportWhereChange;

  /// Report form (Legal B.4): question 3
  ///
  /// In de, this message translates to:
  /// **'Warum ist der Inhalt rechtswidrig?'**
  String get reportWhy;

  /// Report form (Legal B.4): help under question 3
  ///
  /// In de, this message translates to:
  /// **'Erkläre bitte so genau wie möglich, welches Recht verletzt wird und warum. Wenn es um deine eigenen Rechte geht, sag uns, in welcher Beziehung du zum Inhalt stehst.'**
  String get reportWhyHelp;

  /// Report form: characters of the reason used, of at most 5,000
  ///
  /// In de, this message translates to:
  /// **'{count} / {max}'**
  String reportCounter(int count, int max);

  /// Report form (Legal B.4): label of the name field
  ///
  /// In de, this message translates to:
  /// **'Dein Name'**
  String get reportName;

  /// Report form (Legal B.4): label of the e-mail field
  ///
  /// In de, this message translates to:
  /// **'Deine E-Mail-Adresse'**
  String get reportEmail;

  /// Report form (Legal B.4): help under name and e-mail
  ///
  /// In de, this message translates to:
  /// **'Wir brauchen Namen und E-Mail-Adresse, um dir den Eingang zu bestätigen und dir unsere Entscheidung mitzuteilen. Ohne sie prüfen wir die Meldung trotzdem, können dir aber nicht antworten.'**
  String get reportContactHelp;

  /// Report form (Legal B.4): shown for child sexual abuse material instead of name and e-mail, and as their help once added
  ///
  /// In de, this message translates to:
  /// **'Bei Darstellungen sexuellen Kindesmissbrauchs kannst du ohne Namen und E-Mail-Adresse melden.'**
  String get reportCsamNote;

  /// Report form (job 278 prototype): shows the hidden name and e-mail fields for child sexual abuse material
  ///
  /// In de, this message translates to:
  /// **'Namen und E-Mail-Adresse angeben'**
  String get reportCsamAdd;

  /// Report form (Legal B.4): the required check box
  ///
  /// In de, this message translates to:
  /// **'Ich bin in gutem Glauben davon überzeugt, dass meine Angaben und Vorwürfe in dieser Meldung richtig und vollständig sind.'**
  String get reportGoodFaith;

  /// Report form (Legal B.4 without 'in the app', N-260 cut 1): opens the annotator on the screen before More (flag feedback-fb2)
  ///
  /// In de, this message translates to:
  /// **'Screenshot anhängen (optional)'**
  String get reportScreenshot;

  /// Report form (Legal B.4): help under the screenshot button; also the annotator's hint when it opens for a report
  ///
  /// In de, this message translates to:
  /// **'Verdecke darauf, was nichts mit der Meldung zu tun hat.'**
  String get reportScreenshotHelp;

  /// Report form (job 278 prototype): next to the attached screenshot's preview
  ///
  /// In de, this message translates to:
  /// **'Screenshot angehängt'**
  String get reportScreenshotAttached;

  /// Report form (job 278 prototype): removes the attached screenshot
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get reportScreenshotRemove;

  /// Report form (Legal B.4): footer before the link to the privacy policy
  ///
  /// In de, this message translates to:
  /// **'Wie wir mit deinen Angaben umgehen:'**
  String get reportPrivacyLead;

  /// Report form (Legal B.4): footer link to the privacy policy's section on reports
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung, Abschnitt 10'**
  String get reportPrivacyLink;

  /// Report form (Legal B.4): the send button
  ///
  /// In de, this message translates to:
  /// **'Meldung senden'**
  String get reportSend;

  /// Report form (job 278 prototype): error under question 1 after Send
  ///
  /// In de, this message translates to:
  /// **'Wähle, worum es geht.'**
  String get reportErrorAbout;

  /// Report form (job 278 prototype): error under question 2 after Send
  ///
  /// In de, this message translates to:
  /// **'Wähle, wo der Inhalt ist.'**
  String get reportErrorWhere;

  /// Report form (job 278 prototype): error under question 3 after Send, with the characters still missing
  ///
  /// In de, this message translates to:
  /// **'Mindestens 20 Zeichen (noch {count}).'**
  String reportErrorShort(int count);

  /// Report form (job 278 prototype): error under question 3 after Send
  ///
  /// In de, this message translates to:
  /// **'Höchstens 5.000 Zeichen.'**
  String get reportErrorLong;

  /// Report form (job 281): error under the e-mail field after Send when it is no address
  ///
  /// In de, this message translates to:
  /// **'Prüfe die E-Mail-Adresse.'**
  String get reportErrorEmail;

  /// Report form (job 278 prototype): error under the good-faith check box after Send
  ///
  /// In de, this message translates to:
  /// **'Bitte bestätige das, um die Meldung zu senden.'**
  String get reportErrorGoodFaith;

  /// Report form (Legal N-242, without the link): the server refused it, too many reports this hour
  ///
  /// In de, this message translates to:
  /// **'Deine Meldung wurde nicht gesendet, weil gerade zu viele Meldungen ankommen. Deine Angaben sind noch da. Bitte versuch es in einer Stunde noch einmal oder schick sie per E-Mail an unsere Kontaktstelle support@snacklist.app: worum es geht, wo der Inhalt ist und warum er rechtswidrig ist. Auch so bearbeiten wir deine Meldung.'**
  String get reportFailedRateLimited;

  /// Report form (the web form's text, without the link): the server answered with an error
  ///
  /// In de, this message translates to:
  /// **'Die Meldung konnte gerade nicht gesendet werden. Bitte versuch es gleich noch einmal oder schreib an support@snacklist.app.'**
  String get reportFailedUnavailable;

  /// Report form (the web form's text): no answer from the server
  ///
  /// In de, this message translates to:
  /// **'Keine Verbindung. Deine Angaben sind noch da: Bitte versuch es gleich noch einmal.'**
  String get reportFailedOffline;

  /// Report form: the screenshot is over the 2 MiB the server takes, refused before sending or by the server (413)
  ///
  /// In de, this message translates to:
  /// **'Der Screenshot ist zu groß. Entferne ihn und sende die Meldung noch einmal.'**
  String get reportFailedScreenshotTooLarge;

  /// Report picker (job 278 prototype): the search field's hint
  ///
  /// In de, this message translates to:
  /// **'Einträge und Listen suchen'**
  String get reportPickerSearch;

  /// Report picker (job 278 prototype): section of the household's items
  ///
  /// In de, this message translates to:
  /// **'Einträge'**
  String get reportPickerItems;

  /// Report picker (job 278 prototype): section of the household's lists
  ///
  /// In de, this message translates to:
  /// **'Listen'**
  String get reportPickerLists;

  /// Report picker (job 278 prototype): section with the household's name
  ///
  /// In de, this message translates to:
  /// **'Name des Haushalts'**
  String get reportPickerHousehold;

  /// Report picker (job 278 prototype): the last row, for a place the picker does not list
  ///
  /// In de, this message translates to:
  /// **'Woanders'**
  String get reportPickerElsewhere;

  /// Report form (job 278 prototype): kind of the picked place, above its name
  ///
  /// In de, this message translates to:
  /// **'Eintrag'**
  String get reportKindItem;

  /// Report form (job 278 prototype): kind of the picked place, above its name
  ///
  /// In de, this message translates to:
  /// **'Liste'**
  String get reportKindList;

  /// Report form (job 278 prototype): kind of the picked place, above its name
  ///
  /// In de, this message translates to:
  /// **'Haushalt'**
  String get reportKindHousehold;

  /// Report form: the picked item's, list's or household's name in quotes
  ///
  /// In de, this message translates to:
  /// **'„{name}“'**
  String reportQuoted(String name);

  /// Report form (job 278 prototype): under a picked item, its list and household
  ///
  /// In de, this message translates to:
  /// **'Liste „{list}“ · {household}'**
  String reportItemContext(String list, String household);

  /// Report confirmation (job 278 prototype): heading
  ///
  /// In de, this message translates to:
  /// **'Meldung gesendet'**
  String get reportSentTitle;

  /// Report confirmation (job 278 prototype): above the report's number
  ///
  /// In de, this message translates to:
  /// **'Nummer'**
  String get reportNumber;

  /// Report confirmation (job 278 prototype): copies the number
  ///
  /// In de, this message translates to:
  /// **'Nummer kopieren'**
  String get reportCopyNumber;

  /// Report confirmation (job 278 prototype): the copy button once the number was copied
  ///
  /// In de, this message translates to:
  /// **'Kopiert'**
  String get reportCopied;

  /// Report confirmation (Legal B.4, verbatim)
  ///
  /// In de, this message translates to:
  /// **'Danke, deine Meldung ist eingegangen. Nummer: {ref}. Wir prüfen sie selbst – ohne automatische Entscheidung – und melden uns, wenn du eine E-Mail-Adresse angegeben hast.'**
  String reportThanks(String ref);

  /// Report confirmation (job 278 prototype): when an e-mail address was sent
  ///
  /// In de, this message translates to:
  /// **'Eine Bestätigung ist an {email} unterwegs.'**
  String reportMailed(String email);

  /// Report confirmation (job 278 prototype): when no e-mail address was sent
  ///
  /// In de, this message translates to:
  /// **'Du hast keine E-Mail-Adresse angegeben, darum können wir dir nicht antworten. Heb die Nummer auf, wenn du nachfragen willst.'**
  String get reportNotMailed;

  /// Report confirmation (job 278 prototype)
  ///
  /// In de, this message translates to:
  /// **'Meldungen stehen nicht unter Deine Notizen, und niemand in deinem Haushalt sieht sie.'**
  String get reportNotInNotes;

  /// Report confirmation (job 278 prototype): back to where the report was started
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get reportDone;

  /// Job 313 DL1: the action that opens a store's app, e.g. „Lidl Plus öffnen“: the list header key's screen-reader name and the store screen's button name. {app} is the retailer app's name from the registry
  ///
  /// In de, this message translates to:
  /// **'{app} öffnen'**
  String storeAppOpen(String app);

  /// Job 313: a chain's country by its ISO 3166-1 code, e.g. after a chain name: „REWE · Deutschland“
  ///
  /// In de, this message translates to:
  /// **'{code, select, DE{Deutschland} AT{Österreich} CH{Schweiz} FR{Frankreich} NL{Niederlande} PL{Polen} IT{Italien} ES{Spanien} BE{Belgien} CZ{Tschechien} DK{Dänemark} FI{Finnland} HR{Kroatien} HU{Ungarn} IE{Irland} LU{Luxemburg} NO{Norwegen} PT{Portugal} RO{Rumänien} SE{Schweden} SI{Slowenien} SK{Slowakei} other{{code}}}'**
  String countryName(String code);

  /// Job 313 SS2: asked once after saving a new store whose name is a chain's, e.g. „Ist das REWE (Deutschland)?“. {chain} is the chain's name, {country} the country's name
  ///
  /// In de, this message translates to:
  /// **'Ist das {chain} ({country})?'**
  String chainQuestionOne(String chain, String country);

  /// Job 313 SS5: asked once about an existing store whose name is a chain's. {store} is the household's store name
  ///
  /// In de, this message translates to:
  /// **'Ist dein „{store}“ die Kette {chain} ({country})?'**
  String chainQuestionOneExisting(String store, String chain, String country);

  /// Job 313: the line under the chain question when the chain has an app. {app} is the app's name, e.g. „Lidl Plus“
  ///
  /// In de, this message translates to:
  /// **'Dann kannst du {app} direkt aus der Liste öffnen.'**
  String chainQuestionApp(String app);

  /// Job 313: the chain question's yes: link the store to the chain
  ///
  /// In de, this message translates to:
  /// **'Ja'**
  String get chainQuestionYes;

  /// Job 313 SS2: the chain question's no after creating a store: keep it as typed, not linked, never asked again
  ///
  /// In de, this message translates to:
  /// **'Nein, so lassen'**
  String get chainQuestionKeep;

  /// Job 313 SS5: the chain question's no for an existing store: not linked, never asked again
  ///
  /// In de, this message translates to:
  /// **'Nein'**
  String get chainQuestionNo;

  /// Job 313 SS2: asked after saving a new store whose name fits several chains, e.g. „Welches Aldi?“, one button per chain below
  ///
  /// In de, this message translates to:
  /// **'Welches {store}?'**
  String chainQuestionWhich(String store);

  /// Job 313 SS5: asked about an existing store whose name fits several chains, one button per chain below
  ///
  /// In de, this message translates to:
  /// **'Welche Kette ist dein „{store}“?'**
  String chainQuestionWhichExisting(String store);

  /// Job 313: the answer to „Welches Aldi?“ when the store is none of the chains: not linked, never asked again
  ///
  /// In de, this message translates to:
  /// **'Keins davon'**
  String get chainQuestionNone;

  /// Job 313: a chain with its country, where chains of several countries are listed, e.g. „Hofer (Österreich)“
  ///
  /// In de, this message translates to:
  /// **'{chain} ({country})'**
  String chainWithCountry(String chain, String country);

  /// Job 313 DL1: one-time tip line under the first store header that has an open-store-app key, next to the key's icon; gone after its X or the first tap on a key
  ///
  /// In de, this message translates to:
  /// **'Öffnet die App des Ladens.'**
  String get storeAppTip;

  /// Job 313 SS5: the progress on the list's card that asks existing stores for their chain, e.g. „1 / 3“
  ///
  /// In de, this message translates to:
  /// **'{index} / {total}'**
  String chainCardProgress(int index, int total);

  /// Job 313 SS5: the screen-reader name of the chain card's progress „1 / 3“
  ///
  /// In de, this message translates to:
  /// **'Laden {index} von {total}'**
  String chainCardProgressLabel(int index, int total);

  /// Job 313 SS2: screen-reader name of a chain suggested under a new store's name while typing; a tap creates the store linked to the chain
  ///
  /// In de, this message translates to:
  /// **'{chain} ({country}) wählen'**
  String chainSuggestionPick(String chain, String country);

  /// Job 313 OS3: the label of the store screen's card with the chain's app
  ///
  /// In de, this message translates to:
  /// **'App'**
  String get storeAppCardTitle;

  /// Job 313 OS3: the store screen's button that opens the chain's app (screen readers hear storeAppOpen)
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get storeAppCardOpen;

  /// Job 313 SS-Q8: above the choice of app when the chain has several; the choice is kept per store
  ///
  /// In de, this message translates to:
  /// **'Welche App soll sich öffnen?'**
  String get storeAppCardChoose;

  /// Job 313 SS1: the store screen's line naming the chain the store is linked to, e.g. „Zugeordnet: Lidl · Deutschland“ (Legal N-293: never „verbunden“)
  ///
  /// In de, this message translates to:
  /// **'Zugeordnet: {chain} · {country}'**
  String storeChainLinked(String chain, String country);

  /// Job 313 SS1: button beside the linked chain: pick another chain
  ///
  /// In de, this message translates to:
  /// **'Ändern'**
  String get storeChainChange;

  /// Job 313: screen-reader name of storeChainChange
  ///
  /// In de, this message translates to:
  /// **'Kette ändern'**
  String get storeChainChangeLabel;

  /// Job 313 SS1: button beside the linked chain: the store is no chain's any more (and is not asked again)
  ///
  /// In de, this message translates to:
  /// **'Zuordnung aufheben'**
  String get storeChainUnlink;

  /// Job 313: screen-reader name of storeChainUnlink
  ///
  /// In de, this message translates to:
  /// **'Zuordnung zur Kette aufheben'**
  String get storeChainUnlinkLabel;

  /// Job 313 SS1: the store screen's button for a store without a chain; opens the chain picker
  ///
  /// In de, this message translates to:
  /// **'Kette zuordnen'**
  String get storeChainConnect;

  /// Job 313 SS1: title of the chain picker
  ///
  /// In de, this message translates to:
  /// **'Kette wählen'**
  String get storeChainPickerTitle;

  /// Job 313 SS1: the chain picker's search field hint; finds chains of every country
  ///
  /// In de, this message translates to:
  /// **'Kette suchen'**
  String get storeChainPickerSearch;

  /// Job 313 SS1: the chain picker when the search finds nothing
  ///
  /// In de, this message translates to:
  /// **'Keine Kette gefunden.'**
  String get storeChainPickerEmpty;

  /// Job 313, Legal N-293 (word for word): the list card that asks about stores made before, under its question
  ///
  /// In de, this message translates to:
  /// **'Erkannte Läden können einen Knopf für ihre App zeigen. Die Namen bleiben, wie du sie geschrieben hast.'**
  String get migrateBody;

  /// Job 313, Legal N-293 (word for word, not „Verbunden“): said to screen readers after a store was matched to its chain from the list card
  ///
  /// In de, this message translates to:
  /// **'Zugeordnet'**
  String get migrateDone;

  /// Job 324 (AM2, flag add-match-rows): the action a screen reader names on the add sheet's match row that ticks the open item off, before the item
  ///
  /// In de, this message translates to:
  /// **'Abhaken'**
  String get addMatchTickOff;

  /// Job 324 (AM2): the add sheet's note after a ticked item was put back from its match row or with Enter; item is its Menge and name (10× Eier)
  ///
  /// In de, this message translates to:
  /// **'Wieder auf der Liste: {item}'**
  String addMatchReadded(String item);

  /// Job 352 (IO4, flag learned-order): the edit sheet's place chip and option label; name is the item the item stands after in its store's order
  ///
  /// In de, this message translates to:
  /// **'Neben {name}'**
  String placeNextTo(String name);

  /// Job 352: the place chip when the item is first in its store's order, and the option that puts it there
  ///
  /// In de, this message translates to:
  /// **'Ganz vorne'**
  String get placeFirst;

  /// Job 352: screen-reader name of the place chip; place is placeNextTo or placeFirst
  ///
  /// In de, this message translates to:
  /// **'Platz in der Liste: {place}'**
  String chipPlace(String place);

  /// Job 352: hint of the filter field above the place options when the store has more than 15 other items
  ///
  /// In de, this message translates to:
  /// **'Artikel suchen'**
  String get placeFilter;

  /// Job 352 (flag learned-order): under the trip question's buttons; after „Nein“ or a dismissal the question stays away for 60 minutes (TripCubit.snooze, job 357), and that tick run is not detected as a shopping trip (decline_shop, TD-Q5)
  ///
  /// In de, this message translates to:
  /// **'Nach „Nein“ fragen wir eine Stunde lang nicht mehr, und dieser Einkauf wird nicht erkannt.'**
  String get shopAskQuiet;

  /// Job 352: Verlauf, secondary line under the store of a trip detected from the user's own ticks
  ///
  /// In de, this message translates to:
  /// **'Aus deinen Häkchen erkannt'**
  String get detectedOwn;

  /// Job 352: Verlauf, a trip detected from another member's ticks
  ///
  /// In de, this message translates to:
  /// **'Aus den Häkchen von {name} erkannt'**
  String detectedOther(String name);

  /// Job 352: Verlauf, a trip detected from the user's and another member's ticks
  ///
  /// In de, this message translates to:
  /// **'Aus deinen Häkchen und denen von {name} erkannt'**
  String detectedYouAndOther(String name);

  /// Job 352: Verlauf, a trip detected from two other members' ticks
  ///
  /// In de, this message translates to:
  /// **'Aus den Häkchen von {name1} und {name2} erkannt'**
  String detectedTwoOthers(String name1, String name2);

  /// Job 352: trip page title of a detected trip without a walk (ticks in one burst), where the duration would be
  ///
  /// In de, this message translates to:
  /// **'Abgehakt, ohne Dauer'**
  String get tripNoDuration;

  /// Job 352: the trip page's action on a detected trip; any member may remove it
  ///
  /// In de, this message translates to:
  /// **'Kein Einkauf'**
  String get tripNotShopping;

  /// Job 352: the confirm dialog of tripNotShopping
  ///
  /// In de, this message translates to:
  /// **'Kein Einkauf? Die Häkchen bleiben, aber die Reihenfolge lernt nicht mehr daraus.'**
  String get tripNotShoppingBody;

  /// Job 352: the confirm dialog's button that removes the detected trip
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get tripNotShoppingConfirm;

  /// Job 352: snackbar in Verlauf after a detected trip was removed
  ///
  /// In de, this message translates to:
  /// **'Entfernt'**
  String get tripRemoved;

  /// Job 352: snackbar when removing a detected trip failed
  ///
  /// In de, this message translates to:
  /// **'Der Einkauf konnte nicht entfernt werden. Versuch es noch mal.'**
  String get tripRemoveFailed;

  /// Job 352: title of the list's card after the user's first detected trip, shown once per person
  ///
  /// In de, this message translates to:
  /// **'Einkauf bei {store} erkannt'**
  String detectedCardTitle(String store);

  /// Job 352: the first-detected-trip card's title for a trip without a store
  ///
  /// In de, this message translates to:
  /// **'Einkauf erkannt'**
  String get detectedCardTitleNoStore;

  /// Job 352: body of the first-detected-trip card; names the Settings switch detectTrips word for word
  ///
  /// In de, this message translates to:
  /// **'Snacklist merkt sich, in welcher Reihenfolge du abhakst, und sortiert die Liste beim nächsten Mal so. Der Einkauf steht im Verlauf, für die anderen im Haushalt ohne Uhrzeit. Abschalten kannst du das in den Einstellungen unter „Einkäufe aus meinen Häkchen erkennen“.'**
  String get detectedCardBody;

  /// Job 352: the first-detected-trip card's button that opens the trip
  ///
  /// In de, this message translates to:
  /// **'Ansehen'**
  String get detectedCardView;

  /// Job 352: the first-detected-trip card's button that closes it for good
  ///
  /// In de, this message translates to:
  /// **'Verstanden'**
  String get detectedCardGotIt;

  /// Job 352: Einstellungen, section label over the trip detection switch
  ///
  /// In de, this message translates to:
  /// **'Einkäufe'**
  String get settingsTrips;

  /// Job 352: Einstellungen switch; on, the server detects shopping trips from the user's own ticks and learns the list's order from them
  ///
  /// In de, this message translates to:
  /// **'Einkäufe aus meinen Häkchen erkennen'**
  String get detectTrips;

  /// Job 352: under the detectTrips switch
  ///
  /// In de, this message translates to:
  /// **'Nutzt nur, wann du abhakst. Kein Standort.'**
  String get detectTripsHint;

  /// Job 397: Zugänge, header of the one section of access keys (MCP and API) while the unified-keys flag and server switch are on
  ///
  /// In de, this message translates to:
  /// **'Zugriffsschlüssel'**
  String get accessKeys;

  /// Job 397: Zugänge, under the accessKeys header: what an access key is for
  ///
  /// In de, this message translates to:
  /// **'Ein Zugriffsschlüssel verbindet KI-Assistenten über den MCP-Server und eigene Skripte über die API mit eurer Liste. Ein Schlüssel gilt für beides und darf nur lesen oder lesen und schreiben.'**
  String get accessKeysUnifiedHint;

  /// Job 397: as accessKeysHousehold in the access keys section
  ///
  /// In de, this message translates to:
  /// **'Neue Schlüssel gelten für „{household}“, den Haushalt, der gerade offen ist.'**
  String accessKeysUnifiedHousehold(String household);

  /// Job 397: access keys section, under the MCP server URL
  ///
  /// In de, this message translates to:
  /// **'Für KI-Assistenten: Verbinde per Anmeldung (OAuth) oder mit einem Zugriffsschlüssel.'**
  String get accessKeysMcpBody;

  /// Job 397: access keys section, under the API URL (public-api flag on)
  ///
  /// In de, this message translates to:
  /// **'Für eigene Skripte und Automationen: Lies und, wenn du es erlaubst, ändere eure Liste über HTTP, mit einem Zugriffsschlüssel.'**
  String get accessKeysApiBody;

  /// Job 397: access keys section, empty list
  ///
  /// In de, this message translates to:
  /// **'Kein aktiver Zugriffsschlüssel.'**
  String get noAccessKeys;

  /// Job 397: access keys section, button and dialog title for a new access key
  ///
  /// In de, this message translates to:
  /// **'Schlüssel erstellen'**
  String get createAccessKey;

  /// Job 397: new access key dialog, hint in the name field
  ///
  /// In de, this message translates to:
  /// **'z. B. KI-Assistent, Kurzbefehle oder Home Assistant'**
  String get accessKeyNameHint;

  /// Job 397: dialog title after a new access key was made
  ///
  /// In de, this message translates to:
  /// **'Zugriffsschlüssel erstellt'**
  String get accessKeyCreated;

  /// Job 397: new access key dialog: the secret is shown only now
  ///
  /// In de, this message translates to:
  /// **'Kopiere den Schlüssel jetzt. Er wird nicht noch einmal angezeigt.'**
  String get accessKeyShownOnce;

  /// Job 397: confirm dialog title before revoking an access key
  ///
  /// In de, this message translates to:
  /// **'Zugriffsschlüssel widerrufen?'**
  String get revokeAccessKeyTitle;

  /// Job 397: confirm dialog body before revoking an access key
  ///
  /// In de, this message translates to:
  /// **'Assistenten und Skripte, die ihn benutzen, verlieren sofort den Zugriff.'**
  String get revokeAccessKeyBody;

  /// Job 397: snack bar, the member already has 20 active access keys (MCP and API together)
  ///
  /// In de, this message translates to:
  /// **'Höchstens 20 aktive Zugriffsschlüssel. Widerrufe erst einen.'**
  String get tooManyAccessKeys;

  /// Job 397: snack bar, the server refused to create an access key outside the app's own sign-in (session_required)
  ///
  /// In de, this message translates to:
  /// **'Zugriffsschlüssel kannst du nur hier in der App erstellen, während du angemeldet bist.'**
  String get accessKeySessionRequired;

  /// Job 399 SC1: the card at the list's top after the user ticked the last open item of a store linked to a chain app, e.g. „Lidl ist erledigt“. {store} is the household's store name
  ///
  /// In de, this message translates to:
  /// **'{store} ist erledigt'**
  String storeDoneTitle(String store);

  /// Job 399 SC1: the done card's button that opens the store's chain app (its screen-reader name is storeAppOpen with the app's name)
  ///
  /// In de, this message translates to:
  /// **'App öffnen'**
  String get storeDoneOpen;

  /// Job 463: More row and page title of the push settings (household-add alert, shopping-day reminder); was the Einstellungen section label of job 377
  ///
  /// In de, this message translates to:
  /// **'Mitteilungen'**
  String get settingsPush;

  /// Job 377 (flag push-household-add): Einstellungen switch, off by default; on, the user gets a push when another member adds an item
  ///
  /// In de, this message translates to:
  /// **'Wenn jemand etwas hinzufügt'**
  String get pushHouseholdAdd;

  /// Job 377: under the pushHouseholdAdd switch; the example names a member and an item, as the push does
  ///
  /// In de, this message translates to:
  /// **'Mitteilung mit Name und Eintrag, z. B. „Lea hat Milch hinzugefügt“. Bei Artikeln aus der Apotheke oder Drogerie ohne Artikelnamen, etwa „Lea hat etwas zur Liste hinzugefügt“. Mehrere kurz nacheinander kommen zusammen.'**
  String get pushHouseholdAddHint;

  /// Job 377: snackbar when the switch is turned on but the OS refuses notifications
  ///
  /// In de, this message translates to:
  /// **'Mitteilungen sind für Snacklist ausgeschaltet. Erlaube sie in den Einstellungen deines Geräts.'**
  String get pushBlocked;

  /// Job 377 (N-401, Art. 21): Einstellungen switch under Mitteilungen; on, the user's display name is left out of other members' pushes
  ///
  /// In de, this message translates to:
  /// **'Meinen Namen in Mitteilungen weglassen'**
  String get pushNameHidden;

  /// Job 377: under the pushNameHidden switch
  ///
  /// In de, this message translates to:
  /// **'Andere sehen dann „Jemand hat Milch hinzugefügt“, auch wenn du selbst keine Mitteilungen eingeschaltet hast.'**
  String get pushNameHiddenHint;

  /// Job 378: Mitteilungen page (job 463), section label over the weekday chips of the shopping-day reminder
  ///
  /// In de, this message translates to:
  /// **'Einkaufstag-Erinnerung'**
  String get shoppingDayTitle;

  /// Job 378: above the weekday chips; the reminder is a push at 19:00 local the evening before a picked weekday, none picked means off
  ///
  /// In de, this message translates to:
  /// **'Wähle deine Einkaufstage. Am Abend davor um 19 Uhr in der Zeitzone deines Geräts schickt Snacklist dir einen Hinweis aufs Handy.'**
  String get shoppingDayHint;

  /// Job 378: snackbar when a weekday was picked but the OS refuses notifications; nothing is saved
  ///
  /// In de, this message translates to:
  /// **'Mitteilungen sind für Snacklist ausgeschaltet. Schalte sie in den Einstellungen deines Handys ein.'**
  String get shoppingDayBlocked;

  /// Job 462: a guide from snacklist.app opened in the app could not be fetched (offline, server error)
  ///
  /// In de, this message translates to:
  /// **'Die Anleitung konnte nicht geladen werden. Bist du online?'**
  String get guideFailed;

  /// Job 462: the guide index from snacklist.app could not be fetched
  ///
  /// In de, this message translates to:
  /// **'Die Anleitungen konnten nicht geladen werden. Bist du online?'**
  String get guidesFailed;

  /// Job 462: the guide link points to a guide the site no longer has (404)
  ///
  /// In de, this message translates to:
  /// **'Diese Anleitung gibt es nicht mehr.'**
  String get guideMissing;

  /// Job 462: button on a missing guide, opens the guide index in the guide's language
  ///
  /// In de, this message translates to:
  /// **'Alle Anleitungen'**
  String get guidesAll;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
