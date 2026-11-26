// „In der App öffnen“ on the guides (job 462, build.mjs): a phone's tap opens the installed app at
// this page, as the web app's card does (app/lib/core/open_app.dart, appOpening). Universal Links
// skip a pasted link and a page iOS was told to open in Safari. Only a tap may open another app,
// so the button stays a link; tablets and desktops keep it hidden.
{
  const ua = navigator.userAgent;
  const path = location.pathname;
  // iPhone: the app's custom scheme; its router reads only the path, and a query could pass for a
  // sign-in. Android: an intent for the App Link, back to this page when no app takes it.
  const href = /iPhone|iPod/.test(ua)
    ? `com.snacklist.app://open${path}`
    : /Android/.test(ua) && /Mobile/.test(ua)
      ? `intent://snacklist.app${path}#Intent;scheme=https;package=com.snacklist.app;S.browser_fallback_url=${encodeURIComponent(location.href)};end`
      : null;
  const box = document.querySelector('.open-app');
  if (box && href) {
    box.querySelector('a').href = href;
    box.hidden = false;
  }
}
