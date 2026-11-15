/// Which store listings are public, and where they are: the web join
/// page's `storeListings`, `appStoreId` and `playPackage`
/// (`web/join/join.js`), which `test/app/store_listings_test.dart` holds
/// these to. Nothing links to a listing that is not public.
typedef StoreListings = ({bool appStore, bool googlePlay});

const storeListings = (appStore: false, googlePlay: false);

const appStoreId = '6832756448';

const playPackage = 'com.snacklist.app';

const appStoreUrl = 'https://apps.apple.com/app/id$appStoreId';

const playStoreUrl =
    'https://play.google.com/store/apps/details?id=$playPackage';
