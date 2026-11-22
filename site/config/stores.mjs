// Where the launch stage's badges, QR codes and /get send people (job 82 ADDENDUM 8, job 370):
// the public store listings.
export const STORE_URLS = {
  appStore: 'https://apps.apple.com/app/id6832756448',
  googlePlay: 'https://play.google.com/store/apps/details?id=com.snacklist.app',
};

export const GET_URL = 'https://snacklist.app/get';
// The browser app, linked in the launch stage's top nav.
export const WEB_APP_URL = 'https://app.snacklist.app';

export const storeUrlSet = (url) => url.startsWith('https://');
