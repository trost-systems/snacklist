import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The smallest text size in the app: captions, field errors, counts and
/// the section overline. Material's 11 and 12 px sat below what a hint, an
/// error or a count must be read at.
const double captionSize = 13;

/// Lists the bundled fonts' SIL Open Font Licenses on the licence page, as
/// the OFL asks of a bundle that ships the fonts.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in const [
      ('Bricolage Grotesque', 'OFL-BricolageGrotesque.txt'),
      ('Inter', 'OFL-Inter.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
}
