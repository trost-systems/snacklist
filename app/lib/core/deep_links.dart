/// The paths of the app URL (app.snacklist.app) that open the installed app
/// instead of the browser (docs/DEEP_LINKS.md): iOS universal links
/// (`web/.well-known/apple-app-site-association`) and Android App Links
/// (the verified intent filter in `AndroidManifest.xml`), both checked
/// against this table by `test/core/deep_links_config_test.dart`. Without
/// the app, the same URL opens the web app.
///
/// `/` itself is not claimed: web sign-in returns there with its code,
/// which only the browser that started it can redeem. Neither are the
/// sign-in, onboarding and consent pages, which a browser flow redirects
/// to.
typedef AppLink = ({String path, bool prefix});

const appLinks = <AppLink>[
  (path: '/list', prefix: false),
  (path: '/add', prefix: false),
  (path: '/stores/', prefix: true),
  (path: '/more', prefix: false),
  (path: '/more/', prefix: true),
  (path: '/join/', prefix: true),
];

/// Whether [uri]'s path is one of [appLinks].
bool isAppLink(Uri uri) => appLinks.any(
  (link) =>
      link.prefix ? uri.path.startsWith(link.path) : uri.path == link.path,
);
