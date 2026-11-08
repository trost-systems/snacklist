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
  /// **'Hummlist'**
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

  /// No description provided for @dictationNoOfflineGerman.
  ///
  /// In de, this message translates to:
  /// **'Diktieren geht nur offline, damit deine Stimme auf dem Gerät bleibt. Dafür fehlt hier die deutsche Offline-Spracherkennung. Lade sie in den Systemeinstellungen herunter oder tippe den Eintrag ein.'**
  String get dictationNoOfflineGerman;

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
  /// **'Partner einladen'**
  String get inviteMember;

  /// No description provided for @joinOtherHousehold.
  ///
  /// In de, this message translates to:
  /// **'Anderem Haushalt beitreten'**
  String get joinOtherHousehold;

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
  /// **'Willkommen bei Hummlist'**
  String get onboardingTitle;

  /// No description provided for @onboardingBody.
  ///
  /// In de, this message translates to:
  /// **'Hummlist teilt eine Einkaufsliste mit allen in deinem Haushalt. Erstelle einen neuen Haushalt oder nimm eine Einladung an.'**
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
  /// **'Einträge deiner Einkaufsliste lesen, hinzufügen, abhaken und verschieben. {client} und sein Anbieter erhalten dabei die Inhalte eurer Liste.'**
  String consentListAccess(String client);

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
  /// **'Für Claude, ChatGPT und andere KI-Assistenten. Verbinde per Anmeldung (OAuth) oder mit einem Zugriffstoken.'**
  String get mcpServerBody;

  /// No description provided for @accessTokens.
  ///
  /// In de, this message translates to:
  /// **'Zugriffstoken'**
  String get accessTokens;

  /// No description provided for @noTokens.
  ///
  /// In de, this message translates to:
  /// **'Kein aktiver Token.'**
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
  /// **'Token erstellen'**
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
  /// **'Token erstellt'**
  String get tokenCreated;

  /// No description provided for @tokenShownOnce.
  ///
  /// In de, this message translates to:
  /// **'Kopiere den Token jetzt. Er wird nicht noch einmal angezeigt.'**
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
  /// **'Token widerrufen?'**
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
  /// **'Höchstens 20 aktive Tokens.'**
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
  /// **'Sag zum Beispiel: „Hey Siri, etwas auf Hummlist setzen“.'**
  String get siriSayHint;

  /// No description provided for @siriShowPhrases.
  ///
  /// In de, this message translates to:
  /// **'Siri-Sätze anzeigen'**
  String get siriShowPhrases;

  /// No description provided for @siriOldShortcutHint.
  ///
  /// In de, this message translates to:
  /// **'Den alten Kurzbefehl brauchst du nicht mehr. Seinen Token „{name}“ kannst du unten löschen.'**
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
  /// **'Siri kann auf dem iPhone dann nichts mehr hinzufügen. Beim nächsten Start von Hummlist dort wird Siri neu eingerichtet.'**
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
  /// **'Tippen hakt ab · Halten bearbeitet'**
  String get listHint;

  /// No description provided for @listHintDismiss.
  ///
  /// In de, this message translates to:
  /// **'Verstanden'**
  String get listHintDismiss;

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
  /// **'Dein Konto, dein Profil, deine Zugangs-Tokens und deine verbundenen Apps werden endgültig gelöscht. Das lässt sich nicht rückgängig machen.'**
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
  /// **'Du bist das letzte Mitglied. Deshalb wird der Haushalt „{household}“ mit Liste, Verlauf, Kategorien und Geschäften gelöscht.'**
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

  /// No description provided for @accountDeletePremium.
  ///
  /// In de, this message translates to:
  /// **'„{household}“ hat Hummlist Premium. Es gehört zum Haushalt und endet mit ihm. Archivieren geht hier nicht, denn ein archivierter Haushalt wird mit deinem Konto gelöscht. Soll der Haushalt mit Premium bleiben, lade vorher jemanden ein und lösche dein Konto erst, wenn die Person beigetreten ist.'**
  String accountDeletePremium(String household);

  /// Account deletion (job 104): the last member's household has Hummlist Premium, in builds without the archive UI; accountDeletePremium without its archive sentence
  ///
  /// In de, this message translates to:
  /// **'„{household}“ hat Hummlist Premium. Das gehört zum Haushalt. Löschst du dein Konto, endet es. Soll es bleiben? Dann lad erst jemand ein. Warte, bis die Person beigetreten ist. Lösch dann dein Konto.'**
  String accountDeletePremiumLastMember(String household);

  /// names: quoted and joined, like „Ferien“ und „Büro“
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Dein archivierter Haushalt {names} wird mit deinem Konto gelöscht.} other{Deine archivierten Haushalte {names} werden mit deinem Konto gelöscht.}}'**
  String accountDeleteArchived(int count, String names);

  /// No description provided for @accountDeleteArchivedPremium.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Dein archivierter Haushalt {names} wird mit deinem Konto gelöscht, und mit ihm sein Hummlist Premium.} other{Deine archivierten Haushalte {names} werden mit deinem Konto gelöscht, und mit ihnen ihr Hummlist Premium.}}'**
  String accountDeleteArchivedPremium(int count, String names);

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
  /// **'Falls du dich mit Apple angemeldet hattest: Entferne „Hummlist“ auf deinem iPhone unter Einstellungen › [dein Name] › Anmelden & Sicherheit › Mit Apple anmelden.'**
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

  /// Screen-reader name of the add sheet's store chip while Hummlist picks the store and knows none yet
  ///
  /// In de, this message translates to:
  /// **'Laden: automatisch'**
  String get storeAuto;

  /// The add sheet's store chip while Hummlist picks the store and knows none yet; next to the automatic mark
  ///
  /// In de, this message translates to:
  /// **'Laden'**
  String get chipStoreShort;

  /// The add sheet's category chip while Hummlist picks the category and knows none yet; next to the automatic mark
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get chipCategoryShort;

  /// Screen-reader name of the add sheet's store chip showing the store Hummlist picked
  ///
  /// In de, this message translates to:
  /// **'Laden: automatisch, {name}'**
  String storeAutoValue(String name);

  /// Screen-reader name of the add sheet's category chip showing the category Hummlist picked
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

  /// More: label above the legal rows (imprint, privacy policy, terms, licenses)
  ///
  /// In de, this message translates to:
  /// **'Rechtliches'**
  String get legal;

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

  /// More → Datenschutz and Rechtliches: the link to the privacy policy on the site
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
  /// **'Hummlist hat Verbesserungen geladen. Starte die App neu, um sie zu nutzen.'**
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
  /// **'Darf Hummlist Nutzungsdaten erfassen?'**
  String get analyticsConsentTitle;

  /// Analytics consent screen: who asks, why, what is stored and sent and what never is, how to withdraw. Ends right before analyticsConsentPrivacyLink, which follows after a space and is closed by a full stop. Version 2026-11-01 (consentTextVersion, docs/consent/2026-11-01.md): changing it needs a new version. approved by Peter 2026-11-01 (Legal 12:55)
  ///
  /// In de, this message translates to:
  /// **'Hummlist (Anbieter: Peter Trost) möchte verstehen, welche Funktionen genutzt werden, Fehler finden, messen, ob sich Hummlist trägt, und neue Funktionen schrittweise freischalten. Dafür speichert Hummlist eine zufällige Kennung auf diesem Gerät und sendet damit pseudonyme Nutzungsdaten, Fehlerberichte, die Kennung deines Haushalts und technische Angaben zu Gerät oder Browser an unseren Dienstleister PostHog (Server in der EU). Listeninhalte, Namen und E-Mail-Adressen werden nie gesendet. Du kannst jederzeit unter Mehr → Nutzungsdaten widerrufen. Mehr in der'**
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

  /// More: below the analytics switch. Turning it off deletes the install id. approved by Peter 2026-10-30 (legal review H-03)
  ///
  /// In de, this message translates to:
  /// **'Pseudonym an PostHog (Server in der EU), ohne Listeninhalte. Gilt für dieses Gerät. Ausschalten löscht die Kennung auf diesem Gerät.'**
  String get analyticsToggleHint;

  /// More: shown under the version while this install is marked internal (its analytics are filtered out)
  ///
  /// In de, this message translates to:
  /// **'Interne Installation'**
  String get internalInstall;

  /// More, internal installs only: raises a test exception for error tracking
  ///
  /// In de, this message translates to:
  /// **'Testfehler senden'**
  String get sendTestError;

  /// More: opens the feedback form; also the form's title
  ///
  /// In de, this message translates to:
  /// **'Feedback senden'**
  String get feedbackRow;

  /// More: opens Hummlist's page in the App Store or Google Play, to rate it
  ///
  /// In de, this message translates to:
  /// **'Hummlist bewerten'**
  String get rateApp;

  /// More: opens the help and contact page on hummlist.com in the browser
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
  /// **'Peter darf mich dazu kontaktieren'**
  String get feedbackContact;

  /// Feedback form: what is sent along with the note
  ///
  /// In de, this message translates to:
  /// **'App-Version, Gerät, Sprache und aktueller Bildschirm. Keine Listeneinträge.'**
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

  /// No description provided for @onboardingCreateHint.
  ///
  /// In de, this message translates to:
  /// **'Eine neue Liste, zu der du danach deinen Partner einlädst.'**
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

  /// Legal Review L-7 (N-23), approved by Peter 2026-11-01 (L1): character for character; the onboarding store step (job 78: no longer on the stores screen)
  ///
  /// In de, this message translates to:
  /// **'Ladennamen wie dm, Lidl oder EDEKA verwenden wir nur, damit du erkennst, für welchen Laden eine Liste gedacht ist. Die Namen und Marken gehören den jeweiligen Unternehmen. Hummlist ist ein unabhängiges Angebot und steht in keiner Verbindung zu diesen Unternehmen. Sie unterstützen oder empfehlen Hummlist nicht.'**
  String get storesDisclaimer;

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
  /// **'Teile den Link oder den Code mit der Person, mit der du einkaufst. Die Einladung gilt 7 Tage und für eine Person.'**
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

  /// No description provided for @inviteShareText.
  ///
  /// In de, this message translates to:
  /// **'Komm in unseren Hummlist-Haushalt: {link} · Code: {code}'**
  String inviteShareText(String link, String code);

  /// No description provided for @inviteShareTextCodeOnly.
  ///
  /// In de, this message translates to:
  /// **'Komm in unseren Hummlist-Haushalt. Code: {code}'**
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

  /// No description provided for @invitesOpen.
  ///
  /// In de, this message translates to:
  /// **'Offene Einladungen'**
  String get invitesOpen;

  /// No description provided for @invitesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine offenen Einladungen.'**
  String get invitesEmpty;

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
  /// **'Hummlist Lifetime'**
  String get lifetimeTitle;

  /// More: under Hummlist Lifetime while not unlocked
  ///
  /// In de, this message translates to:
  /// **'Hummlist unterstützen'**
  String get lifetimeRowHint;

  /// No description provided for @lifetimeBody.
  ///
  /// In de, this message translates to:
  /// **'Ein Kauf, für euren ganzen Haushalt: Hummlist Lifetime unterstützt die Entwicklung von Hummlist.'**
  String get lifetimeBody;

  /// Hummlist Lifetime: the buy button; the store's sheet shows the price (no store call before this tap, H-67)
  ///
  /// In de, this message translates to:
  /// **'Weiter zum Kauf'**
  String get lifetimeBuy;

  /// Hummlist Lifetime: under Buy; the page shows no price, the store's sheet does
  ///
  /// In de, this message translates to:
  /// **'Den Preis zeigen dir der App Store oder Google Play, bevor du kaufst.'**
  String get lifetimePriceInStore;

  /// No description provided for @lifetimeRestore.
  ///
  /// In de, this message translates to:
  /// **'Kauf wiederherstellen'**
  String get lifetimeRestore;

  /// No description provided for @lifetimeUnlockedBody.
  ///
  /// In de, this message translates to:
  /// **'Hummlist Lifetime ist für euren ganzen Haushalt freigeschaltet. Danke!'**
  String get lifetimeUnlockedBody;

  /// Hummlist Lifetime: Ask to Buy or a Play payment that completes later
  ///
  /// In de, this message translates to:
  /// **'Wartet auf Bestätigung'**
  String get lifetimePending;

  /// No description provided for @lifetimePendingBody.
  ///
  /// In de, this message translates to:
  /// **'Hummlist Lifetime wird freigeschaltet, sobald der Kauf bestätigt ist. Das kann etwas dauern.'**
  String get lifetimePendingBody;

  /// Hummlist Lifetime: bought or restored, waiting for the unlock from the server
  ///
  /// In de, this message translates to:
  /// **'Wird freigeschaltet …'**
  String get lifetimeUnlocking;

  /// Hummlist Lifetime: bought, but the server's unlock has not arrived within a minute
  ///
  /// In de, this message translates to:
  /// **'Dein Kauf ist angekommen, die Freischaltung dauert nur länger als sonst. Sie erscheint hier von selbst; bitte nicht noch einmal kaufen.'**
  String get lifetimeUnlockDelayed;

  /// Hummlist Lifetime: the household has two or more store purchases; the refund help link is on the page
  ///
  /// In de, this message translates to:
  /// **'Euer Haushalt hat Hummlist Lifetime mehr als einmal gekauft. Einen der Käufe kannst du dir erstatten lassen.'**
  String get lifetimeBoughtTwice;

  /// No description provided for @lifetimeCanceled.
  ///
  /// In de, this message translates to:
  /// **'Kauf abgebrochen.'**
  String get lifetimeCanceled;

  /// Hummlist Lifetime: the store has no product yet
  ///
  /// In de, this message translates to:
  /// **'Hummlist Lifetime ist bald verfügbar.'**
  String get lifetimeComingSoon;

  /// No description provided for @lifetimeStoreOffline.
  ///
  /// In de, this message translates to:
  /// **'Der Store ist gerade nicht erreichbar. Prüfe die Verbindung.'**
  String get lifetimeStoreOffline;

  /// No description provided for @lifetimeUsedElsewhere.
  ///
  /// In de, this message translates to:
  /// **'Dieser Kauf gehört zu einem anderen, früheren Haushalt und bleibt dort. Hier schaltet er nichts frei.'**
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

  /// No description provided for @lifetimeWeb.
  ///
  /// In de, this message translates to:
  /// **'Kaufen kannst du Hummlist Lifetime in der iPhone- oder Android-App. Danach ist es auch hier für deinen ganzen Haushalt freigeschaltet.'**
  String get lifetimeWeb;

  /// Hummlist Lifetime: the household's unlock is not known yet (loading or offline); no Buy button meanwhile
  ///
  /// In de, this message translates to:
  /// **'Wir prüfen, ob dein Haushalt Hummlist Lifetime schon hat …'**
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
  /// **'Hummlist Lifetime gehört immer zu dem Haushalt, in dem es gekauft wurde. Käufe im App Store erstattet nur Apple. Bei Google Play beantragst du die Erstattung in den ersten 48 Stunden bei Google; danach schreib uns an support@hummlist.com, wir prüfen jede Anfrage einzeln. Deine gesetzlichen Rechte bleiben unberührt.'**
  String get refundHelpBody;

  /// No description provided for @refundHelpApple.
  ///
  /// In de, this message translates to:
  /// **'iPhone: Öffne reportaproblem.apple.com, melde dich mit deinem Apple Account an, wähle „Rückerstattung anfordern“ und dann Hummlist Lifetime.'**
  String get refundHelpApple;

  /// No description provided for @refundHelpGoogle.
  ///
  /// In de, this message translates to:
  /// **'Android, in den ersten 48 Stunden: Öffne Google Play, tippe auf dein Profilbild, dann „Zahlungen und Abos“, „Budget und Bestellverlauf“, wähle Hummlist Lifetime und „Problem melden“. Danach schreib uns mit der Bestellnummer (beginnt mit „GPA.“) oder der E-Mail-Adresse deines Google-Kontos.'**
  String get refundHelpGoogle;

  /// No description provided for @refundHelpReason.
  ///
  /// In de, this message translates to:
  /// **'Als Grund kannst du schreiben: „Mein Haushalt war schon freigeschaltet.“'**
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

  /// Refund help: opens the FAQ on hummlist.com/support with the refund question (H-76)
  ///
  /// In de, this message translates to:
  /// **'Mehr in den häufigen Fragen'**
  String get refundHelpFaqLink;

  /// No description provided for @joinTargetUnlocked.
  ///
  /// In de, this message translates to:
  /// **'Dieser Haushalt hat Hummlist Lifetime. Du musst nichts kaufen.'**
  String get joinTargetUnlocked;

  /// No description provided for @joinRefundLink.
  ///
  /// In de, this message translates to:
  /// **'Du hast Hummlist Lifetime vor Kurzem gekauft? So forderst du den Kauf zurück'**
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
  /// **'Mit Hummlist Lifetime'**
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
  /// **'Hummlist Premium'**
  String get premiumTitle;

  /// Premium page (PW-P4, job 87): the hero's title; one member buys, the household has it
  ///
  /// In de, this message translates to:
  /// **'Einer kauft. Alle haben es.'**
  String get premiumHeroTitle;

  /// Premium page (PW-P4, job 87): under the hero title
  ///
  /// In de, this message translates to:
  /// **'Hummlist Premium gilt für euren ganzen Haushalt, auch für alle, die später dazukommen.'**
  String get premiumHeroBody;

  /// Premium page (PW-P4, job 87): benefit line, Siri
  ///
  /// In de, this message translates to:
  /// **'Per Siri auf die Liste, ohne die App zu öffnen'**
  String get premiumBenefitSiri;

  /// FINAL (Legal Review N-67, 2026-11-04; Peter 2026-10-31: no assistant brand named): Premium page, benefit line, AI assistants over MCP
  ///
  /// In de, this message translates to:
  /// **'KI-Assistenten, die MCP unterstützen, mit eurer Liste verbinden'**
  String get premiumBenefitAi;

  /// Premium page (PW-P4, job 87): benefit line, the public API; only while the public-api flag is on
  ///
  /// In de, this message translates to:
  /// **'Eigene Automationen mit der Hummlist API'**
  String get premiumBenefitApi;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: an active yearly plan that renews
  ///
  /// In de, this message translates to:
  /// **'Hummlist Premium aktiv (jährlich, verlängert sich am {date})'**
  String premiumStatusRenews(DateTime date);

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: an active yearly plan with auto-renew off
  ///
  /// In de, this message translates to:
  /// **'Hummlist Premium aktiv (jährlich, läuft am {date} aus)'**
  String premiumStatusEnds(DateTime date);

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the household has Lifetime
  ///
  /// In de, this message translates to:
  /// **'Hummlist Premium Lifetime'**
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
  /// **'In der Beta kostenlos freigeschaltet, bis Hummlist Premium startet'**
  String get premiumStatusBeta;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the household's rows are loading or offline; no Buy
  ///
  /// In de, this message translates to:
  /// **'Wir prüfen, ob euer Haushalt Hummlist Premium schon hat …'**
  String get premiumChecking;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the yearly plan's card title, offered first
  ///
  /// In de, this message translates to:
  /// **'Jährlich'**
  String get premiumYearlyTitle;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49, 87). Premium page, yearly tile: the billing period under the store's price, followed by „inkl. MwSt.“ for a euro price
  ///
  /// In de, this message translates to:
  /// **'pro Jahr'**
  String get premiumPerYear;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the one-time purchase's card title
  ///
  /// In de, this message translates to:
  /// **'Lifetime'**
  String get premiumLifetimeTitle;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49, 87). Premium page, Lifetime tile: under the store's price, followed by „inkl. MwSt.“ for a euro price
  ///
  /// In de, this message translates to:
  /// **'einmalig'**
  String get premiumOneTime;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: Lifetime framed as three times the yearly price (Spec #4 AC9), without computing an amount
  ///
  /// In de, this message translates to:
  /// **'Einmal zahlen, für immer: so viel wie drei Jahre.'**
  String get premiumLifetimeValue;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the subscription disclosures next to the yearly card and its Buy button (App Store Review Guidelines 3.1.2, Google Play)
  ///
  /// In de, this message translates to:
  /// **'Hummlist Premium jährlich, Laufzeit 1 Jahr. Das Abo verlängert sich automatisch um ein Jahr, wenn du es nicht mindestens 24 Stunden vor Ende der Laufzeit kündigst. Bezahlt wird über dein Apple- bzw. Google-Konto, bei der Bestätigung des Kaufs und bei jeder Verlängerung. Verwalten und kündigen kannst du das Abo in den Abo-Einstellungen des App Store bzw. von Google Play.'**
  String get premiumYearlyTerms;

  /// LEGAL REVIEW Q6 (job 87): the household binding, shown before purchase. Wording pending Legal Review.
  ///
  /// In de, this message translates to:
  /// **'Premium gehört dann zum Haushalt „{household}“ und bleibt dort, auch wenn du den Haushalt später verlässt.'**
  String premiumHousehold(String household);

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: buy the yearly plan; RevenueCat starts only on this tap (H-67)
  ///
  /// In de, this message translates to:
  /// **'Jährlich abschließen'**
  String get premiumBuyYearly;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: buy Lifetime; RevenueCat starts only on this tap (H-67)
  ///
  /// In de, this message translates to:
  /// **'Lifetime kaufen'**
  String get premiumBuyLifetime;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: the store's prices could not be read (offline, store unavailable); no Buy without a price (A2-5)
  ///
  /// In de, this message translates to:
  /// **'Hummlist Premium ist gerade nicht verfügbar.'**
  String get premiumUnavailable;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: link to the terms; Apple's standard EULA on iOS, a placeholder page elsewhere (no Hummlist terms exist, H-93)
  ///
  /// In de, this message translates to:
  /// **'Nutzungsbedingungen (EULA)'**
  String get premiumTermsLink;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: link to the privacy policy
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung'**
  String get premiumPrivacyLink;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: after lifetimeUsedElsewhere when the yearly plan belongs to another household (one subscription per Apple ID and group)
  ///
  /// In de, this message translates to:
  /// **'Dein Apple- bzw. Google-Konto zahlt schon ein Jahresabo für einen anderen Haushalt. Jemand anderes aus diesem Haushalt kann Hummlist Premium abschließen.'**
  String get premiumUsedElsewhereYearly;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page: two yearly plans run at once (H-84); followed by the manage link
  ///
  /// In de, this message translates to:
  /// **'Euer Haushalt hat zwei Jahresabos. Kündigen kann jedes nur, wer es abgeschlossen hat.'**
  String get premiumTwoYearly;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page on the web: no sales on the web
  ///
  /// In de, this message translates to:
  /// **'Hummlist Premium kaufst du in der iPhone- oder Android-App. Danach ist es auch hier für deinen ganzen Haushalt freigeschaltet.'**
  String get premiumWeb;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Refund help: a short note for the yearly plan below the H-76 texts, which name only Lifetime (NEEDS_LEAD Job 49)
  ///
  /// In de, this message translates to:
  /// **'Für das Jahresabo gilt dasselbe. Eine Kündigung beendet nur die Verlängerung; das laufende Jahr wird nicht automatisch erstattet.'**
  String get premiumRefundYearly;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. Premium page: opens the store's subscription management (H-83)
  ///
  /// In de, this message translates to:
  /// **'Abo verwalten oder kündigen'**
  String get premiumManage;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Premium page on the web: before the two store links
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
  /// **'Euer Haushalt hat schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird weiter abgerechnet, bis es gekündigt wird; das restliche Abojahr wird nicht automatisch erstattet. Kündigen kann nur, wer das Abo abgeschlossen hat, unter [Abos verwalten]. Hummlist kann das Abo nicht kündigen.'**
  String get premiumLifetimeWhileYearly;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. premiumLifetimeWhileYearly for the subscriber (H-84). [brackets]: the store link
  ///
  /// In de, this message translates to:
  /// **'Euer Haushalt hat schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird weiter abgerechnet, bis es gekündigt wird; das restliche Abojahr wird nicht automatisch erstattet. Du kannst es unter [Abo verwalten] kündigen. Hummlist kann das Abo nicht kündigen.'**
  String get premiumLifetimeWhileYearlySubscriber;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. Lifetime-while-yearly warning: opens the store sheet (RevenueCat starts only here, H-67). EN: Lead wording, PLACEHOLDER
  ///
  /// In de, this message translates to:
  /// **'Trotzdem kaufen'**
  String get premiumBuyAnyway;

  /// Legal Review K.13 (job 49 ADDENDUM 2), word for word: do not reword. Before deleting the account, leaving, deleting or archiving a household, to the subscriber of a renewing yearly plan (H-85)
  ///
  /// In de, this message translates to:
  /// **'Dein Jahresabo für Hummlist Premium läuft weiter und wird über dein Apple- bzw. Google-Konto abgerechnet, bis du es kündigst. Löschen oder Verlassen kündigt es nicht.'**
  String get premiumBillingContinues;

  /// PLACEHOLDER (job 49): Hummlist Launch / Legal Review K.13 write the final copy (NEEDS_LEAD Job 49). Lead wording for Legal Review: the same moment, to members who are not the subscriber (H-85, NEEDS_LEAD Job 49)
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

  /// PLACEHOLDER (job 50): Hummlist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings (Zugänge), locked household: the card's title
  ///
  /// In de, this message translates to:
  /// **'Teil von Hummlist Premium'**
  String get integrationPremiumTitle;

  /// PLACEHOLDER (job 50): Hummlist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: why the connections are paused; nothing is removed
  ///
  /// In de, this message translates to:
  /// **'Siri und KI-Assistenten gehören zu Hummlist Premium. Eure Verbindungen bleiben gespeichert und funktionieren wieder, sobald euer Haushalt Hummlist Premium hat.'**
  String get integrationPremiumBody;

  /// PLACEHOLDER (job 50): Hummlist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: included in Hummlist Premium
  ///
  /// In de, this message translates to:
  /// **'Siri auf dem iPhone'**
  String get integrationPremiumSiri;

  /// PLACEHOLDER (job 50): Hummlist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: included in Hummlist Premium
  ///
  /// In de, this message translates to:
  /// **'KI-Assistenten, die MCP unterstützen'**
  String get integrationPremiumAi;

  /// PLACEHOLDER (job 50): Hummlist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: planned, not built yet
  ///
  /// In de, this message translates to:
  /// **'Später: Google Assistant und Apple Watch'**
  String get integrationPremiumLater;

  /// PLACEHOLDER (job 50): Hummlist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: button that opens the Hummlist Premium page (only where it is sold)
  ///
  /// In de, this message translates to:
  /// **'Hummlist Premium freischalten'**
  String get integrationPremiumBuy;

  /// PLACEHOLDER (job 50): Hummlist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: Hummlist Premium is not sold in this build yet, no button
  ///
  /// In de, this message translates to:
  /// **'Bald verfügbar.'**
  String get integrationPremiumSoon;

  /// PLACEHOLDER (job 50): Hummlist Launch writes the final copy (NEEDS_LEAD Job 50). Integration settings, locked household: shown on each existing connection or token, which stays as it is
  ///
  /// In de, this message translates to:
  /// **'Pausiert: braucht Hummlist Premium'**
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
  /// **'Kann auch Einträge hinzufügen, abhaken und verschieben.'**
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

  /// PLACEHOLDER (job 73): Hummlist Launch writes the final copy. Zugänge, API section, locked household (job 50): the keys stay, unused for now; new ones can still be made
  ///
  /// In de, this message translates to:
  /// **'Die Hummlist-API gehört zu Hummlist Premium. Deine Schlüssel bleiben und funktionieren wieder, sobald dein Haushalt Premium hat.'**
  String get apiPremium;

  /// Zugänge, under the access token heading while the public API is hidden (job 80)
  ///
  /// In de, this message translates to:
  /// **'Mit einem Token baust du eigene Automationen, die eure Liste pflegen, etwa ein Skript oder einen Assistenten am MCP-Server.'**
  String get accessTokensHint;

  /// Zugänge, under the access token heading while the public-api flag is on (job 80)
  ///
  /// In de, this message translates to:
  /// **'Mit einem Token baust du eigene Automationen am MCP-Server, die eure Liste pflegen. Für Programme ohne MCP gibt es unten die API.'**
  String get accessTokensHintWithApi;

  /// Job 169b: Zugänge, under the token hint when the user is in several households: the household a new token acts in
  ///
  /// In de, this message translates to:
  /// **'Ein neuer Token gilt für „{household}“, den Haushalt, der gerade offen ist.'**
  String accessKeysHousehold(String household);

  /// Job 169b: as accessKeysHousehold while the public-api flag is on
  ///
  /// In de, this message translates to:
  /// **'Neue Token und API-Schlüssel gelten für „{household}“, den Haushalt, der gerade offen ist.'**
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
  /// **'Halte einen Artikel gedrückt, ohne ihn zu ziehen, und ändere Menge, Marke, Laden und mehr.'**
  String get tipEditBody;

  /// List tab tip card (job 80): title of the tip that the amount can be typed with the item
  ///
  /// In de, this message translates to:
  /// **'Menge gleich mittippen'**
  String get tipAmountsTitle;

  /// List tab tip card (job 80): the quoted examples must parse with a Menge (app/test/tips/tips_test.dart checks them with parseEntry)
  ///
  /// In de, this message translates to:
  /// **'Schreib „2 Gurken“ oder „Milch 2 l“, und Hummlist erkennt die Menge.'**
  String get tipAmountsBody;

  /// List tab tip card (job 80): tooltip and screen reader label of the X that hides the tip
  ///
  /// In de, this message translates to:
  /// **'Tipp ausblenden'**
  String get tipDismiss;

  /// Job 169b: create_household or accept_invite refused, the user is in 10 households
  ///
  /// In de, this message translates to:
  /// **'Du bist schon in 10 Haushalten. Verlasse einen, bevor du einen neuen anlegst oder beitrittst.'**
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
  /// **'Du bist das letzte Mitglied. Der Haushalt wird mit Liste, Verlauf, Kategorien und Geschäften gelöscht.'**
  String get leaveLast;

  /// Job 169b: leave dialog, last member of a household with Lifetime, archive off
  ///
  /// In de, this message translates to:
  /// **'„{household}“ hat Hummlist Lifetime. Du bist das letzte Mitglied: Verlässt du ihn, wird der Haushalt gelöscht. Hummlist Lifetime endet mit ihm, denn ein Kauf gehört zu seinem Haushalt.'**
  String leaveLifetimeEnds(String household);

  /// Job 169b: leave dialog, last member of a household with Lifetime, archive on
  ///
  /// In de, this message translates to:
  /// **'„{household}“ hat Hummlist Lifetime. Du bist das letzte Mitglied. Archiviere den Haushalt, statt ihn zu löschen: Liste und Hummlist Lifetime bleiben erhalten, und du kannst ihn später unter „Mehr“ wieder aktivieren. Aktivierst du ihn nicht innerhalb von 24 Monaten wieder, wird er gelöscht.'**
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
