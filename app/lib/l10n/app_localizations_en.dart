// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Hummlist';

  @override
  String get addFieldHint => 'What do you need?';

  @override
  String get addButton => 'Add';

  @override
  String get emptyList => 'The list is empty. Type below what you need.';

  @override
  String get sortingItem => 'Sorting …';

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
  String get dictationListening => 'Listening …';

  @override
  String get dictationUnavailable =>
      'Voice input isn\'t available. Allow microphone and speech recognition in Settings.';

  @override
  String get dictationNoOfflineGerman =>
      'Dictation only works offline, so your voice stays on the device. This device is missing German offline speech recognition. Download it in the system settings or type the item instead.';

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
    return 'Change refused: $name';
  }

  @override
  String get inviteMember => 'Invite your partner';

  @override
  String get joinOtherHousehold => 'Join another household';

  @override
  String get signOut => 'Sign out';

  @override
  String get inviteTitle => 'Invite member';

  @override
  String get inviteBody =>
      'Enter this code in the app or share the link. The invite is valid for 7 days and for one person.';

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
  String get onboardingTitle => 'Welcome to Hummlist';

  @override
  String get onboardingBody =>
      'Hummlist shares one shopping list with everyone in your household. Create a new household or accept an invite.';

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
  String get loading => 'Loading …';

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
  String get siriSayHint => 'For example, say “Hey Siri, add to Hummlist”.';

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
      'Siri on that iPhone can no longer add items. Hummlist sets Siri up again the next time it starts there.';

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
  String get listHint => 'Tap ticks off · Hold to edit';

  @override
  String get listHintDismiss => 'Got it';

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
    return '“$household” has Hummlist Premium. It belongs to the household and ends with it. Archiving isn\'t possible here, because an archived household is deleted with your account. To keep the household with Premium, invite someone first and delete your account only after they have joined.';
  }

  @override
  String accountDeletePremiumLastMember(String household) {
    return '“$household” has Hummlist Premium. It belongs to the household. If you delete your account, it ends. Do you want to keep it? Then ask someone to join first. Wait until they have joined. Then delete your account.';
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
          'Your archived households $names are deleted with your account, and their Hummlist Premium with them.',
      one:
          'Your archived household $names is deleted with your account, and its Hummlist Premium with it.',
    );
    return '$_temp0';
  }

  @override
  String quotedName(String name) {
    return '“$name”';
  }

  @override
  String get accountDeletePremiumAck =>
      'I know: Premium ends. I will not get my money back on its own.';

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
      'If you signed in with Apple, remove “Hummlist” on your iPhone under Settings › [your name] › Sign-In & Security › Sign in with Apple.';

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
  String get suggestionCatalog => 'From the catalogue';

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
      'Drag the stores into the order they have on the list. Tap a store to rename it and order its categories.';

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
      'No stores yet. Add one and the list sorts your items along its walking route.';

  @override
  String storeDeleteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open items move to “No store”.',
      one: '1 open item moves to “No store”.',
      zero: 'No open items are in this store.',
    );
    return '$_temp0 Its walking route goes too.';
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
  String get languageSystem => 'Device';

  @override
  String languageSystemNow(String language) {
    return 'Currently $language';
  }

  @override
  String languageSystemPicked(String language) {
    return 'Device ($language)';
  }

  @override
  String get legal => 'Legal';

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
      'Hummlist has downloaded improvements. Restart the app to use them.';

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
  String get analyticsConsentTitle => 'May Hummlist collect usage data?';

  @override
  String get analyticsConsentBody =>
      'Hummlist (run by Peter Trost) wants to see which features are used, find bugs, measure whether Hummlist pays for itself and switch new features on step by step. For that, Hummlist stores a random ID on this device and uses it to send pseudonymous usage data, error reports, your household\'s ID and technical details of your device or browser to our service provider PostHog (servers in the EU). List contents, names and e-mail addresses are never sent. You can withdraw any time under More → Usage data. More in the';

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
      'Pseudonymous, to PostHog (servers in the EU), never list contents. Applies to this device. Turning it off deletes the ID on this device.';

  @override
  String get internalInstall => 'Internal installation';

  @override
  String get sendTestError => 'Send a test error';

  @override
  String get feedbackRow => 'Send feedback';

  @override
  String get rateApp => 'Rate Hummlist';

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
  String get feedbackCategories => 'Kind (optional)';

  @override
  String get feedbackContact => 'Peter may contact me about this';

  @override
  String get feedbackAttached =>
      'App version, device, language and current screen. No list items.';

  @override
  String get feedbackAttachedTitle => 'Sent along:';

  @override
  String get feedbackSend => 'Send';

  @override
  String get feedbackRetry => 'Retry';

  @override
  String get feedbackSending => 'Sending …';

  @override
  String get feedbackThanks => 'Thanks!';

  @override
  String get feedbackFailed => 'Not sent. Check your connection and try again.';

  @override
  String feedbackTooLong(int max) {
    return '$max characters at most';
  }

  @override
  String feedbackCounter(int count, int max) {
    return '$count / $max';
  }

  @override
  String get feedbackClose => 'Close';

  @override
  String get onboardingCreateHint =>
      'A new list; you invite your partner next.';

  @override
  String get onboardingJoin => 'Join with an invite';

  @override
  String get onboardingJoinHint => 'You got a link or a code.';

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
  String get storesDisclaimer =>
      'We use shop names such as dm, Lidl or EDEKA only so you can see which shop a list is for. The names and trade marks belong to their owners. Hummlist is independent and isn\'t affiliated with, sponsored or endorsed by these companies.';

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
  String get invitePreview => 'Invite to the household';

  @override
  String get invitePartnerBody =>
      'Share the link or the code with the person you shop with. The invite is valid for 7 days and for one person.';

  @override
  String get later => 'Later';

  @override
  String get toTheList => 'Go to the list';

  @override
  String inviteShareText(String link, String code) {
    return 'Join our Hummlist household: $link · Code: $code';
  }

  @override
  String inviteShareTextCodeOnly(String code) {
    return 'Join our Hummlist household. Code: $code';
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
  String get invitesOpen => 'Open invites';

  @override
  String get invitesEmpty => 'No open invites.';

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
  String get lifetimeTitle => 'Hummlist Lifetime';

  @override
  String get lifetimeRowHint => 'Support Hummlist';

  @override
  String get lifetimeBody =>
      'One purchase for your whole household: Hummlist Lifetime supports the development of Hummlist.';

  @override
  String get lifetimeBuy => 'Continue to purchase';

  @override
  String get lifetimePriceInStore =>
      'The App Store or Google Play shows you the price before you buy.';

  @override
  String get lifetimeRestore => 'Restore purchase';

  @override
  String get lifetimeUnlockedBody =>
      'Hummlist Lifetime is unlocked for your whole household. Thank you!';

  @override
  String get lifetimePending => 'Waiting for approval';

  @override
  String get lifetimePendingBody =>
      'Hummlist Lifetime is unlocked as soon as the purchase is approved. This can take a while.';

  @override
  String get lifetimeUnlocking => 'Unlocking …';

  @override
  String get lifetimeUnlockDelayed =>
      'Your purchase went through; unlocking just takes longer than usual. It appears here by itself, so please don\'t buy again.';

  @override
  String get lifetimeBoughtTwice =>
      'Your household bought Hummlist Lifetime more than once. One of the purchases can be refunded.';

  @override
  String get lifetimeCanceled => 'Purchase canceled.';

  @override
  String get lifetimeComingSoon => 'Hummlist Lifetime is coming soon.';

  @override
  String get lifetimeStoreOffline =>
      'The store can\'t be reached right now. Check your connection.';

  @override
  String get lifetimeUsedElsewhere =>
      'This purchase belongs to another, earlier household and stays there. It unlocks nothing here.';

  @override
  String get lifetimeNothingRestored => 'No earlier purchase found.';

  @override
  String lifetimeStoreFailed(String code) {
    return 'The purchase didn\'t go through ($code).';
  }

  @override
  String get lifetimeWeb =>
      'You can buy Hummlist Lifetime in the iPhone or Android app. It\'s then unlocked here too, for your whole household.';

  @override
  String get lifetimeChecking =>
      'Checking whether your household has Hummlist Lifetime already …';

  @override
  String get lifetimeRefundLink =>
      'Bought it twice? How to get your money back';

  @override
  String get refundHelpTitle => 'Request a refund';

  @override
  String get refundHelpBody =>
      'Hummlist Lifetime always belongs to the household it was bought in. Only Apple refunds App Store purchases. For Google Play, ask Google within 48 hours of buying; after that, email us at support@hummlist.com and we\'ll look at your request. Your statutory rights are not affected.';

  @override
  String get refundHelpApple =>
      'iPhone: open reportaproblem.apple.com, sign in with your Apple Account, choose “Request a refund”, then Hummlist Lifetime.';

  @override
  String get refundHelpGoogle =>
      'Android, within 48 hours: open Google Play, tap your profile picture, then “Payments & subscriptions”, “Budget & order history”, choose Hummlist Lifetime and “Report a problem”. After that, email us with the order number (it starts with “GPA.”) or your Google account\'s email address.';

  @override
  String get refundHelpReason =>
      'As the reason you can write: “My household was already unlocked.”';

  @override
  String get refundHelpAppleLink => 'Ask Apple';

  @override
  String get refundHelpGoogleLink => 'Ask Google';

  @override
  String get refundHelpFaqLink => 'More in the FAQ';

  @override
  String get joinTargetUnlocked =>
      'This household has Hummlist Lifetime. You don\'t need to buy anything.';

  @override
  String get joinRefundLink =>
      'Bought Hummlist Lifetime recently? How to request a refund';

  @override
  String get joinLifetimeRefundLink => 'Ask Apple or Google for a refund';

  @override
  String get archivedTitle => 'Archived households';

  @override
  String get archivedEmpty => 'You haven\'t archived a household.';

  @override
  String get archivedUnlocked => 'With Hummlist Lifetime';

  @override
  String archivedDeletesOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Will be deleted on $dateString';
  }

  @override
  String get archivedRestore => 'Bring back';

  @override
  String archivedRestoreTitle(String household) {
    return 'Bring back “$household”?';
  }

  @override
  String archivedRestoreBody(String household) {
    return 'You are a member of “$household” again. Your other households stay.';
  }

  @override
  String get premiumTitle => 'Hummlist Premium';

  @override
  String get premiumHeroTitle => 'One buys. Everyone has it.';

  @override
  String get premiumHeroBody =>
      'Hummlist Premium covers your whole household, including everyone who joins later.';

  @override
  String get premiumBenefitSiri =>
      'Add to the list with Siri, without opening the app';

  @override
  String get premiumBenefitAi =>
      'Connect AI assistants that support MCP to your list';

  @override
  String get premiumBenefitApi => 'Your own automations with the Hummlist API';

  @override
  String premiumStatusRenews(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Hummlist Premium active (yearly, renews on $dateString)';
  }

  @override
  String premiumStatusEnds(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Hummlist Premium active (yearly, ends on $dateString)';
  }

  @override
  String get premiumStatusLifetime => 'Hummlist Premium Lifetime';

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
      'Free in the beta, until Hummlist Premium launches';

  @override
  String get premiumChecking =>
      'Checking whether your household already has Hummlist Premium …';

  @override
  String get premiumYearlyTitle => 'Yearly';

  @override
  String get premiumPerYear => 'per year';

  @override
  String get premiumLifetimeTitle => 'Lifetime';

  @override
  String get premiumOneTime => 'one-time';

  @override
  String get premiumLifetimeValue =>
      'Pay once, for good: as much as three years.';

  @override
  String get premiumYearlyTerms =>
      'Hummlist Premium yearly, 1 year. The plan renews automatically for another year unless you cancel it at least 24 hours before the end of the period. Your Apple or Google account is charged when you confirm the purchase and at every renewal. You can manage and cancel the plan in the App Store\'s or Google Play\'s subscription settings.';

  @override
  String premiumHousehold(String household) {
    return 'Premium then belongs to the household “$household” and stays there, even if you leave it later.';
  }

  @override
  String get premiumBuyYearly => 'Subscribe yearly';

  @override
  String get premiumBuyLifetime => 'Buy Lifetime';

  @override
  String get premiumUnavailable =>
      'Hummlist Premium is not available right now.';

  @override
  String get premiumTermsLink => 'Terms of Use (EULA)';

  @override
  String get premiumPrivacyLink => 'Privacy policy';

  @override
  String get premiumUsedElsewhereYearly =>
      'Your Apple or Google account already pays a yearly plan for another household. Someone else in this household can subscribe to Hummlist Premium.';

  @override
  String get premiumTwoYearly =>
      'Your household has two yearly plans. Each can only be cancelled by whoever took it out.';

  @override
  String get premiumWeb =>
      'You can buy Hummlist Premium in the iPhone or Android app. It is then unlocked here too, for your whole household.';

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
      'Your household already has a yearly plan. It keeps running and being billed after the one-time purchase until it is cancelled; the rest of the plan year isn\'t refunded automatically. Only the person who took out the plan can cancel it, in [Manage subscriptions]. Hummlist can\'t cancel it.';

  @override
  String get premiumLifetimeWhileYearlySubscriber =>
      'Your household already has a yearly plan. It keeps running and being billed after the one-time purchase until it is cancelled; the rest of the plan year isn\'t refunded automatically. You can cancel it in [Manage subscription]. Hummlist can\'t cancel it.';

  @override
  String get premiumBuyAnyway => 'Buy anyway';

  @override
  String get premiumBillingContinues =>
      'Your Hummlist Premium yearly plan keeps running and is billed to your Apple or Google account until you cancel it. Deleting or leaving doesn\'t cancel it.';

  @override
  String get premiumBillingContinuesOther =>
      'A yearly plan for this household keeps running until it is cancelled.';

  @override
  String get premiumManageSubscription => 'Manage subscription';

  @override
  String get premiumContinueAnyway => 'Continue anyway';

  @override
  String get integrationPremiumTitle => 'Part of Hummlist Premium';

  @override
  String get integrationPremiumBody =>
      'Siri and AI assistants are part of Hummlist Premium. Your connections stay saved and work again as soon as your household has Hummlist Premium.';

  @override
  String get integrationPremiumSiri => 'Siri on iPhone';

  @override
  String get integrationPremiumAi => 'AI assistants that support MCP';

  @override
  String get integrationPremiumLater =>
      'Later: Google Assistant and Apple Watch';

  @override
  String get integrationPremiumBuy => 'Unlock Hummlist Premium';

  @override
  String get integrationPremiumSoon => 'Coming soon.';

  @override
  String get integrationPaused => 'Paused: needs Hummlist Premium';

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
      'The Hummlist API is part of Hummlist Premium. Your keys stay and work again as soon as your household has Premium.';

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
      'Press and hold an item without dragging it to change its quantity, brand, store and more.';

  @override
  String get tipAmountsTitle => 'Type the amount too';

  @override
  String get tipAmountsBody =>
      'Write “2 cucumbers” or “milk 2 l” and Hummlist picks up the amount.';

  @override
  String get tipDismiss => 'Hide tip';

  @override
  String get tooManyHouseholds =>
      'You are in 10 households already. Leave one before you create or join another.';

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
    return 'Siri, Alexa and AI assistants use “$household” now.';
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
  String get householdMemberUnnamed => 'No name';

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
    return '“$household” has Hummlist Lifetime. You are the last member: if you leave, the household is deleted. Hummlist Lifetime ends with it, because a purchase belongs to its household.';
  }

  @override
  String leaveArchiveOffer(String household) {
    return '“$household” has Hummlist Lifetime. You are the last member. Archive the household instead of deleting it: the list and Hummlist Lifetime are kept, and you can bring it back under “More” later. If you don\'t bring it back within 24 months, it is deleted.';
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
}
