/**
 * Films the real Hummlist Linux app for the demo videos.
 *
 * Each client is the profile build on its own Xvfb display at 3x (GDK_SCALE=3), signed in
 * through the real login screen. Input is real X input (xdotool): pointer presses and key
 * strokes reach GTK and Flutter like a user's would. Marionette only reads where widgets are.
 * One ffmpeg process grabs every display, so all clients share one clock, and every input is
 * logged on that clock for the touch dots in the compositions.
 */

import { parseElements, type Bounds, type Element } from '../../../.cursor/skills/verify-family-groceries/cli/marionette.ts';

export const SCALE = Number(Deno.env.get('CAPTURE_SCALE') ?? 3);
export const LOGICAL = { width: 412, height: 892 };
export const PHYSICAL = { width: LOGICAL.width * SCALE, height: LOGICAL.height * SCALE };

export interface ClientSpec {
  name: string;
  email: string;
  password: string;
  lang: 'de' | 'en';
  display: number;
}

export interface Client extends ClientSpec {
  dir: string;
  xvfb: Deno.ChildProcess;
  app: Deno.ChildProcess;
  vmUri: string;
}

/** One input or note on the recording's clock, in logical app pixels. */
export interface CaptureEvent {
  t: number;
  client: string;
  kind: 'press' | 'release' | 'key' | 'type' | 'mark';
  x?: number;
  y?: number;
  text?: string;
}

const XDOTOOL = Deno.env.get('XDOTOOL') ?? `${Deno.env.get('HOME')}/tools/xdo/xdotool`;

async function run(cmd: string[], env: Record<string, string> = {}): Promise<string> {
  const out = await new Deno.Command(cmd[0], { args: cmd.slice(1), env, stdout: 'piped', stderr: 'piped' }).output();
  const text = new TextDecoder().decode(out.stdout);
  if (!out.success) throw new Error(`${cmd.join(' ')} failed: ${new TextDecoder().decode(out.stderr)}${text}`);
  return text;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function until<T>(what: string, probe: () => Promise<T | undefined>, timeoutMs = 30_000): Promise<T> {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    const v = await probe().catch(() => undefined);
    if (v !== undefined) return v;
    await sleep(150);
  }
  throw new Error(`timed out after ${timeoutMs} ms waiting for ${what}`);
}

/**
 * The engine's software renderer with Skia. Under Xvfb the OpenGL path (llvmpipe, no DRI3)
 * presents a frame only when an X event arrives, so animations showed up as one or two frames;
 * the software path presents every frame at 30 fps. Impeller cannot draw to it, hence Skia.
 * CAPTURE_ENGINE_SWITCHES (comma-separated) replaces the switches.
 */
function engineEnv(): Record<string, string> {
  const switches = (Deno.env.get('CAPTURE_ENGINE_SWITCHES') ?? 'enable-impeller=false').split(',').filter(Boolean);
  const env: Record<string, string> = { FLUTTER_LINUX_RENDERER: Deno.env.get('FLUTTER_LINUX_RENDERER') ?? 'software' };
  if (switches.length) env.FLUTTER_ENGINE_SWITCHES = String(switches.length);
  switches.forEach((sw, i) => (env[`FLUTTER_ENGINE_SWITCH_${i + 1}`] = sw));
  return env;
}

export async function launch(spec: ClientSpec, bundle: string, root: string): Promise<Client> {
  const dir = `${root}/${spec.name}`;
  await Deno.remove(dir, { recursive: true }).catch(() => {});
  await Deno.mkdir(dir, { recursive: true });
  const xvfb = new Deno.Command('Xvfb', {
    args: [`:${spec.display}`, '-screen', '0', `${PHYSICAL.width}x${PHYSICAL.height}x24`, '-nolisten', 'tcp'],
    stdout: 'null',
    stderr: 'null',
  }).spawn();
  await until(`Xvfb :${spec.display}`, async () => (await Deno.stat(`/tmp/.X11-unix/X${spec.display}`)) ? true : undefined);
  const log = await Deno.open(`${dir}/app.log`, { write: true, create: true, truncate: true });
  const locale = spec.lang === 'de' ? 'de_DE.UTF-8' : 'en_US.UTF-8';
  const app = new Deno.Command(bundle, {
    env: {
      DISPLAY: `:${spec.display}`,
      GDK_SCALE: String(SCALE),
      LANG: locale,
      LANGUAGE: spec.lang,
      LC_ALL: locale,
      XDG_DATA_HOME: `${dir}/data`,
      XDG_CONFIG_HOME: `${dir}/config`,
      XDG_CACHE_HOME: `${dir}/cache`,
      NO_AT_BRIDGE: '1',
      ...engineEnv(),
    },
    stdout: 'piped',
    stderr: 'piped',
  }).spawn();
  let logText = '';
  const pump = async (s: ReadableStream<Uint8Array>) => {
    for await (const chunk of s) {
      logText += new TextDecoder().decode(chunk);
      await log.write(chunk);
    }
  };
  pump(app.stdout);
  pump(app.stderr);
  const vm = await until('the Dart VM service', async () => {
    const m = logText.match(/The Dart VM service is listening on http:\/\/(127\.0\.0\.1:\d+\/[^\s]*)/);
    return m ? `ws://${m[1].replace(/\/?$/, '/')}ws` : undefined;
  }, 90_000);
  const client: Client = { ...spec, dir, xvfb, app, vmUri: vm };
  await until('Marionette', () => elements(client).then((e) => (e.length ? true : undefined)), 60_000);
  return client;
}

export async function elements(c: Client): Promise<Element[]> {
  return parseElements(await run(['marionette', '--uri', c.vmUri, 'get-interactive-elements']));
}

export type Target = { text: string } | { key: string } | { type: string } | { x: number; y: number };

function matches(e: Element, t: Target): boolean {
  if ('text' in t) {
    const want = t.text.normalize('NFC');
    return e.text?.normalize('NFC') === want || e.label?.normalize('NFC') === want;
  }
  if ('key' in t) return e.key === t.key;
  if ('type' in t) return e.type === t.type;
  return false;
}

/** Logical bounds of the first visible element matching the target. */
export async function find(c: Client, t: Target, timeoutMs = 15_000, anywhere = false): Promise<Bounds> {
  if ('x' in t) return { x: t.x, y: t.y, width: 0, height: 0 };
  return await until(`${JSON.stringify(t)} on ${c.name}`, async () => {
    const hit = (await elements(c)).find((e) => matches(e, t) && e.bounds && (anywhere || (e.bounds.y >= 0 &&
      e.bounds.y + e.bounds.height <= LOGICAL.height)));
    return hit?.bounds;
  }, timeoutMs);
}

export async function gone(c: Client, t: Target, timeoutMs = 15_000): Promise<void> {
  await until(`${JSON.stringify(t)} gone on ${c.name}`, async () =>
    (await elements(c)).some((e) => matches(e, t)) ? undefined : true, timeoutMs);
}

const xdo = (c: Client, args: string[]) => run([XDOTOOL, ...args], { DISPLAY: `:${c.display}` });

export class Session {
  events: CaptureEvent[] = [];
  t0 = 0;
  constructor(readonly clients: Client[]) {}

  private now(): number {
    return this.t0 ? Math.round(performance.timeOrigin + performance.now() - this.t0) : -1;
  }

  mark(client: string, text: string) {
    this.events.push({ t: this.now(), client, kind: 'mark', text });
  }

  /** A finger tap at a point inside the target: press, hold like a thumb, release. */
  async tap(c: Client, t: Target, opts: { dx?: number; dy?: number; holdMs?: number } = {}) {
    const b = await find(c, t);
    const x = Math.round(b.x + (opts.dx ?? b.width / 2));
    const y = Math.round(b.y + (opts.dy ?? b.height / 2));
    await xdo(c, ['mousemove', String(x * SCALE), String(y * SCALE)]);
    this.events.push({ t: this.now(), client: c.name, kind: 'press', x, y });
    await xdo(c, ['mousedown', '1']);
    await sleep(opts.holdMs ?? 90);
    await xdo(c, ['mouseup', '1']);
    this.events.push({ t: this.now(), client: c.name, kind: 'release', x, y });
    await xdo(c, ['mousemove', String(PHYSICAL.width / 2), '20']);
  }

  /** Types like a person: one real key stroke per character. */
  async type(c: Client, text: string, delayMs = 85) {
    this.events.push({ t: this.now(), client: c.name, kind: 'type', text });
    await xdo(c, ['type', '--delay', String(delayMs), text]);
  }

  /** Mouse-wheel scrolls (off the record, before filming) until `t` exists with its top at or above `top`. */
  async scrollUntil(c: Client, t: Target, top: number) {
    await xdo(c, ['mousemove', String(PHYSICAL.width / 2), String(PHYSICAL.height / 2)]);
    for (let i = 0; i < 80; i++) {
      const hit = (await elements(c)).find((e) => matches(e, t) && e.bounds);
      if (hit && hit.bounds!.y <= top) break;
      await xdo(c, ['click', '5']);
      await sleep(250);
    }
    console.error(`[scroll] ${c.name}: ${JSON.stringify(t)} at y ${(await find(c, t, 15_000, true)).y}`);
    await xdo(c, ['mousemove', String(PHYSICAL.width / 2), '20']);
  }

  async key(c: Client, key: string) {
    this.events.push({ t: this.now(), client: c.name, kind: 'key', text: key });
    await xdo(c, ['key', key]);
  }
}

/** Signs in through the real login screen; not filmed, so the fields are filled by Marionette. */
export async function login(c: Client) {
  await find(c, { key: 'login-email' }, 60_000);
  await run(['marionette', '--uri', c.vmUri, 'enter-text', '--key', 'login-email', '--input', c.email]);
  await run(['marionette', '--uri', c.vmUri, 'enter-text', '--key', 'login-password', '--input', c.password]);
  await run(['marionette', '--uri', c.vmUri, 'tap', '--type', 'FilledButton']);
  await find(c, { key: 'add-item-field' }, 60_000);
  // First-run hint above the list: dismissed off camera, as a returning user has.
  if ((await elements(c)).some((e) => e.key === 'list-hint-dismiss')) {
    await run(['marionette', '--uri', c.vmUri, 'tap', '--key', 'list-hint-dismiss']);
    await gone(c, { key: 'list-hint-dismiss' });
  }
  await xdo(c, ['mousemove', String(PHYSICAL.width / 2), '20']);
}

export interface Recording {
  stop(): Promise<void>;
}

/**
 * Starts one ffmpeg grabbing every client's display at 30 fps, near-lossless, without the
 * pointer. Sets the session clock to the grab's own start time (x11grab stamps frames with the
 * wall clock and ffmpeg prints the first one as `start:`), so event times match video times.
 */
export async function record(s: Session, outDir: string): Promise<Recording> {
  const args = ['-y', '-loglevel', 'info'];
  for (const c of s.clients) {
    args.push('-f', 'x11grab', '-draw_mouse', '0', '-framerate', '30', '-video_size',
      `${PHYSICAL.width}x${PHYSICAL.height}`, '-i', `:${c.display}`);
  }
  s.clients.forEach((c, i) => {
    args.push('-map', `${i}:v`, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '10', '-pix_fmt', 'yuv444p',
      `${outDir}/${c.name}.mkv`);
  });
  const ff = new Deno.Command('ffmpeg', { args, stdin: 'piped', stdout: 'null', stderr: 'piped' }).spawn();
  let err = '';
  const starts = new Map<number, number>();
  (async () => {
    for await (const chunk of ff.stderr) {
      if (err.length < 200_000) err += new TextDecoder().decode(chunk);
      // "Input #1, x11grab, from ':57791':\n  Duration: N/A, start: 1761973496.512345, ..."
      for (const m of err.matchAll(/Input #(\d+), x11grab[^\n]*\n\s*Duration: [^,]*, start: (\d+\.\d+)/g)) {
        starts.set(Number(m[1]), Number(m[2]) * 1000);
      }
    }
  })();
  const startsAt = await until('ffmpeg x11grab start times', async () =>
    starts.size >= s.clients.length ? s.clients.map((_, i) => starts.get(i)!) : undefined, 15_000);
  // Every output starts at its input's first frame; the latest input start is the common zero.
  s.t0 = Math.max(...startsAt);
  const offsets = Object.fromEntries(s.clients.map((c, i) => [c.name, Math.round(s.t0 - startsAt[i])]));
  await Deno.writeTextFile(`${outDir}/offsets.json`, JSON.stringify(offsets));
  return {
    async stop() {
      const w = ff.stdin.getWriter();
      await w.write(new TextEncoder().encode('q'));
      await w.close();
      await ff.status;
    },
  };
}

export async function shutdown(clients: Client[]) {
  for (const c of clients) {
    try { c.app.kill('SIGTERM'); } catch { /* already gone */ }
    try { c.xvfb.kill('SIGTERM'); } catch { /* already gone */ }
  }
  await sleep(500);
}

export { sleep, until };
