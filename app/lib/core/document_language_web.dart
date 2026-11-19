import 'package:web/web.dart' as web;

/// Sets `<html lang>` to the language the app shows, so screen readers and
/// the browser's translate offer read the page in it (index.html starts
/// with `de`).
void setDocumentLanguage(String code) {
  final root = web.document.documentElement;
  if (root != null && root.getAttribute('lang') != code) {
    root.setAttribute('lang', code);
  }
}
