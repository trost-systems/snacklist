// Writes site/COPY_NEEDED.md, the landing copy for Snacklist PM, from content/landing/copy.yml.
// `--check` writes nothing and fails when the file is stale (the site tests run it).
import process from 'node:process';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { HISTORY_COPY } from '../history.mjs';
import { parseCopy } from '../landing.mjs';

const SITE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
const SOURCE = 'content/landing/copy.yml';
const TARGET = join(SITE_DIR, 'COPY_NEEDED.md');

const SECTIONS = {
  meta: 'Landing pages: title and description (search, sharing)',
  header: 'Every page: header (also the landing buttons)',
  footer: 'Every page: footer',
  hero: 'Landing: hero',
  features: 'Landing: features',
  feature: 'Landing: feature cards',
  voice: 'Landing: voice block',
  privacy: 'Landing: privacy block',
  founder: 'Landing: founder note (waitlist and beta stages)',
  test: 'Landing: closing block',
  demo: 'Landing: demo videos',
  waitlist: 'Waitlist: sign-up form, confirm and unsubscribe pages',
  beta: 'Stage beta: call to action',
  launch: 'Stage launch: call to action, store badges, QR code',
};

const cell = (s) => s.replaceAll('|', '\\|').replaceAll('\n', ' ');

/** The demo videos' on-screen words (job 54), kept with their sources in marketing/videos. */
export const VIDEO_COPY = join(SITE_DIR, '../marketing/videos/copy.json');

export function readVideoCopy() {
  const raw = JSON.parse(readFileSync(VIDEO_COPY, 'utf8'));
  return Object.entries(raw).filter(([id]) => id !== '_');
}

/** Siri's and Alexa's new spoken sentences (job 112, Q79); the functions' tests check them. */
export const VOICE_COPY = join(SITE_DIR, '../supabase/functions/voice/copy_needed.json');

export function readVoiceCopy() {
  const raw = JSON.parse(readFileSync(VOICE_COPY, 'utf8'));
  return Object.entries(raw).filter(([id]) => id !== '_');
}

export function copyNeeded(
  copy,
  videoCopy = [],
  historyCopy = Object.entries(HISTORY_COPY),
  voiceCopy = readVoiceCopy(),
) {
  const rows = (status) =>
    [...copy]
      .filter(([, e]) => e.status === status)
      .map(([id, e]) => `| \`${id}\` | ${SECTIONS[id.split('.')[0]] ?? id.split('.')[0]} | ${cell(e.de)} | ${cell(e.en)} | ${cell(e.source)} | ${status} |`);
  const head = '| Id | Page / section | DE | EN | Why / source | Status |\n| --- | --- | --- | --- | --- | --- |';
  return `# Copy needed: landing pages (for Snacklist PM)

Generated from \`site/${SOURCE}\` by \`node site/scripts/copy-needed.mjs\`; edit the YAML, not this
file. Every string on \`/de\` and \`/en\` carries its id in the page as \`data-copy-id="<id>"\`.

**draft**: new or changed for the first homepage (job 53), waiting for Launch. Change the text in
\`copy.yml\` and set \`status: reused\` once approved, or keep it a draft. Siri copy stays a draft
until native Siri ships. **reused**: word for word from copy that is already published.

\`waitlist.*\` is the sign-up form and the pages behind the mail links (job 82, docs/WAITLIST.md);
\`beta.*\` and \`launch.*\` show only in those stages (\`site/config/stage.ts\`). Every text waits for
Peter's approval in his own words; Legal's consent texts are in \`site/content/legal/consent/\`.

## Drafts

${head}
${rows('draft').join('\n')}

## Reused

${head}
${rows('reused').join('\n')}
${videoCopy.length ? `
## Demo videos: words on screen

From \`marketing/videos/copy.json\` (job 54). They are burnt into the videos: after a change,
re-render with \`node marketing/videos/build.mjs\` (marketing/videos/README.md).

${head}
${videoCopy.map(([id, e]) => `| \`${id}\` | Demo video ${id.split('.')[0]} | ${cell(e.de)} | ${cell(e.en)} | ${cell(e.source)} | ${e.status} |`).join('\n')}
` : ''}${historyCopy.length ? `
## Release timeline (/history, /en/history)

From \`HISTORY_COPY\` in \`site/history.mjs\` (job 105): every string of the release timeline and
its footer link. Peter approved the existing strings on 2026-11-26 (H1, t1300u). \`status\` is
\`draft\` until approved, then \`reused\`. \`{…}\` is filled in at build time. Change the text
there; this section follows.

${head}
${historyCopy.map(([id, e]) => `| \`${id}\` | ${cell(e.where)} | ${cell(e.de)} | ${cell(e.en)} | New: release timeline (job 105). Peter 2026-11-26 (H1). | ${e.status ?? 'draft'} |`).join('\n')}
` : ''}${voiceCopy.length ? `
## Voice replies (Siri, Alexa)

From \`supabase/functions/voice/copy_needed.json\` (job 112, Peter Q79): the yes/no question when
the user says a plain name and the open item has its own brand or details. Examples with Butter
(brand Weihenstephan) and Quark (brand Ehrmann) open; the names come from the list. Change the
sentence in the functions and in that file together (\`voice/copy_needed_test.ts\` checks them).

${head}
${voiceCopy.map(([id, e]) => `| \`${id}\` | ${cell(e.where)} | ${cell(e.de)} | ${cell(e.en)} | New: Peter Q79, job 112. | draft |`).join('\n')}
` : ''}`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const text = copyNeeded(parseCopy(readFileSync(join(SITE_DIR, SOURCE), 'utf8'), SOURCE), readVideoCopy());
  if (process.argv.includes('--check')) {
    if (readFileSync(TARGET, 'utf8') !== text) {
      console.error('site/COPY_NEEDED.md is stale: run node site/scripts/copy-needed.mjs');
      process.exit(1);
    }
  } else {
    writeFileSync(TARGET, text);
    console.log('wrote site/COPY_NEEDED.md');
  }
}
