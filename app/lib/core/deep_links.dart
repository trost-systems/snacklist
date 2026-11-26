/// The links that open the installed app instead of the browser
/// (docs/DEEP_LINKS.md): iOS universal links (an
/// `apple-app-site-association` per host) and Android App Links (one
/// verified intent filter per [LinkHost] in `AndroidManifest.xml`), all
/// checked against this table by `test/core/deep_links_config_test.dart`.
/// Without the app, the same URL stays in the browser.
///
/// On the app host `/` itself is not claimed: web sign-in returns there
/// with its code, which only the browser that started it can redeem.
/// Neither are the sign-in, onboarding and consent pages, which a browser
/// flow redirects to. On the site only the guides are: its landing, legal,
/// support and changelog pages stay in the browser.
enum LinkHost(final List<String> hosts) {
  /// The web app; app.hummlist.com serves it too until R1, for old links.
  app(['app.snacklist.app', 'app.hummlist.com']),

  /// The public site (`site/`), never www, which redirects to it.
  site(['snacklist.app']),
}

typedef AppLink = ({LinkHost host, String path, bool prefix});

const appLinks = <AppLink>[
  (host: LinkHost.app, path: '/list', prefix: false),
  (host: LinkHost.app, path: '/add', prefix: false),
  (host: LinkHost.app, path: '/stores/', prefix: true),
  (host: LinkHost.app, path: '/more', prefix: false),
  (host: LinkHost.app, path: '/more/', prefix: true),
  (host: LinkHost.app, path: '/join', prefix: false),
  (host: LinkHost.app, path: '/join/', prefix: true),
  (host: LinkHost.app, path: '/edit', prefix: false),
  (host: LinkHost.app, path: '/edit/', prefix: true),
  (host: LinkHost.app, path: '/history', prefix: false),
  (host: LinkHost.app, path: '/history/', prefix: true),
  (host: LinkHost.app, path: '/trip/', prefix: true),
  (host: LinkHost.app, path: '/households/new', prefix: false),
  (host: LinkHost.app, path: '/households/new/', prefix: true),
  (host: LinkHost.site, path: '/de/anleitungen', prefix: false),
  (host: LinkHost.site, path: '/de/anleitungen/', prefix: true),
  (host: LinkHost.site, path: '/en/guides', prefix: false),
  (host: LinkHost.site, path: '/en/guides/', prefix: true),
];

/// Whether [host]'s entries of [appLinks] claim [path].
bool claims(LinkHost host, String path) => appLinks.any(
  (link) =>
      link.host == host &&
      (link.prefix ? path.startsWith(link.path) : path == link.path),
);

/// Whether [uri]'s path is claimed on the app host, whatever host [uri]
/// names (a location in the app has none).
bool isAppLink(Uri uri) => claims(LinkHost.app, uri.path);
