// Writes site/COPY_NEEDED.md, the landing copy for Hummlist Launch, from content/landing/copy.yml.
// `--check` writes nothing and fails when the file is stale (the site tests run it).
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
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
  test: 'Landing: test block',
  demo: 'Landing: demo videos',
};

const cell = (s) => s.replaceAll('|', '\\|').replaceAll('\n', ' ');

/** The demo videos' on-screen words (job 54), kept with their sources in marketing/videos. */
export const VIDEO_COPY = join(SITE_DIR, '../marketing/videos/copy.json');

export function readVideoCopy() {
  const raw = JSON.parse(readFileSync(VIDEO_COPY, 'utf8'));
  return Object.entries(raw).filter(([id]) => id !== '_');
}

export function copyNeeded(copy, videoCopy = []) {
  const rows = (status) =>
    [...copy]
      .filter(([, e]) => e.status === status)
      .map(([id, e]) => `| \`${id}\` | ${SECTIONS[id.split('.')[0]] ?? id.split('.')[0]} | ${cell(e.de)} | ${cell(e.en)} | ${cell(e.source)} | ${status} |`);
  const head = '| Id | Page / section | DE | EN | Why / source | Status |\n| --- | --- | --- | --- | --- | --- |';
  return `# Copy needed: landing pages (for Hummlist Launch)

Generated from \`site/${SOURCE}\` by \`node site/scripts/copy-needed.mjs\`; edit the YAML, not this
file. Every string on \`/de\` and \`/en\` carries its id in the page as \`data-copy-id="<id>"\`.

**draft**: new or changed for the first homepage (job 53), waiting for Launch. Change the text in
\`copy.yml\` and set \`status: reused\` once approved, or keep it a draft. Siri copy stays a draft
until native Siri ships. **reused**: word for word from copy that is already published.

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
