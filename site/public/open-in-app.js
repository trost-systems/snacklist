// The guides and their indexes open in the app when it is installed (job 462). When the
// Universal Link or App Link did not fire (a typed URL, a link inside another app's browser), the
// page offers the hand-off by hand: the sign-in scheme on iOS, an intent on Android that falls
// back to this page without the app. Desktop browsers keep the link hidden.
(() => {
  const agent = navigator.userAgent;
  // iPadOS reports itself as a Mac; only the touch screen tells them apart.
  const ios = /iPhone|iPad|iPod/.test(agent) || (/Macintosh/.test(agent) && navigator.maxTouchPoints > 1);
  const android = /Android/.test(agent);
  if (!ios && !android) return;
  // A section (`#…`) rides along on iOS; an intent URL has no room for one, its `#` is the intent's.
  const target = () => {
    const { host, href, pathname, search, hash } = location;
    return ios
      ? `com.snacklist.app://open${pathname}${search}${hash}`
      : `intent://${host}${pathname}${search}#Intent;scheme=https;package=com.snacklist.app;S.browser_fallback_url=${encodeURIComponent(href)};end`;
  };
  const links = document.querySelectorAll('a[data-open-in-app]');
  const update = () => {
    for (const link of links) link.href = target();
  };
  update();
  addEventListener('hashchange', update);
  for (const link of links) link.closest('[hidden]')?.removeAttribute('hidden');
})();
