import 'package:family_groceries/list/retailer.dart';

import 'fake_repository.dart';

const lidlPlus = RetailerApp(
  name: 'Lidl Plus',
  android: 'com.lidl.eci.lidlplus',
  ios: '1238611143',
);
const lidl = Retailer(
  chain: 'lidl',
  country: 'DE',
  name: 'Lidl',
  apps: [lidlPlus],
);
const rewe = Retailer(
  chain: 'rewe',
  country: 'DE',
  name: 'REWE',
  apps: [RetailerApp(name: 'REWE', android: 'de.rewe.app.mobile', ios: '6')],
);
const aldiNord = Retailer(
  chain: 'aldi-nord',
  country: 'DE',
  name: 'ALDI Nord',
  apps: [
    RetailerApp(name: 'ALDI Nord', android: 'de.aldiNord.android', ios: '3'),
  ],
);
const aldiSued = Retailer(
  chain: 'aldi-sued',
  country: 'DE',
  name: 'ALDI SÜD',
  apps: [RetailerApp(name: 'ALDI SÜD', android: 'de.aldi_de', ios: '4')],
);
const hofer = Retailer(
  chain: 'aldi-sued',
  country: 'AT',
  name: 'HOFER',
  apps: [RetailerApp(name: 'HOFER', android: 'de.aldi_at', ios: '5')],
);
const billaApp = RetailerApp(name: 'BILLA', android: 'at.billa', ios: '1');
const joe = RetailerApp(name: 'jö', android: 'at.joe', ios: '2');
const billa = Retailer(
  chain: 'billa',
  country: 'AT',
  name: 'BILLA',
  apps: [billaApp, joe],
);

/// A registry with German chains, two of them „Aldi“, and Austria's.
void seedRetailers(FakeRepository repo) => repo
  ..retailers = const [lidl, rewe, aldiNord, aldiSued, hofer, billa]
  ..aliases = const {
    (chain: 'aldi-nord', country: 'DE'): ['aldi'],
    (chain: 'aldi-sued', country: 'DE'): ['aldi', 'aldi süd'],
    (chain: 'aldi-sued', country: 'AT'): ['hofer'],
  };
