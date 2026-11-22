import { test } from 'node:test';
import assert from 'node:assert/strict';
import { getApp, storeFor } from '../api/get.mjs';
import { STORE_URLS } from '../config/stores.mjs';
import { buildSite, serve } from './helpers.mjs';

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';
const IPAD = 'Mozilla/5.0 (iPad; CPU OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1';
const ANDROID = 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
const DESKTOP = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const LISTED = STORE_URLS;
const UNLISTED = { appStore: 'TODO: not public', googlePlay: 'TODO: not public' };

const go = (ua, lang, urls) => getApp(new Request('https://snacklist.app/get', { headers: { 'user-agent': ua, ...(lang ? { 'accept-language': lang } : {}) } }), urls);

test('/get sends a phone to its store once the listing is public', () => {
  for (const [ua, want] of [[IPHONE, LISTED.appStore], [IPAD, LISTED.appStore], [ANDROID, LISTED.googlePlay]]) {
    const res = go(ua, 'de-DE', LISTED);
    assert.deepEqual([res.status, res.headers.get('location')], [302, want], ua);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(res.headers.get('vary'), 'user-agent, accept-language');
  }
});

test('/get sends a desktop, an unknown agent and every phone without a public listing to the landing page', () => {
  for (const [ua, lang, urls, want] of [
    [DESKTOP, 'de-DE,de;q=0.9', LISTED, '/de'],
    [DESKTOP, 'en-US', LISTED, '/en'],
    ['curl/8.5.0', undefined, LISTED, '/de'],
    [IPHONE, 'en-GB', UNLISTED, '/en'],
    [ANDROID, 'de', UNLISTED, '/de'],
  ]) {
    assert.equal(go(ua, lang, urls).headers.get('location'), want, `${ua} ${lang}`);
  }
  assert.equal(storeFor(DESKTOP, LISTED), null);
});

test('the preview serves /get through the vercel.json rewrite', async () => {
  const { outDir } = buildSite();
  const res = await serve(outDir, ['/get']);
  assert.deepEqual([res['/get'].status, res['/get'].headers.location], [302, '/de']);
});
