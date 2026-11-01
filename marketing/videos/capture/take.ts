/**
 * One take of one video in one language: seed a fresh fixture run, start and sign in one app
 * per member, run the shot script while recording, then tear the run down again.
 *
 *   deno run -A marketing/videos/capture/take.ts <video> <de|en> [--keep]
 *
 * Writes marketing/videos/<video>/footage/<lang>/: one .mkv per member, events.json (every
 * input on the recording's clock) and take.json (offsets, measurements, run id). The footage is
 * not committed (.gitignore); rerun the take to recreate it.
 */

import * as d from './driver.ts';
import { shots } from './shots.ts';

const [video, lang] = Deno.args;
const keep = Deno.args.includes('--keep');
const shot = shots[video];
if (!shot || (lang !== 'de' && lang !== 'en')) {
  console.error(`usage: take.ts <${Object.keys(shots).join('|')}> <de|en> [--keep]`);
  Deno.exit(64);
}

const here = new URL('.', import.meta.url).pathname;
const repo = new URL('../../../', import.meta.url).pathname;
const fg = Deno.env.get('FG') ?? `${repo}scripts/fg`;
const bundle = Deno.env.get('CAPTURE_BUNDLE') ?? `${repo}app/build/linux/x64/profile/bundle/family_groceries`;
const prefix = Deno.env.get('FG_PORT_PREFIX') ?? '577';
const out = `${here}../${video}/footage/${lang}`;
const work = `/tmp/hummlist-capture-${prefix}/${video}-${lang}`;

async function fgJson(args: string[]) {
  const o = await new Deno.Command(fg, { args, stdout: 'piped', stderr: 'inherit' }).output();
  const doc = JSON.parse(new TextDecoder().decode(o.stdout));
  if (!doc.ok) throw new Error(`fg ${args.join(' ')}: ${JSON.stringify(doc.error)}`);
  return doc;
}

const stack = JSON.parse(new TextDecoder().decode((await new Deno.Command('supabase', {
  args: ['status', '-o', 'json', '--workdir', `${Deno.env.get('FG_STATE_DIR') ?? `${Deno.env.get('HOME')}/.cache/fg/${prefix}`}/stack`],
  stdout: 'piped', stderr: 'null',
}).output()).stdout).replace(/^[^{]*/, ''));
Deno.env.set('CAPTURE_API_URL', stack.API_URL);
Deno.env.set('CAPTURE_PUBLISHABLE_KEY', stack.PUBLISHABLE_KEY);

const scenario = shot.scenario[lang];
const run: string = (await fgJson(['seed', scenario])).run;
console.error(`[take] ${video} ${lang}: seeded ${scenario} as ${run}`);
const manifest = JSON.parse(
  await Deno.readTextFile(`${Deno.env.get('FG_STATE_DIR') ?? `${Deno.env.get('HOME')}/.cache/fg/${prefix}`}/runs/${run}.json`),
);

const clients: d.Client[] = [];
try {
  await Deno.mkdir(out, { recursive: true });
  for (const [i, handle] of shot.members.entries()) {
    const u = manifest.users[handle];
    const c = await d.launch(
      { name: handle, email: u.email, password: u.password, lang, display: Number(`${prefix}9${i}`) },
      bundle,
      work,
    );
    clients.push(c);
    await d.login(c);
  }
  const s = new d.Session(clients);
  const byName = Object.fromEntries(clients.map((c) => [c.name, c]));
  await shot.prepare?.(s, byName, lang);
  const rec = await d.record(s, out);
  let measured: Record<string, unknown> = {};
  try {
    measured = (await shot.film(s, byName, lang)) ?? {};
  } finally {
    await rec.stop();
  }
  const offsets = JSON.parse(await Deno.readTextFile(`${out}/offsets.json`));
  await Deno.remove(`${out}/offsets.json`);
  await Deno.writeTextFile(`${out}/events.json`, JSON.stringify(s.events, null, 1) + '\n');
  await Deno.writeTextFile(
    `${out}/take.json`,
    JSON.stringify({ video, lang, scenario, run, scale: d.SCALE, at: new Date().toISOString(), offsets, measured }, null, 1) + '\n',
  );
  console.error(`[take] wrote ${out}`);
} finally {
  await d.shutdown(clients);
  if (!keep) await fgJson(['teardown', run]);
}
