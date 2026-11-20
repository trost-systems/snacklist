// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Snacklist';

  @override
  String get addFieldHint => 'What do you need?';

  @override
  String get addButton => 'Add';

  @override
  String get emptyList => 'Your list is empty. Type what you need below.';

  @override
  String get sortingItem => 'Sorting…';

  @override
  String get recentlyUsed => 'Recently used';

  @override
  String get readd => 'Back on the list';

  @override
  String itemDeleted(String name) {
    return '$name deleted';
  }

  @override
  String itemTicked(String name) {
    return '$name ticked off';
  }

  @override
  String alreadyOnList(String name) {
    return '$name is already on the list';
  }

  @override
  String get dedupeMerge => 'Merge';

  @override
  String dedupeMerged(String item) {
    return 'Merged: $item';
  }

  @override
  String mergeRefused(String name) {
    return 'Couldn\'t merge $name';
  }

  @override
  String get dictationStart => 'Dictate';

  @override
  String get dictationStop => 'Stop dictation';

  @override
  String get dictationListening => 'Listening…';

  @override
  String get dictationUnavailable =>
      'Voice input isn\'t available. Allow microphone and speech recognition in Settings.';

  @override
  String get dictationNoOfflineSpeech =>
      'Dictation only works offline, so your voice stays on the device. This device is missing English offline speech recognition. Download it in the system settings or type the item instead.';

  @override
  String get dictationOfflineSpeechDownloading =>
      'Dictation only works offline, so your voice stays on the device. Snacklist asked Android to download English offline speech recognition. Try again once it\'s installed, or type the item instead.';

  @override
  String get dictationNothingHeard => 'I didn\'t hear anything.';

  @override
  String get dictationNothingUnderstood =>
      'I didn\'t catch anything for the list.';

  @override
  String get dictationSplitFailed =>
      'No connection. The text is in the field; check it and tap Add.';

  @override
  String dictationAdded(String items) {
    return 'Added: $items.';
  }

  @override
  String dictationAlreadyOnList(String items) {
    return 'Already on the list: $items.';
  }

  @override
  String get dictationTooMany =>
      'More than thirty at once doesn\'t work; please say the rest again.';

  @override
  String get undo => 'Undo';

  @override
  String get editSheet => 'Edit';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldBrand => 'Brand';

  @override
  String get brandNone => 'no brand';

  @override
  String get itemQuantity => 'Qty';

  @override
  String get fieldProperties => 'Details';

  @override
  String get propertiesExample => 'e.g. organic, 1 l';

  @override
  String get quantityMinus => 'One less';

  @override
  String get quantityPlus => 'One more';

  @override
  String get noStore => 'No store';

  @override
  String chipStore(String name) {
    return 'Store: $name';
  }

  @override
  String chipCategory(String name) {
    return 'Category: $name';
  }

  @override
  String get categoryAuto => 'Category: automatic';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get syncOffline => 'Offline';

  @override
  String get syncOfflineLine =>
      'Your changes will sync once you\'re back online.';

  @override
  String get syncOfflineLabel =>
      'Offline: Your changes will sync once you\'re back online.';

  @override
  String get syncFailing => 'Sync failing';

  @override
  String get syncFailingWord => 'Failing';

  @override
  String get syncFailingLine => 'Your changes are saved on this device.';

  @override
  String get syncFailingLabel =>
      'Sync failing: Your changes are saved on this device.';

  @override
  String get syncRetrying => 'Trying again';

  @override
  String get syncDetails => 'Show details';

  @override
  String get syncSynced => 'Synced';

  @override
  String get syncStillFailing => 'Still failing';

  @override
  String syncFailed(String name) {
    return 'Change rejected: $name';
  }

  @override
  String get inviteMember => 'Invite people';

  @override
  String get inviteScreenTitle => 'Shop together';

  @override
  String get signOut => 'Sign out';

  @override
  String get inviteTitle => 'Invite member';

  @override
  String get inviteBody =>
      'Enter this code in the app or share the link. The invite works for one person and is valid for 7 days.';

  @override
  String get inviteCodeLabel => 'Code';

  @override
  String get inviteLinkLabel => 'Link';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get close => 'Close';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get signIn => 'Sign in';

  @override
  String get signUp => 'Sign up';

  @override
  String get sendMagicLink => 'Email me a sign-in link';

  @override
  String get magicLinkSent =>
      'We sent you a sign-in link. Open it on this device.';

  @override
  String get signUpCheckEmail =>
      'Please confirm your email address with the link we sent you.';

  @override
  String get invalidEmail => 'Please enter a valid email address';

  @override
  String get passwordTooShort => 'At least 6 characters';

  @override
  String authFailed(String message) {
    return 'Sign-in failed: $message';
  }

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signInWithApple => 'Sign in with Apple';

  @override
  String get signInCanceled => 'Sign-in canceled';

  @override
  String get continueWithEmail => 'Continue with email';

  @override
  String get orWithEmail => 'or with email';

  @override
  String get onboardingTitle => 'Welcome to Snacklist';

  @override
  String get onboardingBody =>
      'Snacklist shares one shopping list with everyone in your household. Create a new household or accept an invite.';

  @override
  String get householdName => 'Household name';

  @override
  String get householdNameDefault => 'Our household';

  @override
  String get householdNameHintFurther => 'e.g. Parents, flat, club';

  @override
  String get createHousehold => 'Create a household';

  @override
  String get inviteCode => 'Invite code';

  @override
  String get joinHousehold => 'Join household';

  @override
  String get joinTitle => 'Join a household';

  @override
  String get invalidInvite => 'This code is invalid or has expired.';

  @override
  String genericError(String message) {
    return 'Something went wrong: $message';
  }

  @override
  String get loading => 'Loading…';

  @override
  String get consentTitle => 'Allow access?';

  @override
  String consentSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String consentHousehold(String name) {
    return 'Household: $name';
  }

  @override
  String consentWants(String client) {
    return '$client wants to:';
  }

  @override
  String consentListAccess(String client) {
    return 'Read, add, tick off and move items on your shopping list. $client and its provider will receive your list contents.';
  }

  @override
  String get scopeOpenid => 'Confirm your sign-in';

  @override
  String get scopeEmail => 'Your email address';

  @override
  String get scopeProfile => 'Your name and profile';

  @override
  String get scopePhone => 'Your phone number';

  @override
  String get scopeOfflineAccess => 'Stay signed in';

  @override
  String get consentAllow => 'Allow';

  @override
  String get consentDeny => 'Deny';

  @override
  String get consentConnectedTitle => 'Connected';

  @override
  String get consentDeclinedTitle => 'Not connected';

  @override
  String consentDone(String client) {
    return 'Done, you can return to $client.';
  }

  @override
  String get consentDoneNoClient => 'Done, you can return to your app.';

  @override
  String consentDeclined(String client) {
    return 'Declined, you can return to $client.';
  }

  @override
  String get consentInvalid =>
      'This request is invalid or has expired. Start the connection again in your app.';

  @override
  String get consentErrorTitle => 'Connection expired';

  @override
  String get consentBackToList => 'Back to the list';

  @override
  String get accessTitle => 'Access';

  @override
  String get mcpServer => 'MCP server';

  @override
  String get mcpServerBody =>
      'For Claude, ChatGPT and other AI assistants. Connect by signing in (OAuth) or with an access token.';

  @override
  String get accessTokens => 'Access tokens';

  @override
  String get noTokens => 'No active token.';

  @override
  String tokenHint(String hint) {
    return '…$hint';
  }

  @override
  String createdOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Created $dateString';
  }

  @override
  String lastUsedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Last used $dateString';
  }

  @override
  String get neverUsed => 'Never used';

  @override
  String get createToken => 'Create token';

  @override
  String get create => 'Create';

  @override
  String get tokenName => 'Name';

  @override
  String get tokenNameHint => 'e.g. Claude or Shortcuts';

  @override
  String get tokenCreated => 'Token created';

  @override
  String get tokenShownOnce => 'Copy the token now. It won\'t be shown again.';

  @override
  String get done => 'Done';

  @override
  String revokeToken(String name) {
    return 'Revoke $name';
  }

  @override
  String get revokeTokenTitle => 'Revoke token?';

  @override
  String get revokeTokenBody => 'Apps using it lose access right away.';

  @override
  String get revoke => 'Revoke';

  @override
  String get tooManyTokens => 'At most 20 active tokens.';

  @override
  String get connectedApps => 'Connected apps';

  @override
  String get noConnectedApps => 'No apps connected yet.';

  @override
  String get siriHeader => 'Siri';

  @override
  String get siriThisIphone => 'Siri (this iPhone)';

  @override
  String get siriOtherIphone => 'Siri (other iPhone)';

  @override
  String get siriSayHint => 'For example, say “Hey Siri, add to Snacklist”.';

  @override
  String get siriShowPhrases => 'Show Siri phrases';

  @override
  String siriOldShortcutHint(String name) {
    return 'You no longer need the old shortcut. You can delete its token “$name” below.';
  }

  @override
  String get siriPhrasesTitle => 'Siri phrases';

  @override
  String get siriPhrasesEnglish => 'In English';

  @override
  String get siriPhrasesGerman => 'In German';

  @override
  String siriPhrase(String phrase) {
    return '“$phrase”';
  }

  @override
  String get revokeSiriTitle => 'Revoke Siri access?';

  @override
  String get revokeSiriBody =>
      'Siri on that iPhone can no longer add items. Snacklist sets Siri up again the next time it starts there.';

  @override
  String connectedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Connected $dateString';
  }

  @override
  String get disconnect => 'Disconnect';

  @override
  String disconnectApp(String name) {
    return 'Disconnect $name';
  }

  @override
  String disconnectTitle(String name) {
    return 'Disconnect $name?';
  }

  @override
  String get disconnectBody => 'The app loses access to your list right away.';

  @override
  String get categoriesHint =>
      'Items without a store, and stores without their own order, follow this order. Tap a category to rename it.';

  @override
  String get categoryName => 'Name';

  @override
  String get renameCategory => 'Rename category';

  @override
  String get addCategory => 'Add category';

  @override
  String deleteCategory(String name) {
    return 'Delete $name';
  }

  @override
  String get moveItemsTo => 'Move items to';

  @override
  String dragCategory(String name) {
    return 'Move $name';
  }

  @override
  String categoryPosition(int position, int count) {
    return '$position of $count';
  }

  @override
  String categoryNameTaken(String name) {
    return 'A category named “$name” already exists.';
  }

  @override
  String get catalogSaveFailed => 'The change could not be saved.';

  @override
  String get tooManyLists => 'A household can have up to 50 lists.';

  @override
  String get storeLayoutHint =>
      'Order the categories the way you walk through the store. Tap a category to rename it.';

  @override
  String newItemsFrom(int count, String name) {
    return '$count new from $name';
  }

  @override
  String newItems(int count) {
    return '$count new';
  }

  @override
  String get newItem => 'New';

  @override
  String storeSectionLabel(String store, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$store, $_temp0';
  }

  @override
  String itemsWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return '$_temp0';
  }

  @override
  String get expandSection => 'Expand';

  @override
  String get collapseSection => 'Collapse';

  @override
  String get listHint => 'Tap to tick off · Hold to edit';

  @override
  String get reorderNeedsConnection => 'Reordering needs a connection.';

  @override
  String suggestion(String label) {
    return 'Suggestion: $label';
  }

  @override
  String get dueSuggestions => 'Need these again?';

  @override
  String get account => 'Account';

  @override
  String get accountExport => 'Export my data';

  @override
  String get accountExportBody =>
      'Everything stored about you, as a JSON file.';

  @override
  String get accountDelete => 'Delete account';

  @override
  String get accountDeleteTitle => 'Delete account?';

  @override
  String get accountDeleteWhat =>
      'Your account, profile, access tokens and connected apps will be deleted for good. This can\'t be undone.';

  @override
  String accountDeleteKept(String household, String names) {
    return 'The household “$household” stays with $names, list and all. Your items stay there, but without your name.';
  }

  @override
  String accountDeleteKeptUnnamed(String household) {
    return 'The household “$household” stays with the other members, list and all. Your items stay there, but without your name.';
  }

  @override
  String namesAnd(String first, String last) {
    return '$first and $last';
  }

  @override
  String accountDeleteDeleted(String household) {
    return 'You\'re the last member, so the household “$household” will be deleted with its list, history, categories and stores.';
  }

  @override
  String get accountDeleteNone =>
      'You\'re not in a household, so there\'s no shared data.';

  @override
  String get accountDeleteExportHint =>
      'To keep a copy first, use “Export my data” under Account.';

  @override
  String accountDeletePremium(String household) {
    return '“$household” is unlocked as a household, for all its members. This unlock belongs to the household, not to your account, and ends with it. Archiving isn\'t possible here, because an archived household is deleted with your account. To keep the unlock, invite someone first and delete your account only after they have joined.';
  }

  @override
  String get accountDeleteOwnPremium =>
      'Your Snacklist Premium belongs to your account and ends with it, a one-time purchase too. It can\'t be moved to another account.';

  @override
  String accountDeletePremiumLastMember(String household) {
    return '“$household” is unlocked as a household. The unlock belongs to the household. If you delete your account, it ends. Do you want to keep it? Then ask someone to join first. Wait until they have joined. Then delete your account.';
  }

  @override
  String accountDeleteArchived(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Your archived households $names are deleted with your account.',
      one: 'Your archived household $names is deleted with your account.',
    );
    return '$_temp0';
  }

  @override
  String accountDeleteArchivedPremium(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Your archived households $names are deleted with your account, and their Snacklist Premium with them.',
      one:
          'Your archived household $names is deleted with your account, and its Snacklist Premium with it.',
    );
    return '$_temp0';
  }

  @override
  String quotedName(String name) {
    return '“$name”';
  }

  @override
  String get accountDeletePremiumAck =>
      'I know: Premium ends. A purchase isn\'t refunded on its own.';

  @override
  String get accountDeleteConfirmLabel => 'Type DELETE to confirm';

  @override
  String get accountDeleteConfirm => 'Delete for good';

  @override
  String get accountDeleteOffline =>
      'No internet connection. Your account was not deleted. Try again once you\'re online.';

  @override
  String accountDeleteFailed(String code) {
    return 'Deletion failed ($code). Your account was not deleted.';
  }

  @override
  String get accountDeleteCanceled => 'Canceled. Your account was not deleted.';

  @override
  String get accountFateOffline =>
      'No internet connection. Couldn\'t load what happens to your household.';

  @override
  String accountFateFailed(String code) {
    return 'Couldn\'t load what happens to your household ($code).';
  }

  @override
  String get accountDeletedNotice => 'Your account was deleted.';

  @override
  String get accountDeletedApple =>
      'If you signed in with Apple, remove “Snacklist” on your iPhone under Settings › [your name] › Sign-In & Security › Sign in with Apple.';

  @override
  String get exportDone => 'Data exported';

  @override
  String exportDoneAt(String path) {
    return 'Data exported: $path';
  }

  @override
  String get exportOffline =>
      'No internet connection. Your data was not exported.';

  @override
  String exportFailed(String code) {
    return 'Export failed ($code).';
  }

  @override
  String get tabList => 'List';

  @override
  String get tabMore => 'More';

  @override
  String get addSheetHint => 'Tap to add · ↵ takes the first suggestion';

  @override
  String get storeAuto => 'Store: automatic';

  @override
  String get chipStoreShort => 'Store';

  @override
  String get chipCategoryShort => 'Category';

  @override
  String storeAutoValue(String name) {
    return 'Store: automatic, $name';
  }

  @override
  String categoryAutoValue(String name) {
    return 'Category: automatic, $name';
  }

  @override
  String get typeToSuggest => 'Type to see suggestions';

  @override
  String get suggestionTyped => 'As typed';

  @override
  String get suggestionHistory => 'Bought before';

  @override
  String get suggestionPack => 'Other pack';

  @override
  String get suggestionVariant => 'Other kind';

  @override
  String get suggestionSize => 'Other size';

  @override
  String get suggestionBrand => 'Other brand';

  @override
  String get suggestionCatalog => 'From the catalog';

  @override
  String get suggestionDue => 'Due again';

  @override
  String get suggestionRecent => 'Recently used';

  @override
  String addedTo(String name, String store) {
    return 'Added: $name → $store';
  }

  @override
  String addedItem(String name) {
    return 'Added: $name';
  }

  @override
  String get clearInput => 'Clear';

  @override
  String listItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get household => 'Household';

  @override
  String get storesTitle => 'Stores';

  @override
  String get listEdit => 'Edit';

  @override
  String get noStoreRowHint => 'Categories for items without a store';

  @override
  String get storeAdd => 'Add store';

  @override
  String get deleteCategoryEverywhere => 'It disappears from every store.';

  @override
  String get storesHint =>
      'Drag the stores into the order you want on the list. Tap a store to rename it and order its categories.';

  @override
  String dragStore(String store) {
    return 'Move $store';
  }

  @override
  String get storeNew => 'New store';

  @override
  String get storeNewLabel => 'Add a new store';

  @override
  String get storeNameHint => 'Store name';

  @override
  String get storeCreateConfirm => 'Add store';

  @override
  String storeAddedAndSelected(String store) {
    return '$store added and selected';
  }

  @override
  String storeAdded(String store) {
    return '$store added';
  }

  @override
  String get storeSearch => 'Search stores';

  @override
  String storeRename(String store) {
    return 'Rename $store';
  }

  @override
  String storeDelete(String store) {
    return 'Delete $store';
  }

  @override
  String storeDeleteTitle(String store) {
    return 'Delete $store?';
  }

  @override
  String storeNameTaken(String name) {
    return 'A store named “$name” already exists.';
  }

  @override
  String get storesNeedConnection =>
      'Adding, renaming or deleting stores needs a connection.';

  @override
  String get storesEmpty =>
      'No stores yet. Add one and the list sorts your items in the order you walk through it.';

  @override
  String storeDeleteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open items move to “No store”.',
      one: '1 open item moves to “No store”.',
      zero: 'This store has no open items.',
    );
    return '$_temp0 Its aisle order goes too.';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Device language';

  @override
  String languageSystemNow(String language) {
    return 'Currently $language';
  }

  @override
  String languageSystemPicked(String language) {
    return 'Device language ($language)';
  }

  @override
  String get imprint => 'Imprint';

  @override
  String get privacy => 'Privacy';

  @override
  String get licenses => 'Licenses';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get updatePatchTitle => 'Update ready';

  @override
  String get updatePatchBody =>
      'Snacklist has downloaded improvements. Restart the app to use them.';

  @override
  String get updatePatchAction => 'Restart';

  @override
  String get updateStoreTitle => 'New version available';

  @override
  String updateStoreBody(String version) {
    return 'Version $version is in the store. Update to get everything new.';
  }

  @override
  String get updateStoreAction => 'Update';

  @override
  String get updateLater => 'Later';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get categoryProduce => 'Fruit & veg';

  @override
  String get categoryBakery => 'Bread & bakery';

  @override
  String get categoryChilled => 'Chilled';

  @override
  String get categoryMeat => 'Meat & fish';

  @override
  String get categoryPantry => 'Pantry';

  @override
  String get categorySweets => 'Sweets & snacks';

  @override
  String get categoryDrinks => 'Drinks';

  @override
  String get categoryFrozen => 'Frozen';

  @override
  String get categoryHousehold => 'Household';

  @override
  String get categoryDrugstore => '👶 Drugstore';

  @override
  String get categoryPaint => 'Paint & varnish';

  @override
  String get categoryPlumbing => 'Plumbing';

  @override
  String get categoryElectrical => 'Electrical & lighting';

  @override
  String get categoryTools => 'Tools';

  @override
  String get categoryFasteners => 'Screws & fixings';

  @override
  String get categoryBuilding => 'Wood & building';

  @override
  String get categoryGarden => 'Garden & plants';

  @override
  String get categoryOther => 'Other';

  @override
  String get analyticsConsentTitle => 'May Snacklist collect usage data?';

  @override
  String get analyticsConsentBody =>
      'Snacklist (run by Peter Trost) wants to see which features are used, find bugs, measure whether Snacklist pays for itself and switch new features on step by step. For that, Snacklist stores a random ID on this device and uses it to send pseudonymous usage data (for example about items, households and setup, which tips you see and how you use Siri, connected apps and AI assistants via MCP, and API keys), error reports, your household\'s ID and technical details of your device or browser to our service provider PostHog (servers in the EU). List contents, names and e-mail addresses are never sent. You can withdraw any time under More → Usage data. More in the';

  @override
  String get analyticsConsentPrivacyLink => 'privacy policy';

  @override
  String get analyticsAccept => 'Allow';

  @override
  String get analyticsDecline => 'Don\'t allow';

  @override
  String get analyticsSection => 'Usage data';

  @override
  String get analyticsToggle => 'Send usage data and error reports';

  @override
  String get analyticsToggleHint =>
      'Applies to this device. Turning it off deletes the ID on this device.';

  @override
  String get internalInstall => 'Internal installation';

  @override
  String copyInstallId(String id) {
    return 'Copy installation ID: $id';
  }

  @override
  String get sendTestError => 'Send a test error';

  @override
  String get feedbackRow => 'Send feedback';

  @override
  String get rateApp => 'Rate Snacklist';

  @override
  String get helpRow => 'Help & contact';

  @override
  String get feedbackMessage => 'Your message';

  @override
  String get feedbackMessageHint => 'What did you notice?';

  @override
  String get feedbackCategoryBug => 'Bug';

  @override
  String get feedbackCategoryIdea => 'Idea';

  @override
  String get feedbackCategoryOther => 'Other';

  @override
  String get feedbackCategories => 'Type (optional)';

  @override
  String get feedbackContact => 'Snacklist Support may contact me about this';

  @override
  String get feedbackAttached =>
      'App version, device and language. No list items.';

  @override
  String get feedbackAttachedTitle => 'Included:';

  @override
  String get feedbackSend => 'Send';

  @override
  String get feedbackRetry => 'Retry';

  @override
  String get feedbackSending => 'Sending…';

  @override
  String get feedbackThanks => 'Thanks!';

  @override
  String get feedbackFailed => 'Not sent. Check your connection and try again.';

  @override
  String get feedbackScreenshotRefused =>
      'The screenshot wasn\'t accepted. Switch it off to send your message without it.';

  @override
  String feedbackTooLong(int max) {
    return 'Up to $max characters';
  }

  @override
  String feedbackCounter(int count, int max) {
    return '$count / $max';
  }

  @override
  String get feedbackClose => 'Close';

  @override
  String get feedbackAttachedBasics => 'App version, device and language.';

  @override
  String get feedbackScreenName => 'Screen name';

  @override
  String get feedbackScreenshot => 'Screenshot';

  @override
  String get feedbackScreenshotNote =>
      'Shows everything that was on screen, including items and names from your household. Cover anything we shouldn\'t see first.';

  @override
  String get feedbackScreenshotPreview => 'Screenshot preview';

  @override
  String get feedbackAddScreenshot => 'Add screenshot';

  @override
  String get feedbackShakeTitle => 'Report a problem with this screen?';

  @override
  String get feedbackShakeWithScreenshot => 'With screenshot';

  @override
  String get feedbackShakeWithout => 'Without screenshot';

  @override
  String get feedbackShakeOffHint => 'Turn shaking off: More › Settings';

  @override
  String get feedbackAnnotateHint =>
      'Mark what\'s wrong. Cover anything nobody should see.';

  @override
  String get feedbackToolPen => 'Pen';

  @override
  String get feedbackToolRectangle => 'Rectangle';

  @override
  String get feedbackToolText => 'Text';

  @override
  String get feedbackToolCover => 'Cover';

  @override
  String get feedbackAnnotateTools => 'Tool';

  @override
  String get feedbackAnnotateUndo => 'Undo';

  @override
  String get feedbackAnnotateTextHint => 'Type here';

  @override
  String get feedbackAnnotateDone => 'Done';

  @override
  String get settingsFeedback => 'Feedback';

  @override
  String get shakeToFeedback => 'Shake to send feedback';

  @override
  String get shakeToFeedbackHint =>
      'Shake your phone to report a problem with the screen.';

  @override
  String get feedbackHubRow => 'Feedback & ideas';

  @override
  String feedbackHubUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count updates',
      one: '1 update',
    );
    return '$_temp0';
  }

  @override
  String get feedbackWrite => 'Write to Snacklist Support';

  @override
  String get feedbackYourNotes => 'Your notes';

  @override
  String get feedbackNoNotes =>
      'No notes yet. What you write shows up here, with its status and the reply.';

  @override
  String get feedbackLoadFailed => 'Couldn\'t load.';

  @override
  String get feedbackStatusSent => 'Sent';

  @override
  String get feedbackStatusRead => 'Read';

  @override
  String get feedbackStatusPlanned => 'Planned';

  @override
  String feedbackStatusFixedIn(String version) {
    return 'Fixed in $version';
  }

  @override
  String get feedbackStatusFixed => 'Fixed';

  @override
  String get feedbackNewReply => 'New reply';

  @override
  String get feedbackNewStatus => 'New status';

  @override
  String get feedbackIdeas => 'Ideas being considered';

  @override
  String get feedbackIdeaConsidering => 'Being considered';

  @override
  String feedbackVote(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes',
      one: '1 vote',
    );
    return '$title: +1, $_temp0';
  }

  @override
  String get feedbackIdeasNote => 'Snacklist Support writes the ideas.';

  @override
  String get feedbackVoteFailed => 'Your vote didn\'t go through. Try again.';

  @override
  String get feedbackNoteTitle => 'Your note';

  @override
  String feedbackWhen(DateTime date, DateTime time) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);
    final intl.DateFormat timeDateFormat = intl.DateFormat.Hm(localeName);
    final String timeString = timeDateFormat.format(time);

    return '$dateString, $timeString';
  }

  @override
  String feedbackWhenRead(String when) {
    return '$when · read';
  }

  @override
  String feedbackReplyFrom(String when) {
    return 'Snacklist Support · $when';
  }

  @override
  String feedbackWhatsNew(String version) {
    return 'What\'s new in $version';
  }

  @override
  String get feedbackNoteMissing => 'This note can\'t be found.';

  @override
  String get onboardingCreateHint =>
      'Start a new list, then invite the people you shop with.';

  @override
  String get onboardingJoin => 'Join with an invite';

  @override
  String get onboardingJoinHint => 'You\'ve received a link or a code.';

  @override
  String get householdNameInvalid => 'Enter a name of 1 to 80 characters.';

  @override
  String get storesChoice => 'Stores';

  @override
  String get onboardingStoresHint =>
      'Pick the stores you shop at. Your list shows them in this order.';

  @override
  String get storeAddOwn => 'Add your own store';

  @override
  String get storeHardware => 'Hardware store';

  @override
  String get skipStores => 'Skip';

  @override
  String get skipStoresHint =>
      'Start without stores. You can add them later under List → Edit.';

  @override
  String get householdOffline =>
      'No internet connection. Try again once you\'re online.';

  @override
  String get householdArchiveDisabled =>
      'Archiving isn\'t available right now. Your household stays as it is.';

  @override
  String get tooManyAttempts => 'Too many attempts. Please try again later.';

  @override
  String get inviteCheck => 'Continue';

  @override
  String get invitePreview => 'Household invitation';

  @override
  String get invitePartnerBody =>
      'Share the link or the code with the people you shop with. Each invite works for one person and is valid for 7 days.';

  @override
  String get later => 'Later';

  @override
  String get toTheList => 'Go to the list';

  @override
  String get startTagline => 'Your shopping list. Live on every phone.';

  @override
  String get startWelcome =>
      'Welcome! In two minutes your shared list is ready, with everything you need right now.';

  @override
  String get startGo => 'Get started';

  @override
  String get startLogIn => 'Already have an account? Sign in';

  @override
  String get loginNew => 'New to Snacklist? Get started';

  @override
  String onboardingProgress(int step, int count) {
    return 'Step $step of $count';
  }

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingNext => 'Continue';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingExit => 'Leave setup';

  @override
  String get onboardingExitTitle => 'Leave setup?';

  @override
  String get onboardingExitBody =>
      'What you\'ve entered so far stays saved on this device.';

  @override
  String get onboardingExitLogIn => 'Sign in instead';

  @override
  String get onboardingExitDiscard => 'Discard progress';

  @override
  String get onboardingExitStay => 'Continue setup';

  @override
  String get whoTitle => 'Who do you shop with?';

  @override
  String get whoBody =>
      'Pick all that apply. We use this for the name, the invite and your first tips.';

  @override
  String get kindPartner => 'Partner';

  @override
  String get kindFamily => 'Family';

  @override
  String get kindFlat => 'Flatmates';

  @override
  String get kindClub => 'Club or team';

  @override
  String get kindSolo => 'Just me';

  @override
  String get kindOther => 'Other';

  @override
  String get whoOtherLabel => 'Who else?';

  @override
  String get whoOtherHint => 'e.g. neighbours';

  @override
  String whoSeveral(String first) {
    return 'We\'ll start with “$first” and keep the others for later.';
  }

  @override
  String get nameTitle => 'What should your household be called?';

  @override
  String get nameBody =>
      'Everyone you invite sees this name. You can change it later.';

  @override
  String get householdNameFamily => 'Our family';

  @override
  String get householdNameFlat => 'Our flat';

  @override
  String get householdNameClub => 'Our club';

  @override
  String get householdNameSolo => 'My list';

  @override
  String get storesStepTitle => 'Where do you shop?';

  @override
  String get needTitle => 'What do you need right now?';

  @override
  String get needBody => 'Tap what should go on the list, or type it below.';

  @override
  String get needStaples =>
      'Milk,Bread,Eggs,Butter,Cheese,Bananas,Apples,Tomatoes,Pasta,Coffee,Yogurt,Toilet paper';

  @override
  String get needFieldLabel => 'Anything else?';

  @override
  String get needFieldHint => 'e.g. 2 cucumbers';

  @override
  String get needAdd => 'Add';

  @override
  String needListTitle(int count) {
    return 'On your list ($count)';
  }

  @override
  String needRemove(String name) {
    return 'Remove $name';
  }

  @override
  String needNext(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Continue with $count items',
      one: 'Continue with 1 item',
      zero: 'Continue',
    );
    return '$_temp0';
  }

  @override
  String get accountStepTitle => 'Create your account';

  @override
  String get accountStepBody =>
      'Almost done. Create an account to save your list and invite someone.';

  @override
  String get setupBusy => 'Setting up your household…';

  @override
  String get inviteStepPartner => 'Invite your partner';

  @override
  String get inviteStepFamily => 'Invite your family';

  @override
  String get inviteStepFlat => 'Invite your flatmates';

  @override
  String get inviteStepClub => 'Invite members';

  @override
  String get inviteStepOther => 'Invite someone';

  @override
  String get inviteStepBody =>
      'Share the link with the person you shop with. Each invite works for one person and is valid for 7 days.';

  @override
  String get inviteStepBodyClub =>
      'Send each member their own link. Everyone sees the same list.';

  @override
  String inviteStepWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items are already waiting on the list.',
      one: '1 item is already waiting on the list.',
    );
    return '$_temp0';
  }

  @override
  String get inviteAnother => 'Another invite';

  @override
  String get inviteJoined => 'Joined';

  @override
  String inviteJoinedName(String name) {
    return '$name joined';
  }

  @override
  String inviteShareTextCodeOnly(String code) {
    return 'Join our Snacklist household. Code: $code';
  }

  @override
  String get share => 'Share';

  @override
  String get copyLink => 'Copy link';

  @override
  String get copyCode => 'Copy code';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get codeCopied => 'Code copied';

  @override
  String get invitesTitle => 'Invites';

  @override
  String get newInvite => 'New invite';

  @override
  String inviteValidUntil(DateTime date, DateTime time) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);
    final intl.DateFormat timeDateFormat = intl.DateFormat.Hm(localeName);
    final String timeString = timeDateFormat.format(time);

    return 'valid until $dateString, $timeString';
  }

  @override
  String get inviteRevoke => 'Revoke';

  @override
  String inviteRevokeLabel(String code) {
    return 'Revoke invite $code';
  }

  @override
  String get retry => 'Try again';

  @override
  String get lifetimeTitle => 'Snacklist Lifetime';

  @override
  String get lifetimeRowHint => 'Support Snacklist';

  @override
  String get lifetimeBody =>
      'One purchase for your whole household: Snacklist Lifetime supports the development of Snacklist.';

  @override
  String get lifetimeBuy => 'Continue to purchase';

  @override
  String get lifetimePriceInStore =>
      'The App Store or Google Play shows you the price before you buy.';

  @override
  String get lifetimeRestore => 'Restore purchase';

  @override
  String get lifetimePending => 'Waiting for approval';

  @override
  String get lifetimePendingBody =>
      'Snacklist Lifetime is unlocked as soon as the purchase is approved. This can take a while.';

  @override
  String get lifetimeUnlocking => 'Unlocking…';

  @override
  String get lifetimeUnlockDelayed =>
      'Your purchase went through; unlocking just takes longer than usual. It appears here by itself, so please don\'t buy again.';

  @override
  String get lifetimeBoughtTwice =>
      'Snacklist Lifetime was bought more than once. Whoever paid for one of the purchases can get it refunded.';

  @override
  String get lifetimeCanceled => 'Purchase canceled.';

  @override
  String get lifetimeComingSoon => 'Snacklist Lifetime is coming soon.';

  @override
  String get lifetimeStoreOffline =>
      'The store can\'t be reached right now. Check your connection.';

  @override
  String get lifetimeUsedElsewhere =>
      'This purchase already belongs to another Snacklist account or household and stays there. It unlocks nothing for you.';

  @override
  String get lifetimeNothingRestored => 'No earlier purchase found.';

  @override
  String lifetimeStoreFailed(String code) {
    return 'The purchase didn\'t go through ($code).';
  }

  @override
  String get lifetimeChecking =>
      'Checking whether your household has Snacklist Lifetime already…';

  @override
  String get lifetimeRefundLink =>
      'Bought it twice? How to get your money back';

  @override
  String get refundHelpTitle => 'Request a refund';

  @override
  String get refundHelpBody =>
      'Only Apple refunds App Store purchases. For Google Play, ask Google within 48 hours of buying; after that, email us at support@snacklist.app and we\'ll look at your request. Your statutory rights are not affected.';

  @override
  String get refundHelpApple =>
      'iPhone: open reportaproblem.apple.com, sign in with your Apple Account, choose “Request a refund”, then Snacklist Lifetime.';

  @override
  String get refundHelpGoogle =>
      'Android, within 48 hours: open Google Play, tap your profile picture, then “Payments & subscriptions”, “Budget & order history”, choose Snacklist Lifetime and “Report a problem”. After that, email us with the order number (it starts with “GPA.”) or your Google account\'s email address.';

  @override
  String get refundHelpReason =>
      'As the reason you can write, for example: “I already had Snacklist Premium.”';

  @override
  String get refundHelpAppleLink => 'Ask Apple';

  @override
  String get refundHelpGoogleLink => 'Ask Google';

  @override
  String get refundHelpFaqLink => 'More in the FAQ';

  @override
  String get joinTargetUnlocked =>
      'This household has Snacklist Lifetime. You don\'t need to buy anything.';

  @override
  String get joinRefundLink =>
      'Bought Snacklist Lifetime recently? How to request a refund';

  @override
  String get joinLifetimeRefundLink => 'Ask Apple or Google for a refund';

  @override
  String get archivedTitle => 'Archived households';

  @override
  String get archivedEmpty => 'You haven\'t archived a household.';

  @override
  String get archivedUnlocked => 'With Snacklist Lifetime';

  @override
  String archivedDeletesOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Will be deleted on $dateString';
  }

  @override
  String get archivedRestore => 'Restore';

  @override
  String archivedRestoreTitle(String household) {
    return 'Restore “$household”?';
  }

  @override
  String archivedRestoreBody(String household) {
    return 'You are a member of “$household” again. Your other households stay.';
  }

  @override
  String get premiumTitle => 'Snacklist Premium';

  @override
  String get premiumHeroTitle => 'One buys. Everyone has it.';

  @override
  String get premiumHeroBody =>
      'Snacklist Premium covers your whole household, including everyone who joins later.';

  @override
  String get premiumBenefitAi =>
      'Connect AI assistants that support MCP to your list';

  @override
  String get premiumBenefitApi => 'Your own automations with the Snacklist API';

  @override
  String premiumStatusRenews(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Snacklist Premium active (yearly, renews on $dateString)';
  }

  @override
  String premiumStatusEnds(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Snacklist Premium active (yearly, ends on $dateString)';
  }

  @override
  String get premiumStatusLifetime => 'Snacklist Premium Lifetime';

  @override
  String premiumWithVat(String period) {
    return '$period, incl. VAT';
  }

  @override
  String get premiumBetaPrivacyLink => 'More in the privacy policy';

  @override
  String get premiumBetaBody =>
      'You pay nothing, and nothing renews automatically. We\'ll let you know at least 4 weeks before the free unlock ends.';

  @override
  String get premiumStatusFree =>
      'Unlocked free of charge (testing and app review)';

  @override
  String get premiumStatusBeta =>
      'Free in the beta, until Snacklist Premium launches';

  @override
  String get premiumChecking =>
      'Checking whether your household already has Snacklist Premium…';

  @override
  String get premiumYearlyTitle => 'Yearly';

  @override
  String get premiumPerYear => 'per year';

  @override
  String get premiumLifetimeTitle => 'Lifetime';

  @override
  String get premiumOneTime => 'one-time';

  @override
  String get premiumLifetimeValue => 'Pay once, no subscription.';

  @override
  String get premiumYearlyTerms =>
      'Snacklist Premium yearly, 1 year, at the store\'s price shown. The plan renews automatically for another year unless you cancel it at least 24 hours before the end of the period. Your Apple or Google account is charged when you confirm the purchase and at every renewal. You can manage and cancel the plan in the App Store\'s or Google Play\'s subscription settings. If the plan ends, we delete nothing; the history then shows the last 4 weeks again.';

  @override
  String get premiumOwner =>
      'Premium then belongs to you and applies in every household you\'re a member of, later ones included. The other members don\'t get it through your purchase.';

  @override
  String get premiumBuyYearly => 'Subscribe yearly';

  @override
  String get premiumBuyLifetime => 'Buy Lifetime';

  @override
  String get premiumUnavailable =>
      'Snacklist Premium is not available right now.';

  @override
  String get premiumTermsLink => 'Terms of Use (EULA)';

  @override
  String get premiumPrivacyLink => 'Privacy policy';

  @override
  String get premiumUsedElsewhereYearly =>
      'An Apple or Google account pays for one Snacklist Premium yearly plan at most. If yours already pays one for another Snacklist account, Premium applies only there.';

  @override
  String get premiumTwoYearly =>
      'Your Premium currently comes from two yearly plans. Each can only be cancelled with the Apple or Google account it was taken out with.';

  @override
  String get premiumWeb =>
      'You can buy Snacklist Premium in the iPhone or Android app. It then applies here too, in each of your households.';

  @override
  String get premiumRefundYearly =>
      'The same goes for the yearly plan. Cancelling only stops the renewal; the current year is not refunded automatically.';

  @override
  String get premiumManage => 'Manage or cancel subscription';

  @override
  String get premiumManageWeb =>
      'You manage your yearly plan in the App Store or on Google Play.';

  @override
  String get premiumManageApple => 'App Store';

  @override
  String get premiumManageGoogle => 'Google Play';

  @override
  String premiumBillingIssue(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Apple or Google couldn\'t charge your yearly plan. Premium keeps running until $dateString. Check your payment method in the store.';
  }

  @override
  String get premiumLifetimeWhileYearly =>
      'A yearly plan is already tied to this household. It keeps running and being billed after your one-time purchase until it is cancelled; the rest of the plan year isn\'t refunded automatically. Only the person who took out the plan can cancel it, in [Manage subscriptions]. Snacklist can\'t cancel it.';

  @override
  String get premiumLifetimeWhileYearlySubscriber =>
      'You already have a yearly plan. It keeps running and being billed after the one-time purchase until you cancel it; the rest of the plan year isn\'t refunded automatically. You can cancel it in [Manage subscription]. Snacklist can\'t cancel it.';

  @override
  String get premiumBuyAnyway => 'Buy anyway';

  @override
  String get premiumBillingContinues =>
      'Your Snacklist Premium yearly plan keeps running and is billed to your Apple or Google account until you cancel it. Leaving, deleting or archiving a household doesn\'t cancel it.';

  @override
  String get premiumBillingContinuesAccount =>
      'Your Snacklist Premium yearly plan keeps running and is billed to your Apple or Google account until you cancel it. Deleting your account ends your Premium, but not the plan. Cancel it first.';

  @override
  String get premiumBillingContinuesOther =>
      'A yearly plan is tied to this household. It keeps running until it is cancelled.';

  @override
  String get premiumManageSubscription => 'Manage subscription';

  @override
  String get premiumContinueAnyway => 'Continue anyway';

  @override
  String get integrationPremiumTitle => 'Part of Snacklist Premium';

  @override
  String get integrationPremiumBody =>
      'AI assistants are part of Snacklist Premium. Your connections stay saved and work again as soon as your household has Snacklist Premium.';

  @override
  String get integrationPremiumAi => 'AI assistants that support MCP';

  @override
  String get integrationPremiumLater =>
      'Later: Google Assistant and Apple Watch';

  @override
  String get integrationPremiumBuy => 'Unlock Snacklist Premium';

  @override
  String get integrationPremiumSoon => 'Coming soon.';

  @override
  String get integrationPaused => 'Paused: needs Snacklist Premium';

  @override
  String get apiHeader => 'API';

  @override
  String get apiBody =>
      'For your own scripts and automations: read and change your list over HTTP with an API key.';

  @override
  String get apiDocs => 'API documentation';

  @override
  String get noApiKeys => 'No active API key.';

  @override
  String get createApiKey => 'Create API key';

  @override
  String get apiKeyNameHint => 'e.g. Home Assistant';

  @override
  String get apiScopeRead => 'Read only';

  @override
  String get apiScopeReadBody =>
      'Reads the list, categories and stores. Changes nothing.';

  @override
  String get apiScopeReadWrite => 'Read and write';

  @override
  String get apiScopeReadWriteBody => 'Can also add, tick off and move items.';

  @override
  String get apiKeyCreated => 'API key created';

  @override
  String get apiKeyShownOnce => 'Copy the key now. It won\'t be shown again.';

  @override
  String get revokeApiKeyTitle => 'Revoke API key?';

  @override
  String get revokeApiKeyBody => 'Scripts using it lose access right away.';

  @override
  String get tooManyApiKeys => 'At most 10 active API keys. Revoke one first.';

  @override
  String get apiKeySessionRequired =>
      'You can only create API keys here in the app while you\'re signed in.';

  @override
  String get apiDisabled => 'The API isn\'t available yet.';

  @override
  String get apiPremium =>
      'The Snacklist API is part of Snacklist Premium. Your keys stay and work again as soon as your household has Premium.';

  @override
  String get accessTokensHint =>
      'Use a token to build your own automations that manage your list, like a script or an assistant on the MCP server.';

  @override
  String get accessTokensHintWithApi =>
      'Use a token to build your own automations on the MCP server that manage your list. For programs without MCP, use the API below.';

  @override
  String accessKeysHousehold(String household) {
    return 'A new token works in “$household”, the household open now.';
  }

  @override
  String accessKeysHouseholdWithApi(String household) {
    return 'New tokens and API keys work in “$household”, the household open now.';
  }

  @override
  String lastActiveOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Last active $dateString';
  }

  @override
  String get notActiveYet => 'Not active yet';

  @override
  String appDevice(String device) {
    return 'Approved on $device';
  }

  @override
  String appCanTitle(String name) {
    return 'What $name can do';
  }

  @override
  String get appCanEmail => 'See your email address.';

  @override
  String get appCanProfile => 'See your name.';

  @override
  String get appCanPhone => 'See your phone number.';

  @override
  String get appCanStay => 'Stay connected until you disconnect it.';

  @override
  String get copyEmail => 'Copy email address';

  @override
  String get tipEditTitle => 'Edit an item';

  @override
  String get tipEditBody =>
      'Press and hold an item to change its quantity, brand, store and more.';

  @override
  String get tipAmountsTitle => 'Type the amount too';

  @override
  String get tipAmountsBody =>
      'Write “2 cucumbers” or “milk 2 l” and Snacklist picks up the amount.';

  @override
  String get tipDismiss => 'Hide tip';

  @override
  String get tooManyHouseholds =>
      'You are in 20 households already. Leave one before you create or join another.';

  @override
  String get householdSwitch => 'Switch household';

  @override
  String get householdsTitle => 'Your households';

  @override
  String householdMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String householdOpenItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open',
      one: '1 open',
      zero: 'nothing open',
    );
    return '$_temp0';
  }

  @override
  String get householdCurrent => 'Shown';

  @override
  String get newHousehold => 'New household';

  @override
  String get joinWithCode => 'Join with a code';

  @override
  String voiceDefaultRow(String household) {
    return 'Siri, Alexa & AI use: $household';
  }

  @override
  String get voiceDefaultTitle => 'Default for Siri, Alexa & AI';

  @override
  String get voiceDefaultBody =>
      'What you tell Siri, Alexa or an AI assistant goes into this household.';

  @override
  String get voiceDefaultOn =>
      'Siri, Alexa and AI assistants use this household.';

  @override
  String voiceDefaultOff(String household) {
    return 'Siri, Alexa and AI assistants now use “$household”.';
  }

  @override
  String get householdPageTitle => 'Household';

  @override
  String get householdRename => 'Rename';

  @override
  String get householdRenameTitle => 'Rename household';

  @override
  String get householdMembersTitle => 'Members';

  @override
  String householdMemberYou(String name) {
    return '$name (you)';
  }

  @override
  String get householdMemberUnnamed => 'Unnamed';

  @override
  String get householdMembersFailed => 'The members could not be loaded.';

  @override
  String get leaveHousehold => 'Leave household';

  @override
  String leaveTitle(String household) {
    return 'Leave “$household”?';
  }

  @override
  String get leaveShared =>
      'The other members keep the list. You can only come back with a new invite.';

  @override
  String get leaveLast =>
      'You are the last member. The household is deleted with its list, history, categories and stores.';

  @override
  String leaveLifetimeEnds(String household) {
    return '“$household” has Snacklist Lifetime. You are the last member: if you leave, the household is deleted. Snacklist Lifetime ends with it, because a purchase belongs to its household.';
  }

  @override
  String leaveArchiveOffer(String household) {
    return '“$household” has Snacklist Lifetime. You are the last member. Archive the household instead of deleting it: the list and Snacklist Lifetime are kept, and you can bring it back under “More” later. If you don\'t bring it back within 24 months, it is deleted.';
  }

  @override
  String get leaveArchive => 'Archive and leave';

  @override
  String get leaveDelete => 'Delete and leave';

  @override
  String consentDefaultHousehold(String name) {
    return 'Works in your default household “$name”, and in any other of your households you name.';
  }

  @override
  String get voiceDefaultMake => 'Make default';

  @override
  String get defaultListTitle => 'List for Siri, Alexa & AI';

  @override
  String defaultListRow(String list) {
    return 'List: $list';
  }

  @override
  String get inviteSheetTitle => 'Invite people';

  @override
  String inviteSheetOpen(String name) {
    return 'Invite people to $name';
  }

  @override
  String get invitePremiumShared => 'Premium covers everyone in the household.';

  @override
  String get invitePersonTitle => 'For one person';

  @override
  String get invitePersonBody => 'A link for one person, valid for 7 days.';

  @override
  String get inviteJoinPageHint =>
      'Anyone with the link or code sees your name, the household\'s name and a few numbers about it before joining. Only share them with people you want to invite.';

  @override
  String get inviteGroupTitle => 'Group link';

  @override
  String get inviteGroupBody =>
      'For up to 50 people, valid for 30 days. Show the QR code or share the link.';

  @override
  String get inviteGroupCreate => 'Create group link';

  @override
  String inviteGroupUses(int count, int max) {
    return '$count of $max joined';
  }

  @override
  String get inviteGroupFull =>
      'This link is full: no one else can join with it.';

  @override
  String get inviteGroupRevoked =>
      'Link revoked: no one can join with it any more.';

  @override
  String get inviteGroupRevoke => 'Revoke link';

  @override
  String get inviteGroupRenew => 'Create new link';

  @override
  String get inviteGroupRevokeTitle => 'Revoke the group link?';

  @override
  String get inviteGroupRevokeBody =>
      'No one can join with the link any more. Everyone who joined stays in the household.';

  @override
  String get inviteGroupRevokeConfirm => 'Revoke';

  @override
  String get inviteGroupRenewTitle => 'Create a new link?';

  @override
  String get inviteGroupRenewBody =>
      'The current link stops working. Everyone who joined stays in the household.';

  @override
  String get inviteGroupQr => 'QR code of the group link';

  @override
  String get inviteJoinsTitle => 'Who joined';

  @override
  String get inviteJoinsEmpty => 'No one yet.';

  @override
  String inviteJoinedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'on $dateString';
  }

  @override
  String inviteShareKind(String kind, String name, String link, String code) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'partner':
          'I\'ve set up our shopping list in Snacklist. Join me: $link · Code: $code',
      'family':
          'Our family shopping list “$name” is on Snacklist now. Join us: $link · Code: $code',
      'flat':
          'Our flat\'s shopping list “$name” is on Snacklist now. Join us: $link · Code: $code',
      'club':
          'We\'re planning the shopping for “$name” in Snacklist. Join in: $link · Code: $code',
      'solo':
          'I\'m sharing my shopping list “$name” in Snacklist with you: $link · Code: $code',
      'other': 'Join our Snacklist household: $link · Code: $code',
    });
    return '$_temp0';
  }

  @override
  String get householdRoleOwner => 'Owner';

  @override
  String get householdRoleAdmin => 'Admin';

  @override
  String memberActions(String name) {
    return 'Options for $name';
  }

  @override
  String get memberMakeAdmin => 'Make admin';

  @override
  String get memberRemoveAdmin => 'Remove admin rights';

  @override
  String get memberRemove => 'Remove from household';

  @override
  String memberRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String memberRemoveBody(String name, String household) {
    return '$name will no longer see the list of “$household” and can\'t come back through earlier invites or the current group link. For the next 30 days, only a new invite or a new group link from an admin brings them back.';
  }

  @override
  String get memberRemoveConfirm => 'Remove';

  @override
  String householdRemovedNotice(String name) {
    return 'You were removed from the household “$name”. For 30 days, old invites won\'t let you back in. In that time you can only rejoin through a new invite from the owner or an admin.';
  }

  @override
  String householdGoneNotice(String name) {
    return 'You\'re no longer a member of “$name”.';
  }

  @override
  String get householdNotAdmin => 'Only admins can do that.';

  @override
  String get householdCannotRemove => 'You can\'t remove this person.';

  @override
  String get invitePaste => 'Paste invite';

  @override
  String get invitePasteNothing =>
      'There\'s no invite link or code on the clipboard.';

  @override
  String get invitePasteWaiting => 'Invite saved. Sign in to join.';

  @override
  String get householdNotOwner =>
      'Only the household\'s owner can make people admins.';

  @override
  String get listsTitle => 'Lists';

  @override
  String get listMain => 'Shopping list';

  @override
  String get listNew => 'New list';

  @override
  String get listNameLabel => 'List name';

  @override
  String listAdded(String name) {
    return 'List “$name” added';
  }

  @override
  String get listRenameTitle => 'Rename list';

  @override
  String listActions(String name) {
    return 'Actions for “$name”';
  }

  @override
  String get listMoveUp => 'Move up';

  @override
  String get listMoveDown => 'Move down';

  @override
  String listDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String listDeleteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The $count open items on it will be deleted too.',
      one: 'The 1 open item on it will be deleted too.',
      zero: 'Nothing is open on this list.',
    );
    return '$_temp0';
  }

  @override
  String get listsNeedConnection =>
      'Lists can only be added, renamed, sorted or deleted with a connection.';

  @override
  String onListAlready(String name, String list) {
    return '“$name” is already on “$list”.';
  }

  @override
  String get editList => 'List';

  @override
  String get claimMine => 'I\'ll bring it';

  @override
  String get claimAmount => 'How much?';

  @override
  String get claimAmountHint => 'e.g. 2';

  @override
  String claimBy(String name) {
    return '$name\'s bringing it';
  }

  @override
  String claimByAmount(String name, String amount) {
    return '$name\'s bringing $amount';
  }

  @override
  String get claimYou => 'You\'re bringing it';

  @override
  String claimYouAmount(String amount) {
    return 'You\'re bringing $amount';
  }

  @override
  String get claimSomeone => 'Someone';

  @override
  String joinRequestSent(String name) {
    return 'Request sent. An admin of “$name” needs to approve it.';
  }

  @override
  String get joinDeclinedRecently =>
      'Your request to join this household was declined recently. You can ask again after 24 hours.';

  @override
  String get joinRequestWithdraw => 'Withdraw request';

  @override
  String get joinRequestToList => 'Go to the list';

  @override
  String get joinRequestCreateOwn => 'Create your own household';

  @override
  String joinApprovedNotice(String name) {
    return 'You\'re now in “$name”.';
  }

  @override
  String joinDeclinedNotice(String name) {
    return 'Your request to join “$name” wasn\'t accepted.';
  }

  @override
  String get joinRequestPending => 'Request pending';

  @override
  String joinRequestWithdrawFor(String name) {
    return 'Withdraw your request for “$name”?';
  }

  @override
  String get joinApprovalToggle => 'Confirm new members';

  @override
  String get joinApprovalHint => 'New people wait until an admin lets them in.';

  @override
  String get joinRequestsTitle => 'Join requests';

  @override
  String joinRequestsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open requests',
      one: '1 open request',
    );
    return '$_temp0';
  }

  @override
  String get joinRequestsNone => 'No open requests.';

  @override
  String get joinRequestsFailed => 'Couldn\'t load the requests.';

  @override
  String get joinRequestApprove => 'Approve';

  @override
  String get joinRequestInviteFull =>
      'The invite for this request is full. Send a new link. Once it\'s opened, you can let them in.';

  @override
  String get joinRequestDecline => 'Decline';

  @override
  String get hintInviteTitle => 'Shop together';

  @override
  String get hintInviteBody => 'Invite someone to use the list together.';

  @override
  String get hintInviteAction => 'Invite';

  @override
  String get hintStoreOrderTitle => 'Sorted like your store';

  @override
  String get hintStoreOrderBody =>
      'Here you can sort the categories in the order you walk through the store.';

  @override
  String get hintAddStoreTitle => 'Another store?';

  @override
  String get hintAddStoreBody => 'Here you can add more stores you shop at.';

  @override
  String get hintDictationTitle => 'Just say it';

  @override
  String get hintDictationBody =>
      'Tap the mic and say: “milk, two cucumbers and toilet paper”.';

  @override
  String get hintAssistantTitle => 'Even better with AI & automation';

  @override
  String get hintAssistantBody =>
      'Let your AI assistant manage your list, or use the API to build automations.';

  @override
  String get hintAssistantAction => 'Manage access';

  @override
  String get hintSiriTitle => 'Add with Siri';

  @override
  String get hintSiriBody =>
      'Say “Hey Siri, add to Snacklist” when your hands are full.';

  @override
  String get hintWidgetTitle => 'Your list on the home screen';

  @override
  String get hintWidgetBody =>
      'Add the Snacklist widget by pressing and holding your phone\'s home screen.';

  @override
  String get hintOwnHouseholdTitle => 'A list of your own';

  @override
  String get hintOwnHouseholdBody =>
      'Someone else created this household. You can create your own too, for example just for you.';

  @override
  String get hintSecondHouseholdTitle => 'Another list?';

  @override
  String get hintSecondHouseholdBody =>
      'For your club or flat: create a second household.';

  @override
  String get hintAddHouseholdAction => 'Create a household';

  @override
  String get hintDismissedNotice => 'All tips under More → Tips.';

  @override
  String get hintsTitle => 'Tips';

  @override
  String get checklistTitle => 'First steps';

  @override
  String get checklistDismiss => 'Hide first steps';

  @override
  String checklistProgress(int done, int total) {
    return '$done of $total';
  }

  @override
  String get checklistStarted => 'List started';

  @override
  String get checklistJoined => 'Joined the household';

  @override
  String checklistInvite(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'partner': 'Invite your partner',
      'family': 'Invite your family',
      'flat': 'Invite your flatmates',
      'club': 'Invite members',
      'other': 'Invite someone',
    });
    return '$_temp0';
  }

  @override
  String checklistInviteBody(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'club': 'Everyone sees the same list and can add to it.',
      'other': 'They see your items right away and can add their own.',
    });
    return '$_temp0';
  }

  @override
  String get checklistShop => 'Go shopping once';

  @override
  String get checklistAssistant => 'Connect an AI assistant';

  @override
  String get checklistAssistantBody =>
      'Under More → Access. It can add things to your list.';

  @override
  String get checklistOpen => 'Open';

  @override
  String checklistDone(String step) {
    return '$step, done';
  }

  @override
  String get tabHistory => 'History';

  @override
  String get historyShowByStore => 'Show by store';

  @override
  String get historyShowByDate => 'Show by date';

  @override
  String get tripAdd => 'Log a trip';

  @override
  String get tripAddShort => 'Log';

  @override
  String get tripEdit => 'Edit trip';

  @override
  String tripAddAt(String store) {
    return 'Log a trip to $store';
  }

  @override
  String get historyEmptyTitle => 'No trips yet';

  @override
  String get historyEmptyBody =>
      'After shopping, log what you bought. Later you can look up what you got where, and when.';

  @override
  String get historyLoadFailed => 'The history couldn\'t be loaded.';

  @override
  String get historyThisWeek => 'This week';

  @override
  String get historyLastWeek => 'Last week';

  @override
  String historyDayFilter(DateTime day) {
    final intl.DateFormat dayDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dayString = dayDateFormat.format(day);

    return 'Trips on $dayString';
  }

  @override
  String get historyDayClear => 'Show all trips';

  @override
  String get historyDayEmpty => 'No trips on this day';

  @override
  String historyDayLabel(String date, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trips',
      one: '1 trip',
    );
    return '$date, $_temp0';
  }

  @override
  String get historyStoreEmpty => 'No trips yet';

  @override
  String get historyLockedTitle => 'See older trips with Snacklist Premium';

  @override
  String historyLockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count older trips',
      one: '1 older trip',
    );
    return '$_temp0';
  }

  @override
  String historyDayLocked(String date) {
    return '$date, older trips with Snacklist Premium';
  }

  @override
  String get tripStoreMissing => 'Pick a store.';

  @override
  String get tripStoreGone => 'This store was deleted.';

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get dayToday => 'Today';

  @override
  String get dayYesterday => 'Yesterday';

  @override
  String get tripStore => 'Store';

  @override
  String get tripDay => 'When';

  @override
  String get tripOtherDay => 'Other day';

  @override
  String get tripItems => 'Bought';

  @override
  String get tripItemName => 'Item';

  @override
  String get tripAddItem => 'Add item';

  @override
  String tripRemoveItem(String name) {
    return 'Remove $name';
  }

  @override
  String get tripDelete => 'Delete trip';

  @override
  String get tripDeleteTitle => 'Delete this trip?';

  @override
  String get tripDeleteBody =>
      'The trip disappears from everyone\'s history in the household.';

  @override
  String get tripDeleteFailed =>
      'The trip couldn\'t be deleted. Please try again.';

  @override
  String get tripSaveFailed => 'The trip couldn\'t be saved. Please try again.';

  @override
  String tripItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String tripSummaryMore(String names, int count) {
    return '$names and $count more';
  }

  @override
  String get priceAdd => 'Price';

  @override
  String priceChipEmpty(String name) {
    return 'Price for $name';
  }

  @override
  String priceChipSet(String name, String amount) {
    return 'Price for $name: $amount, change';
  }

  @override
  String get priceField => 'Price';

  @override
  String get weightField => 'Weight in kg';

  @override
  String get pricePerPiece => 'per item';

  @override
  String get pricePerKg => 'per kg';

  @override
  String get pricePerLitre => 'per l';

  @override
  String get priceUnitLitre => 'l';

  @override
  String get volumeField => 'Amount in l';

  @override
  String get volumeErrorEmpty => 'Enter the amount.';

  @override
  String get volumeErrorZero => 'The amount must be over 0 ml.';

  @override
  String get volumeErrorTooLarge => 'At most 50 l.';

  @override
  String get priceLine => 'Total';

  @override
  String get priceBasisLabel => 'Price is';

  @override
  String get priceUnitPiece => 'Item';

  @override
  String get priceUnitKg => 'kg';

  @override
  String get priceUnitLabel => 'Unit';

  @override
  String get priceCountLess => 'One less';

  @override
  String get priceCountMore => 'One more';

  @override
  String priceCount(int count) {
    return 'Quantity $count';
  }

  @override
  String priceTogether(String amount) {
    return 'Altogether $amount';
  }

  @override
  String priceUnitIs(String amount, String per) {
    return 'That is $amount $per';
  }

  @override
  String priceTotalAfter(String amount) {
    return 'New total $amount';
  }

  @override
  String priceDearer(String amount) {
    return '$amount more than last time';
  }

  @override
  String priceCheaper(String amount) {
    return '$amount less than last time';
  }

  @override
  String get priceSame => 'Same as last time';

  @override
  String get priceErrorEmpty => 'Enter a price.';

  @override
  String priceErrorTooLarge(String min, String max) {
    return 'Between $min and $max per item.';
  }

  @override
  String get weightErrorEmpty => 'Enter the weight.';

  @override
  String get weightErrorZero => 'The weight must be over 0 g.';

  @override
  String get weightErrorTooLarge => 'At most 50 kg.';

  @override
  String get priceRemove => 'Remove price';

  @override
  String get tripTotal => 'Shopping total';

  @override
  String tripCounts(int priced, int open) {
    return '$priced priced · $open open';
  }

  @override
  String tripTotalLabel(String amount, int priced, int open) {
    return 'Shopping total $amount, $priced priced, $open open';
  }

  @override
  String storeSubtotal(String store, String amount) {
    return '$store total $amount';
  }

  @override
  String get currencyTitle => 'Currency';

  @override
  String get currencyHint =>
      'For prices and the shopping total, for everyone in the household';

  @override
  String get currencyPick => 'Choose currency';

  @override
  String get listSwitch => 'Switch list or household';

  @override
  String get switcherHouseholds => 'Households';

  @override
  String switcherBack(String page) {
    return 'Back: $page';
  }

  @override
  String get switcherInvite => 'Invite';

  @override
  String switcherOpenInvites(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open invites',
      one: '1 open invite',
    );
    return '$_temp0';
  }

  @override
  String get switcherOpenInvitesTitle => 'Open invites';

  @override
  String get shopAskTitle => 'Are you shopping right now?';

  @override
  String get shopAskBody =>
      'Snacklist times your trip, and at the end you see what was planned and what you added.';

  @override
  String get shopAskYes => 'Yes, start a trip';

  @override
  String get shopAskNo => 'No, just tick it off';

  @override
  String get shopAskMistake => 'Ticked off by mistake?';

  @override
  String get shopAskTakeBack => 'Untick';

  @override
  String get shopRunning => 'Trip in progress';

  @override
  String get shopPaused => 'Paused';

  @override
  String shopAutoPaused(String time) {
    return 'Paused · nothing ticked since $time';
  }

  @override
  String get shopPause => 'Pause';

  @override
  String get shopResume => 'Resume';

  @override
  String get shopEnd => 'End';

  @override
  String shopEndAt(String time) {
    return 'End at $time';
  }

  @override
  String shopClockLabel(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'for $minutes minutes',
      one: 'for 1 minute',
      zero: 'for less than a minute',
    );
    return '$_temp0';
  }

  @override
  String get shopAutoEndedTitle => 'Trip ended automatically';

  @override
  String shopAutoEndedBody(String time) {
    return 'Nothing was ticked off for 4 hours, so the trip ended at your last tick, at $time.';
  }

  @override
  String get shopKeepGoing => 'Keep going';

  @override
  String get shopShowSummary => 'See summary';

  @override
  String get shopSummaryTitle => 'Planned and bought';

  @override
  String shopSummaryWhen(String day, String from, String to) {
    return '$day, $from to $to';
  }

  @override
  String shopMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get shopUnderAMinute => 'under 1 min';

  @override
  String shopHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String shopShoppedFor(String duration) {
    return 'Shopped for $duration';
  }

  @override
  String shopLede(int bought, int planned) {
    return 'Bought $bought of $planned from the list';
  }

  @override
  String shopLedeExtra(int count) {
    return '$count extra';
  }

  @override
  String shopLedeNoList(int count) {
    return 'No list · $count bought';
  }

  @override
  String shopAutoEndHint(String time) {
    return 'Ended at the last tick at $time, automatically.';
  }

  @override
  String get shopPlannedSection => 'On the list at the start';

  @override
  String get shopExtraSection => 'Added since the start';

  @override
  String get shopPlannedEmpty => 'The list was empty.';

  @override
  String get shopExtraEmpty => 'Nothing. Everything was on the list.';

  @override
  String get shopNotBought => 'not bought';

  @override
  String get shopBought => 'bought';

  @override
  String shopBy(String name) {
    return 'added by $name';
  }

  @override
  String get shopMarkPlanned => 'Was planned';

  @override
  String get shopMarkPlannedHint =>
      '“Was planned” counts an item as on the list when it was agreed but not written down.';

  @override
  String shopPlannedPrice(String amount) {
    return 'planned $amount';
  }

  @override
  String shopMore(String amount) {
    return '$amount more';
  }

  @override
  String shopLess(String amount) {
    return '$amount less';
  }

  @override
  String get shopAsPlanned => 'as planned';

  @override
  String get shopPaid => 'Paid';

  @override
  String get shopPaidTotal => 'Paid in total';

  @override
  String shopCompared(String amount, String difference) {
    return 'Planned $amount · $difference';
  }

  @override
  String shopComparedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'for $count items',
      one: 'for 1 item',
    );
    return '$_temp0';
  }

  @override
  String shopWithoutPrice(int count) {
    return '$count without a price';
  }

  @override
  String shopWithoutPlan(int count) {
    return '$count without a planned price';
  }

  @override
  String get shopTotalsNote =>
      'Paid counts only items with a price. The difference compares only items with a planned and a paid price.';

  @override
  String get shopKeepShopping => 'Keep shopping';

  @override
  String get shopNotSaved => 'The trip isn\'t saved yet.';

  @override
  String shopTicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items ticked off',
      one: '1 item ticked off',
    );
    return '$_temp0';
  }

  @override
  String get shopLockedTitle => 'What was planned, what did you add?';

  @override
  String get shopLockedBody =>
      'After every trip, Snacklist Premium shows what was on the list and what got added along the way, also by others in the household.';

  @override
  String get shopLockedButton => 'See Snacklist Premium';

  @override
  String get shopLoadFailed => 'The summary couldn\'t be loaded.';

  @override
  String get shopStartByHand => 'Start a trip';

  @override
  String get shopStartByHandHint =>
      'The clock runs from now; the list as it is now counts as planned.';

  @override
  String get shopByOther => 'added by someone else';

  @override
  String get shopMarkFailed => '“Was planned” couldn\'t be saved. Try again.';

  @override
  String get subtotalsTotal => 'Total';

  @override
  String subtotalsUnpriced(int count) {
    return '$count without price';
  }

  @override
  String subtotalsPriced(int count) {
    return '$count with price';
  }

  @override
  String get subtotalsAllBought => 'all bought';

  @override
  String subtotalsBought(String amount) {
    return '$amount bought';
  }

  @override
  String subtotalsOpen(String amount) {
    return '$amount open';
  }

  @override
  String get subtotalsJump => 'Go to the store in the list';

  @override
  String moneyAtLeast(String amount) {
    return 'at least $amount';
  }

  @override
  String moneyAtLeastSpoken(String amount) {
    return 'at least $amount';
  }

  @override
  String moneyEstimate(String amount) {
    return '≈ $amount';
  }

  @override
  String moneyEstimateSpoken(String amount) {
    return 'about $amount';
  }

  @override
  String get voiceDefaultLabel => 'Siri, Alexa & AI add to:';

  @override
  String voiceDefaultHouseholdName(String household) {
    return 'Household: $household';
  }

  @override
  String get voiceDefaultBack => 'Siri, Alexa & AI';

  @override
  String voiceDefaultListBody(String household) {
    return 'What you say without naming a list goes onto this list in “$household”.';
  }

  @override
  String get jh2StartHaveAccount => 'Already have an account';

  @override
  String get jh2JoinExisting => 'Join existing household';

  @override
  String get jh2JoinCodeHeading => 'Enter your invite code';

  @override
  String get jh2JoinCodeHelp =>
      'The 8 characters from your invite. Once they\'re all in, you\'ll see the household.';

  @override
  String get jh2JoinCodeJoin => 'Join';

  @override
  String jh2InvitedBy(String inviter, String household) {
    return '$inviter invites you to “$household”';
  }

  @override
  String jh2InvitedTo(String household) {
    return 'You’re invited to “$household”';
  }

  @override
  String jh2InvitedByInviter(String inviter) {
    return '$inviter invites you to a household';
  }

  @override
  String get jh2InvitedToHousehold => 'You’re invited to a household';

  @override
  String jh2PreviewMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String jh2PreviewOpenItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open items',
      one: '1 open item',
    );
    return '$_temp0';
  }

  @override
  String get jh2PreviewPremium => 'Premium covers everyone in the household';

  @override
  String get jh2CodeUnavailable =>
      'This invite no longer works. Ask for a new invite.';

  @override
  String get jh2CodeRateLimited =>
      'Too many tries right now. Try again in a while.';

  @override
  String get jh2InviteSheetBody => 'Do you already have a Snacklist account?';

  @override
  String get jh2InviteSheetCreate => 'Create account';

  @override
  String jh2JoinRequestWaiting(String name) {
    return 'Your request is with “$name”. An admin sees your name there and lets you in. Your list opens by itself as soon as they do.';
  }

  @override
  String get jh2JoinRequestOwnList => 'Start my own list instead';

  @override
  String get inviteQrPerson => 'QR code for this invite';

  @override
  String get openAppText => 'Snacklist works better in the app.';

  @override
  String get openAppAction => 'Open';

  @override
  String get justAdded => 'Just added';

  @override
  String get suggestionsLoading => 'Loading suggestions';

  @override
  String get suggestionStale => 'older suggestion, still loading';

  @override
  String get yourNameTitle => 'What should we call you?';

  @override
  String get yourNameBody =>
      'Everyone in your household sees this name. The people you invite see your first name. You can change it later.';

  @override
  String get yourNameLabel => 'Your name';

  @override
  String get yourNameHint => 'e.g. Lea';

  @override
  String get yourNameInvalid => 'Enter a name of 1 to 80 characters.';

  @override
  String get yourNameConfirm => 'Yes, that\'s me';

  @override
  String get yourNameNotNow => 'Not now';

  @override
  String get yourNameLoadFailed => 'Couldn\'t load your name.';

  @override
  String get yourNameOffline =>
      'No internet connection. Your name was not saved.';

  @override
  String get yourNameAdd => 'Add your name';

  @override
  String get yourNameEditBody =>
      'Everyone in your household sees this name. People you invite see your first name.';

  @override
  String get yourNameSaved => 'Name saved';

  @override
  String get reportEntryAlso => 'Also: report content';

  @override
  String get reportContent => 'Report content';

  @override
  String get reportEntryHint =>
      'Only we read the report, nobody in your household.';

  @override
  String get reportIntro =>
      'Use this form to report content in Snacklist that you believe is illegal, for example an item, a list, a household name or a photo. For questions or bugs, please use feedback or support@snacklist.app. This form is not an emergency service: if someone is in immediate danger, call your local emergency number now (112 in the EU).';

  @override
  String get reportRequired => 'required';

  @override
  String get reportRecommended => 'recommended';

  @override
  String get reportAbout => 'What is it about?';

  @override
  String get reportCategoryHate => 'Insults, threats or hate';

  @override
  String get reportCategoryPersonalRights =>
      'Violation of my personal rights or privacy (e.g. a photo of me)';

  @override
  String get reportCategoryIp => 'Copyright or trade mark';

  @override
  String get reportCategoryCsam => 'Child sexual abuse material';

  @override
  String get reportCategoryDanger => 'Threat to life or safety';

  @override
  String get reportCategoryOther => 'Other illegal content';

  @override
  String get reportWhere => 'Where is the content?';

  @override
  String get reportWhereHelp =>
      'In the app we select the item, list or photo for you – please check it.';

  @override
  String get reportWhereChooseHelp =>
      'Choose the item, list or household name. The more exact, the faster we can find it.';

  @override
  String get reportWhereElsewhereHelp =>
      'Describe where it is: the household and list name and the exact text of the item. The more exact, the faster we can find it.';

  @override
  String get reportWhereChoose => 'Choose';

  @override
  String get reportWhereChange => 'Change';

  @override
  String get reportWhy => 'Why is this content illegal?';

  @override
  String get reportWhyHelp =>
      'Please explain as precisely as you can which right is violated and why. If it concerns your own rights, tell us how you are connected to the content.';

  @override
  String reportCounter(int count, int max) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat maxNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String maxString = maxNumberFormat.format(max);

    return '$countString / $maxString';
  }

  @override
  String get reportName => 'Your name';

  @override
  String get reportEmail => 'Your e-mail address';

  @override
  String get reportContactHelp =>
      'We need your name and e-mail address to confirm receipt and tell you our decision. Without them we still review the report, but can\'t reply.';

  @override
  String get reportCsamNote =>
      'For child sexual abuse material you can report without your name and e-mail address.';

  @override
  String get reportCsamAdd => 'Add my name and e-mail address';

  @override
  String get reportGoodFaith =>
      'I believe in good faith that the information and allegations in this report are accurate and complete.';

  @override
  String get reportScreenshot => 'Attach screenshot (optional)';

  @override
  String get reportScreenshotHelp =>
      'Cover anything that has nothing to do with the report.';

  @override
  String get reportScreenshotAttached => 'Screenshot attached';

  @override
  String get reportScreenshotRemove => 'Remove';

  @override
  String get reportPrivacyLead => 'How we handle your details:';

  @override
  String get reportPrivacyLink => 'Privacy policy, section 10';

  @override
  String get reportSend => 'Send report';

  @override
  String get reportErrorAbout => 'Choose what it is about.';

  @override
  String get reportErrorWhere => 'Choose where the content is.';

  @override
  String reportErrorShort(int count) {
    return 'At least 20 characters ($count more).';
  }

  @override
  String get reportErrorLong => 'At most 5,000 characters.';

  @override
  String get reportErrorEmail => 'Check the e-mail address.';

  @override
  String get reportErrorGoodFaith => 'Please confirm this to send the report.';

  @override
  String get reportFailedRateLimited =>
      'Your report was not sent because too many reports are arriving right now. Your details are still here. Please try again in an hour or e-mail them to our point of contact support@snacklist.app: what it is about, where the content is and why it is illegal. We handle your report that way too.';

  @override
  String get reportFailedUnavailable =>
      'The report couldn\'t be sent just now. Please try again shortly or write to support@snacklist.app.';

  @override
  String get reportFailedOffline =>
      'No connection. Your details are still here: please try again shortly.';

  @override
  String get reportFailedScreenshotTooLarge =>
      'The screenshot is too large. Remove it and send the report again.';

  @override
  String get reportPickerSearch => 'Search items and lists';

  @override
  String get reportPickerItems => 'Items';

  @override
  String get reportPickerLists => 'Lists';

  @override
  String get reportPickerHousehold => 'Household name';

  @override
  String get reportPickerElsewhere => 'Somewhere else';

  @override
  String get reportKindItem => 'Item';

  @override
  String get reportKindList => 'List';

  @override
  String get reportKindHousehold => 'Household';

  @override
  String reportQuoted(String name) {
    return '“$name”';
  }

  @override
  String reportItemContext(String list, String household) {
    return 'List “$list” · $household';
  }

  @override
  String get reportSentTitle => 'Report sent';

  @override
  String get reportNumber => 'Number';

  @override
  String get reportCopyNumber => 'Copy number';

  @override
  String get reportCopied => 'Copied';

  @override
  String reportThanks(String ref) {
    return 'Thanks, we\'ve received your report. Number: $ref. We review it ourselves – with no automated decision – and will get back to you if you gave an e-mail address.';
  }

  @override
  String reportMailed(String email) {
    return 'A confirmation is on its way to $email.';
  }

  @override
  String get reportNotMailed =>
      'You gave no e-mail address, so we can\'t reply. Keep the number if you want to ask about it.';

  @override
  String get reportNotInNotes =>
      'Reports don\'t appear under Your notes and nobody in your household sees them.';

  @override
  String get reportDone => 'Done';

  @override
  String storeAppOpen(String app) {
    return 'Open $app';
  }

  @override
  String countryName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'DE': 'Germany',
      'AT': 'Austria',
      'CH': 'Switzerland',
      'FR': 'France',
      'NL': 'Netherlands',
      'PL': 'Poland',
      'IT': 'Italy',
      'ES': 'Spain',
      'other': '$code',
    });
    return '$_temp0';
  }

  @override
  String chainQuestionOne(String chain, String country) {
    return 'Is this $chain ($country)?';
  }

  @override
  String chainQuestionOneExisting(String store, String chain, String country) {
    return 'Is your “$store” the chain $chain ($country)?';
  }

  @override
  String chainQuestionApp(String app) {
    return 'Then you can open $app right from the list.';
  }

  @override
  String get chainQuestionYes => 'Yes';

  @override
  String get chainQuestionKeep => 'No, keep it as is';

  @override
  String get chainQuestionNo => 'No';

  @override
  String chainQuestionWhich(String store) {
    return 'Which $store?';
  }

  @override
  String chainQuestionWhichExisting(String store) {
    return 'Which chain is your “$store”?';
  }

  @override
  String get chainQuestionNone => 'None of these';

  @override
  String chainWithCountry(String chain, String country) {
    return '$chain ($country)';
  }

  @override
  String get storeAppTip => 'Opens the store\'s app.';

  @override
  String chainCardProgress(int index, int total) {
    return '$index / $total';
  }

  @override
  String chainCardProgressLabel(int index, int total) {
    return 'Store $index of $total';
  }

  @override
  String chainSuggestionPick(String chain, String country) {
    return 'Choose $chain ($country)';
  }

  @override
  String get storeAppCardTitle => 'App';

  @override
  String get storeAppCardOpen => 'Open';

  @override
  String get storeAppCardChoose => 'Which app should open?';

  @override
  String storeChainLinked(String chain, String country) {
    return 'Matched: $chain · $country';
  }

  @override
  String get storeChainChange => 'Change';

  @override
  String get storeChainChangeLabel => 'Change chain';

  @override
  String get storeChainUnlink => 'Remove match';

  @override
  String get storeChainUnlinkLabel => 'Remove the chain match';

  @override
  String get storeChainConnect => 'Match to a chain';

  @override
  String get storeChainPickerTitle => 'Choose a chain';

  @override
  String get storeChainPickerSearch => 'Search chains';

  @override
  String get storeChainPickerEmpty => 'No chain found.';

  @override
  String get migrateBody =>
      'Recognised stores can show a button for their app. Names stay as you wrote them.';

  @override
  String get migrateDone => 'Matched';
}
