/**
 * The app clients: the real Flutter debug build with the Marionette binding,
 * on a headless Linux desktop (Xvfb) or an Android emulator.
 */

import { type Ctx, FgError, type Shell } from './core.ts';
import {
  ANDROID_ABI,
  APP_ID,
  type ClientName,
  type ClientState,
  ENTRYPOINT,
  type Instance,
  type State,
  type SurfaceKind,
} from './instance.ts';
import { mustRun, type StackEnv } from './stack.ts';
import { Marionette } from './marionette.ts';

/** The Linux runner's window (app/linux/runner/my_application.cc): a phone in portrait. */
export const SCREEN = { width: 412, height: 892 };

const LINUX_BUNDLE = 'app/build/linux/x64/debug/bundle/family_groceries';
const APK = 'app/build/app/outputs/flutter-apk/app-debug.apk';
const VM_SERVICE_LINE = /The Dart VM service is listening on (http:\/\/127\.0\.0\.1:(\d+)\/[^\s]*)/;

export function defines(inst: Instance, env: StackEnv, surface: SurfaceKind): string[] {
  // The emulator reaches the host's loopback as 10.0.2.2.
  const host = surface === 'android' ? 'http://10.0.2.2' : 'http://127.0.0.1';
  const port = new URL(env.apiUrl).port || `${inst.prefix}21`;
  return [
    `--dart-define=SUPABASE_URL=${host}:${port}`,
    `--dart-define=SUPABASE_PUBLISHABLE_KEY=${env.publishableKey}`,
    // Debug builds otherwise post Flutter errors only to the VM service, so `fg logs` would miss them.
    '--dart-define=flutter.inspector.structuredErrors=false',
    // Job 25: the app's fake store (features/purchases.md); FG_FAKE_STORE picks its scenario.
    `--dart-define=FAKE_STORE=${Deno.env.get('FG_FAKE_STORE') || 'ok'}`,
    // Job 44: analytics against a local stand-in (cli/posthog_collector.ts, features/analytics.md).
    ...posthogDefines(Deno.env.get('FG_POSTHOG_HOST')),
    // Job 50: the integration lock's settings card (features/purchases.md), the flag
    // premium-gate-integrations since job 328; the server switch too.
    ...(Deno.env.get('FG_INTEGRATION_LOCK') === '1' ? ['--dart-define=FLAGS_ON=premium-gate-integrations'] : []),
  ];
}

/** A stand-in project key and [host], only one on this machine: the app accepts no other stand-in. */
export function posthogDefines(host: string | undefined): string[] {
  if (!host) return [];
  if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(host)) {
    throw new Error(`FG_POSTHOG_HOST is ${host}: only http://127.0.0.1:<port> (cli/posthog_collector.ts)`);
  }
  return ['--dart-define=POSTHOG_PROJECT_API_KEY=phc_fg_local_collector', `--dart-define=POSTHOG_HOST=${host}`];
}

/** Identifies the app source plus build settings, so doctor can tell a stale build from the current one. */
export async function fingerprint(sh: Shell, inst: Instance, surface: SurfaceKind | 'web', flags: string[]): Promise<string> {
  const git = (args: string[]) => sh.run(['git', '-C', inst.repo, ...args]).then((r) => r.stdout);
  const parts = [
    await git(['rev-parse', 'HEAD:app']),
    await git(['diff', 'HEAD', '--', 'app']),
    await git(['ls-files', '--others', '--exclude-standard', '--', 'app']),
    surface,
    ...flags,
  ];
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(parts.join('\0')));
  return Array.from(new Uint8Array(digest).slice(0, 8), (b) => b.toString(16).padStart(2, '0')).join('');
}

export async function build(ctx: Ctx, inst: Instance, state: State, surface: SurfaceKind, env: StackEnv, force: boolean): Promise<string> {
  const flags = defines(inst, env, surface);
  const fp = await fingerprint(ctx.sh, inst, surface, flags);
  const artifact = `${inst.repo}/${surface === 'linux' ? LINUX_BUNDLE : APK}`;
  if (!force && state.builds[surface] === fp && (await ctx.sh.exists(artifact))) return fp;
  const cmd = surface === 'linux'
    ? ['flutter', 'build', 'linux', '--debug', '-t', ENTRYPOINT, ...flags]
    : ['flutter', 'build', 'apk', '--debug', '--target-platform', ANDROID_ABI.target, '-t', ENTRYPOINT, ...flags];
  await ctx.act(`build the ${surface} debug app (${cmd.join(' ')})`, async () => {
    ctx.log(`building the ${surface} debug app (about 30 s warm, a few minutes cold)`);
    await mustRun(ctx.sh, cmd, { cwd: `${inst.repo}/app`, timeoutMs: 900_000 });
    state.builds[surface] = fp;
  });
  return fp;
}

/** X display per client: peter :<prefix>1, lea :<prefix>2, any other user the first free of :<prefix>3..9. */
export function displayFor(inst: Instance, state: State, name: ClientName): number {
  if (name === 'peter' || name === 'lea') return Number(`${inst.prefix}${name === 'peter' ? 1 : 2}`);
  const own = state.clients[name]?.display;
  if (own) return own;
  const taken = new Set(Object.values(state.clients).map((c) => c?.display));
  for (let slot = 3; slot <= 9; slot++) {
    const display = Number(`${inst.prefix}${slot}`);
    if (!taken.has(display)) return display;
  }
  throw new FgError('display_taken', `All X displays of block ${inst.prefix} are in use.`, '`fg down` some clients first.');
}

export async function startLinux(ctx: Ctx, inst: Instance, state: State, name: ClientName, fp: string): Promise<ClientState | undefined> {
  const display = displayFor(inst, state, name);
  const dir = `${inst.stateDir}/clients/${name}`;
  const socket = `/tmp/.X11-unix/X${display}`;
  const lock = `/tmp/.X${display}-lock`;
  const holder = (await ctx.sh.exists(lock)) ? Number((await ctx.sh.readText(lock)).trim()) : 0;
  // Xvfb clears a lock left by a dead server itself; a live holder is someone else's run.
  if (holder && (await ctx.sh.alive(holder, 'Xvfb'))) {
    throw new FgError(
      'display_taken',
      `X display :${display} is already in use (Xvfb pid ${holder}), but not by a client this instance tracks.`,
      `Another run owns it. Pick another port block (FG_PORT_PREFIX) or stop that run with its own \`fg down\`.`,
    );
  }
  return await ctx.act(`start Xvfb :${display} and the app as ${name}`, async () => {
    await ctx.sh.mkdir(dir);
    const xvfbPid = await ctx.sh.spawn(
      ['Xvfb', `:${display}`, '-screen', '0', `${SCREEN.width}x${SCREEN.height}x24`, '-nolisten', 'tcp'],
      { log: `${dir}/xvfb.log` },
    );
    const ready = async () =>
      (await ctx.sh.exists(socket)) && (await ctx.sh.exists(lock)) && Number((await ctx.sh.readText(lock)).trim()) === xvfbPid;
    await waitFor(
      ctx.sh,
      ready,
      15_000,
      () => new FgError('xvfb_failed', `Xvfb :${display} did not start.`, `Read ${dir}/xvfb.log; is Xvfb installed (\`fg setup\`)?`),
    );
    const app = await launchLinuxApp(ctx, inst, name, display, false);
    return { surface: 'linux', ...app, fingerprint: fp, display, xvfbPid, startedAt: new Date().toISOString() } satisfies ClientState;
  });
}

/** Starts the app binary on a running display; keepSession reuses the client's stored login. */
async function launchLinuxApp(ctx: Ctx, inst: Instance, name: ClientName, display: number | undefined, keepSession: boolean) {
  const dir = `${inst.stateDir}/clients/${name}`;
  const log = `${dir}/app.log`;
  if (!keepSession) {
    // A new client starts signed out: a session kept from before a reseed points at deleted users.
    for (const sub of ['data', 'config', 'cache']) await ctx.sh.remove(`${dir}/${sub}`);
  }
  await ctx.sh.writeText(log, '');
  // Line-buffered: with a file as stdout the app's output would only appear in large blocks.
  const pid = await ctx.sh.spawn(['stdbuf', '-oL', '-eL', `${inst.repo}/${LINUX_BUNDLE}`], {
    log,
    env: {
      DISPLAY: `:${display}`,
      // Each client keeps its own session storage (shared_preferences).
      XDG_DATA_HOME: `${dir}/data`,
      XDG_CONFIG_HOME: `${dir}/config`,
      XDG_CACHE_HOME: `${dir}/cache`,
      NO_AT_BRIDGE: '1',
    },
  });
  const vm = await vmService(ctx.sh, () => ctx.sh.readText(log), log);
  return { pid, marker: 'family_groceries', vmUri: vm.ws, log };
}

/** Quits and reopens the app like a user would, keeping its stored session. */
export async function restartClient(ctx: Ctx, inst: Instance, name: ClientName, client: ClientState): Promise<ClientState | undefined> {
  if (client.surface === 'android') {
    await ctx.act(
      `force-stop ${APP_ID} on ${inst.serial}`,
      () => mustRun(ctx.sh, ['adb', '-s', inst.serial, 'shell', 'am', 'force-stop', APP_ID]),
    );
    if (client.hostPort) await ctx.sh.run(['adb', '-s', inst.serial, 'forward', '--remove', `tcp:${client.hostPort}`]);
    return await startAndroid(ctx, inst, client.fingerprint, false);
  }
  return await ctx.act(`quit and reopen the ${name} app (pid ${client.pid}), keeping its session`, async () => {
    await terminate(ctx.sh, client.pid, client.marker);
    const app = await launchLinuxApp(ctx, inst, name, client.display, true);
    return { ...client, ...app, startedAt: new Date().toISOString() } satisfies ClientState;
  });
}

async function vmService(sh: Shell, read: () => Promise<string>, log: string): Promise<{ ws: string; port: number }> {
  const found = await waitForValue(
    sh,
    async () => (await read()).match(VM_SERVICE_LINE) ?? undefined,
    90_000,
    () =>
      new FgError(
        'app_start_failed',
        'The app did not report a Dart VM service within 90 s.',
        `Read ${log}; a debug build is required (the CLI builds one with \`fg up --rebuild\`).`,
      ),
  );
  const [, http = '', port] = found;
  return { ws: `${http.replace('http://', 'ws://').replace(/\/?$/, '/')}ws`, port: Number(port) };
}

export async function waitForMarionette(sh: Shell, uri: string, timeoutMs = 60_000): Promise<void> {
  const m = new Marionette(sh, uri);
  await waitFor(
    sh,
    () => m.elements().then(() => true, () => false),
    timeoutMs,
    () =>
      new FgError(
        'marionette_unreachable',
        `Marionette does not answer at ${uri}.`,
        'Is the app built from test_driver/main_marionette.dart? Run `fg up --rebuild`.',
      ),
  );
}

export async function ensureEmulator(ctx: Ctx, inst: Instance, state: State): Promise<void> {
  if (inst.kvmBroken) {
    throw new FgError(
      'kvm_broken',
      `This box cannot run the Android emulator: ${inst.kvmBroken}`,
      `Use the linux surface (FG_SURFACE=linux, the default here). Delete ${inst.kvmMarker} only after KVM is fixed.`,
    );
  }
  const online = await ctx.sh.run(['adb', '-s', inst.serial, 'get-state']);
  if (online.stdout.trim() === 'device') return;
  const access = await ctx.sh.run(['test', '-r', '/dev/kvm', '-a', '-w', '/dev/kvm']);
  if (access.code !== 0) {
    throw new FgError(
      'kvm_denied',
      'This user cannot open /dev/kvm.',
      'Run `fg setup --surface android` (adds you to the kvm group and fixes /dev/kvm permissions).',
    );
  }
  const avds = await ctx.sh.run(['emulator', '-list-avds']);
  if (!avds.stdout.split('\n').includes(inst.avd)) {
    throw new FgError(
      'no_avd',
      `AVD ${inst.avd} does not exist.`,
      'Run `fg setup --surface android` to install the system image and create it.',
    );
  }
  await ctx.act(`boot emulator ${inst.serial} (AVD ${inst.avd}, headless, 2 GB)`, async () => {
    const pid = await ctx.sh.spawn(
      [
        'emulator',
        '-avd',
        inst.avd,
        '-port',
        String(inst.emuPort),
        '-no-window',
        '-no-audio',
        '-no-boot-anim',
        '-gpu',
        'swiftshader_indirect',
        '-memory',
        '2048',
        '-no-snapshot-save',
      ],
      { log: `${inst.stateDir}/emulator.log` },
    );
    state.emulator = { pid, marker: inst.avd };
    await waitFor(
      ctx.sh,
      async () => (await ctx.sh.run(['adb', '-s', inst.serial, 'shell', 'getprop', 'sys.boot_completed'])).stdout.trim() === '1',
      300_000,
      () =>
        new FgError(
          'emulator_boot_failed',
          `${inst.serial} did not finish booting in 5 minutes.`,
          `Read ${inst.stateDir}/emulator.log; then \`fg down\` and retry.`,
        ),
    );
  });
}

export async function startAndroid(ctx: Ctx, inst: Instance, fp: string, install = true): Promise<ClientState | undefined> {
  const adb = (...args: string[]) => ['adb', '-s', inst.serial, ...args];
  const log = `${inst.stateDir}/clients/peter/logcat.txt`;
  return await ctx.act(`install and launch ${APP_ID} on ${inst.serial}`, async () => {
    await ctx.sh.mkdir(`${inst.stateDir}/clients/peter`);
    if (install) await mustRun(ctx.sh, adb('install', '-r', `${inst.repo}/${APK}`), { timeoutMs: 180_000 });
    await mustRun(ctx.sh, adb('logcat', '-c'));
    await mustRun(ctx.sh, adb('shell', 'am', 'start', '-W', '-n', `${APP_ID}/.MainActivity`));
    const vm = await vmService(ctx.sh, async () => {
      const out = (await ctx.sh.run(adb('logcat', '-d', '-s', 'flutter'))).stdout;
      await ctx.sh.writeText(log, out);
      return out;
    }, log);
    const fwd = await mustRun(ctx.sh, adb('forward', 'tcp:0', `tcp:${vm.port}`));
    const hostPort = Number(fwd.stdout.trim());
    const pid = Number((await ctx.sh.run(adb('shell', 'pidof', APP_ID))).stdout.trim()) || 0;
    const ws = vm.ws.replace(`:${vm.port}/`, `:${hostPort}/`);
    return {
      surface: 'android',
      pid,
      marker: APP_ID,
      vmUri: ws,
      log,
      fingerprint: fp,
      hostPort,
      startedAt: new Date().toISOString(),
    } satisfies ClientState;
  });
}

export async function stopClient(ctx: Ctx, inst: Instance, name: ClientName, client: ClientState): Promise<void> {
  if (client.surface === 'android') {
    await ctx.act(`stop ${APP_ID} on ${inst.serial}`, async () => {
      await ctx.sh.run(['adb', '-s', inst.serial, 'shell', 'am', 'force-stop', APP_ID]);
      if (client.hostPort) await ctx.sh.run(['adb', '-s', inst.serial, 'forward', '--remove', `tcp:${client.hostPort}`]);
    });
    return;
  }
  await ctx.act(`stop the ${name} app (pid ${client.pid}) and Xvfb :${client.display} (pid ${client.xvfbPid})`, async () => {
    await terminate(ctx.sh, client.pid, client.marker);
    if (client.xvfbPid) await terminate(ctx.sh, client.xvfbPid, 'Xvfb');
  });
}

/** SIGTERM, then SIGKILL after 10 s; returns once the process is gone, so its display or port is free. */
async function terminate(sh: Shell, pid: number, marker: string): Promise<void> {
  if (!(await sh.alive(pid, marker))) return;
  await sh.kill(pid, 'SIGTERM');
  for (let i = 0; i < 40 && (await sh.alive(pid, marker)); i++) await sh.sleep(250);
  if (await sh.alive(pid, marker)) await sh.kill(pid, 'SIGKILL');
  for (let i = 0; i < 20 && (await sh.alive(pid, marker)); i++) await sh.sleep(250);
}

export async function clientAlive(sh: Shell, inst: Instance, client: ClientState): Promise<boolean> {
  if (client.surface === 'android') {
    return (await sh.run(['adb', '-s', inst.serial, 'shell', 'pidof', APP_ID])).stdout.trim() !== '';
  }
  return await sh.alive(client.pid, client.marker);
}

export async function waitFor(sh: Shell, check: () => Promise<boolean>, timeoutMs: number, onTimeout: () => FgError): Promise<void> {
  await waitForValue(sh, async () => ((await check()) ? true : undefined), timeoutMs, onTimeout);
}

/** Polls every 500 ms until `probe` returns a value, and returns it. */
export async function waitForValue<T>(
  sh: Shell,
  probe: () => Promise<T | undefined>,
  timeoutMs: number,
  onTimeout: () => FgError,
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await probe();
    if (value !== undefined) return value;
    await sh.sleep(500);
  }
  throw onTimeout();
}
