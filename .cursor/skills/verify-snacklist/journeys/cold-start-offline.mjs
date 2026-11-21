// Feature offline, sub-feature offline-start (job 325): the app opened again on a working network
// never shows „Offline“. Signs in, closes the tab, waits (--wait seconds; past the stack's
// jwt_expiry to start with an expired access token), opens the app again in the same browser
// profile and watches the sync indicator and the realtime joins for --watch seconds.
// --os-none makes the browser's network say none on a working network, as iOS's path monitor does
// (`stays`: until the end; `flips`: an online event --flip-after ms, default 30, after the app
// showed; 1000 plays a cellular start). --slow-channel
// holds every realtime frame from the server for that many ms, as a phone's slower join does.
// --airplane opens the app with the browser's network saying none and every request to the stack
// failing as disconnected (the page itself still loads): then „Offline“ has to show within 3 s.
// --radio-down <ms> plays a cellular radio waking (job 325 review 1): every request and socket to
// the stack fails as disconnected until <ms> after the first one, then the network is back and,
// with --os-none, the browser fires `online`. --no-online keeps the browser's network saying none
// and fires no `online` when it is back, as iOS's monitor that stays at none (job 325 review 2).
//
//   node journeys/cold-start-offline.mjs <evidence dir> [--wait 0] [--watch 25] [--starts 1] [--os-none stays|flips] [--flip-after ms] [--slow-channel ms] [--airplane] [--radio-down ms] [--no-online]
import process from 'node:process';
import { capture, instance, logger, member, openApp, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const wait = Number(opt('wait', '0'));
const watch = Number(opt('watch', '25'));
const starts = Number(opt('starts', '1'));
const airplaneFlag = process.argv.includes('--airplane');
const osNone = opt('os-none', airplaneFlag ? 'stays' : null);
const slowChannel = Number(opt('slow-channel', '0'));
const flipAfter = Number(opt('flip-after', '30'));
const airplane = airplaneFlag;
const radioDown = Number(opt('radio-down', '0'));
const noOnline = process.argv.includes('--no-online');
if (!dir) throw new Error('usage: cold-start-offline.mjs <evidence dir> [--wait s] [--watch s] [--starts n]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const { browser, context, page, L, errors } = await openApp(inst, { lang: 'de', videoDir: dir });
let failed = null;
try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} on ${inst.webUrl}`);
  await page.close();
  for (let start = 1; start <= starts; start++) {
    log(`start ${start}: tab closed, waiting ${wait} s`);
    await new Promise((r) => setTimeout(r, wait * 1000));
    const tab = await context.newPage();
    if (airplane) {
      const api = new URL(inst.apiUrl);
      await tab.route((url) => url.host === api.host, (route) => route.abort('internetdisconnected'));
      await tab.routeWebSocket((url) => url.host === api.host, (ws) => ws.close());
    }
    const t0 = Date.now();
    const at = () => `${((Date.now() - t0) / 1000).toFixed(1)} s`;
    tab.on('pageerror', (e) => errors.push(e.message));
    if (osNone) {
      await tab.addInitScript(({ flips, after }) => {
        globalThis.__online = false;
        Object.defineProperty(Navigator.prototype, 'onLine', { configurable: true, get: () => globalThis.__online });
        if (flips) {
          const poll = setInterval(() => {
            if (!document.querySelector('flt-semantics-host, flutter-view')) return;
            clearInterval(poll);
            setTimeout(() => {
              globalThis.__online = true;
              globalThis.dispatchEvent(new Event('online'));
            }, after);
          }, 10);
        }
      }, { flips: osNone === 'flips', after: flipAfter });
      log(`  the browser's network says none (${osNone})`);
    }
    if (radioDown) {
      const api = new URL(inst.apiUrl);
      let up = false;
      let firstFail = null;
      const bringUp = () => {
        up = true;
        log(`  ${at()} network up`);
        if (osNone && !noOnline) {
          tab.evaluate(() => {
            globalThis.__online = true;
            globalThis.dispatchEvent(new Event('online'));
          }).catch(() => {});
        }
      };
      const noteFail = () => {
        if (firstFail !== null) return;
        firstFail = Date.now();
        log(`  ${at()} first request failed`);
        setTimeout(bringUp, radioDown);
      };
      await tab.route((url) => url.host === api.host, (route) => {
        if (up) return route.continue();
        noteFail();
        return route.abort('internetdisconnected');
      });
      await tab.routeWebSocket((url) => url.host === api.host, (ws) => {
        if (!up) {
          noteFail();
          ws.close();
          return;
        }
        const server = ws.connectToServer();
        ws.onMessage((message) => server.send(message));
        server.onMessage((message) => ws.send(message));
      });
    }
    if (slowChannel) {
      await tab.routeWebSocket(/\/realtime\/v1\/websocket/, (ws) => {
        const server = ws.connectToServer();
        ws.onMessage((message) => server.send(message));
        server.onMessage((message) => setTimeout(() => ws.send(message), slowChannel));
      });
    }
    tab.on('response', (r) => {
      const url = r.url();
      if (url.includes('/auth/v1/token') || (url.includes('/rest/v1/items') && r.request().method() === 'GET')) {
        log(`  ${at()} ${r.request().method()} ${url.replace(inst.apiUrl ?? '', '').split('?')[0]} -> ${r.status()}`);
      }
    });
    tab.on('websocket', (ws) => {
      ws.on('framereceived', ({ payload }) => {
        const text = String(payload);
        if (/phx_reply|system/.test(text) && !/"heartbeat"|phoenix/.test(text)) {
          log(`  ${at()} realtime: ${text.slice(0, 220)}`);
        }
      });
    });
    await tab.goto('/');
    const offline = tab.getByRole('button', { name: new RegExp(`^${L('syncOffline')}:`) });
    let shown = 0;
    let first = null;
    let last = null;
    const end = Date.now() + watch * 1000;
    while (Date.now() < end) {
      if (await offline.count().catch(() => 0)) {
        shown++;
        last = at();
        if (first === null) {
          first = last;
          await capture(tab, dir, `start-${start}-offline`);
        }
      }
      await tab.waitForTimeout(50);
    }
    log(`start ${start}: „${L('syncOffline')}“ seen in ${shown} polls${first ? `, from ${first} to ${last}` : ''}`);
    await capture(tab, dir, `start-${start}-end`);
    if (airplane) {
      const seconds = first === null ? Infinity : Number.parseFloat(first);
      if (seconds > 3) failed ??= new Error(`start ${start} in airplane mode: offline ${first === null ? 'never showed' : `only at ${first}`}`);
    } else if (shown) {
      failed ??= new Error(`start ${start} showed offline on a working network (first at ${first})`);
    }
    await tab.close();
  }
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed ??= error;
} finally {
  await browser.close();
}
if (failed) {
  console.log(`FAIL: ${failed.message}`);
  process.exit(1);
}
console.log('PASS');
