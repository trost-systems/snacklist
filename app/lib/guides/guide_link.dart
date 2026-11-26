import 'package:family_groceries/core/deep_links.dart';
import 'package:family_groceries/guides/guide_page.dart';

/// Where a link in a guide leads. A claimed URL ([siteLinks], [appLinks])
/// stays in the app: the system browser would hand it straight back on
/// Android.
sealed class const GuideLink();

/// Another guide or guide list, at its route: pushed over this one.
final class const OpenGuide(final String location) implements GuideLink;

/// A screen of the app, at its route (path and query).
final class const OpenScreen(final String location) implements GuideLink;

/// A section of this guide; `''` is the page itself.
final class const ScrollTo(final String fragment) implements GuideLink;

/// Anything else, in the system browser.
final class const OpenOutside(final Uri url) implements GuideLink;

/// [href] of a link on [page] (a [guidePage]), or null when it is no URL.
GuideLink? resolveGuideLink(Uri page, String href) {
  final ref = Uri.tryParse(href);
  if (ref == null) {
    return null;
  }
  final url = page.resolveUri(ref);
  final web = url.scheme == 'https' || url.scheme == 'http';
  final host = url.host == 'www.$siteLinkHost' ? siteLinkHost : url.host;
  if (web && host == siteLinkHost && isSiteLink(url)) {
    final target = guidePage(url.path);
    return target.path == page.path
        ? ScrollTo(url.fragment)
        : OpenGuide(target.path);
  }
  if (web && appLinkHosts.contains(host) && isAppLink(url)) {
    return OpenScreen(
      Uri(path: url.path, query: url.hasQuery ? url.query : null).toString(),
    );
  }
  return OpenOutside(url);
}
