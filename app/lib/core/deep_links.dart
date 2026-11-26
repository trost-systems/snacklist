/// The links that open the installed app instead of the browser
/// (docs/DEEP_LINKS.md): iOS universal links and Android App Links, each
/// host with its own table. [appLinks] are the paths of the app URL
/// ([appLinkHosts]), whose association files the web build serves
/// (`web/.well-known/`); [siteLinks] are the public guides on snacklist.app
/// ([siteLinkHost]), whose files the site serves
/// (`site/public/.well-known/`). The entitlement, Android's two verified
/// intent filters and those files are checked against both tables by
/// `test/core/deep_links_config_test.dart`. Without the app, the same URL
/// opens the web app or the site.
///
/// `/` itself is not claimed: web sign-in returns there with its code,
/// which only the browser that started it can redeem. Neither are the
/// sign-in, onboarding and consent pages, which a browser flow redirects
/// to, nor anything on snacklist.app but the guides.
typedef AppLink = ({String path, bool prefix});

/// The app URL's hosts: app.snacklist.app, and app.hummlist.com until R1.
const appLinkHosts = {'app.snacklist.app', 'app.hummlist.com'};

/// The public site's host. `www.snacklist.app` redirects here and is not
/// claimed: Apple does not follow a redirect for the association file.
const siteLinkHost = 'snacklist.app';

/// app.snacklist.app (and app.hummlist.com until R1).
const appLinks = <AppLink>[
  (path: '/list', prefix: false),
  (path: '/add', prefix: false),
  (path: '/stores/', prefix: true),
  (path: '/more', prefix: false),
  (path: '/more/', prefix: true),
  (path: '/join/', prefix: true),
  (path: '/history', prefix: false),
  (path: '/history/', prefix: true),
  (path: '/edit', prefix: false),
  (path: '/edit/', prefix: true),
  (path: '/trip/', prefix: true),
];

/// snacklist.app: the public guides, which the app shows itself.
const siteLinks = <AppLink>[
  (path: '/de/anleitungen', prefix: false),
  (path: '/de/anleitungen/', prefix: true),
  (path: '/en/guides', prefix: false),
  (path: '/en/guides/', prefix: true),
];

/// Whether [uri]'s path is one of [appLinks].
bool isAppLink(Uri uri) => _matches(appLinks, uri);

/// Whether [uri]'s path is one of [siteLinks].
bool isSiteLink(Uri uri) => _matches(siteLinks, uri);

bool _matches(List<AppLink> links, Uri uri) => links.any(
  (link) =>
      link.prefix ? uri.path.startsWith(link.path) : uri.path == link.path,
);
