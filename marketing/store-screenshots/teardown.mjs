#!/usr/bin/env node
// Tears down every fg run the capture seeded (out/runs.txt). Tries each run and fails at the end,
// so one failure leaves no other behind; the file keeps the ones that failed.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';
import { repo } from '../../.claude/skills/verify-snacklist/helpers/lib.mjs';

const file = join(process.env.STORE_SHOTS_OUT ?? join(import.meta.dirname, 'out'), 'runs.txt');
if (existsSync(file)) {
  const failed = [];
  for (const run of new Set(readFileSync(file, 'utf8').split('\n').filter(Boolean))) {
    try {
      execFileSync(join(repo, 'scripts/fg'), ['teardown', run], { stdio: ['ignore', 'ignore', 'inherit'] });
    } catch {
      failed.push(run);
    }
  }
  if (failed.length) {
    writeFileSync(file, `${failed.join('\n')}\n`);
    console.error(`fg teardown failed for ${failed.join(', ')}; ${file} keeps them`);
    process.exit(1);
  }
  rmSync(file);
}
