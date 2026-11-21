// Every place the real More tab leads to today (app/lib/more/more_screen.dart, `_Item.groups`, as an iPhone shows it
// with trip mode on), plus History, Edit (today's „Anpassen“: the list's stores) and switching lists. Each option says
// where each one goes; render.js draws the rows from this and verify.mjs checks that every place is drawn and that the
// docs' taps table equals `taps()`.
export const dests = {
  history: { icon: 'history', key: 'tabHistory' },
  edit: { icon: 'tune', key: 'listEdit' },
  trip: { icon: 'shopping_cart_outlined', key: 'shopStartByHand' },
  account: { icon: 'manage_accounts_outlined', key: 'account' },
  access: { icon: 'key_outlined', key: 'accessTitle' },
  settings: { icon: 'settings_outlined', key: 'settingsTitle' },
  usage: { icon: 'insights_outlined', key: 'analyticsSection' },
  tips: { icon: 'lightbulb_outline', key: 'hintsTitle' },
  feedback: { icon: 'feedback_outlined', key: 'feedbackHubRow' },
  rate: { icon: 'star_outline', key: 'rateApp' },
  help: { icon: 'help_outline', key: 'helpRow' },
  imprint: { icon: 'info_outline', key: 'imprint' },
  privacy: { icon: 'privacy_tip_outlined', key: 'privacyPolicy' },
  terms: { icon: 'article_outlined', key: 'premiumTermsLink' },
  licenses: { icon: 'description_outlined', key: 'licenses' },
  signout: { icon: 'logout', key: 'signOut' },
};
// More's groups, top to bottom (Premium sits in Account; the household rows left More with list-declutter).
export const moreGroups = [['trip'], ['account'], ['access'], ['settings', 'usage'], ['tips', 'feedback', 'rate', 'help'], ['imprint', 'privacy', 'terms', 'licenses'], ['signout']];
export const legal = ['imprint', 'privacy', 'terms', 'licenses'];
export const moreIds = moreGroups.flat();

// The steps from the list to a place, one per tap, by the option's menu (options.js `nav`).
const tabsWithStores = ['docked', 'fab'];
export const pathOf = (o, dest) => {
  if (dest === 'list') return ['panel', 'avatars', 'docked', 'textTabs'].includes(o.nav) ? ['title', 'list'] : o.nav === 'dock' ? ['menu', 'list'] : o.nav === 'drawer' ? ['drawer', 'list'] : ['switcher', 'list'];
  switch (o.nav) {
    case 'float':
    case 'split':
    case 'textTabs':
    case 'docked':
    case 'fab':
      if (dest === 'history') return ['History tab'];
      if (dest === 'edit') return tabsWithStores.includes(o.nav) ? ['Stores tab'] : ['Edit'];
      return ['More tab', dest];
    case 'dock':
      return dest === 'edit' ? ['Edit'] : ['menu', dest];
    case 'panel':
      return dest === 'edit' ? ['Edit'] : ['title', dest];
    case 'drawer':
      return dest === 'edit' ? ['Edit'] : ['drawer', dest];
    case 'avatars':
      if (dest === 'history') return ['History segment'];
      return ['avatars', dest];
    case 'storeTabs':
      if (['history', 'edit', 'trip', 'settings', ...legal].includes(dest)) return ['•••', dest];
      return ['•••', 'More', dest];
    default:
      throw new Error(`nav ${o.nav}`);
  }
};
export const taps = (o, dest) => pathOf(o, dest).length;
// The places a menu (not a tab bar) holds, in order; `more` adds the More page's own rows.
export const menuDests = (o) => Object.keys(dests).filter((d) => pathOf(o, d)[0] !== 'Edit' && pathOf(o, d).length === 2 && !pathOf(o, d)[0].endsWith('tab'));
export const morePageDests = (o) => Object.keys(dests).filter((d) => { const p = pathOf(o, d); return p[0] === 'More tab' || p[1] === 'More'; });
