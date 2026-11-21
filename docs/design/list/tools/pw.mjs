// Playwright from the repo's e2e folder (or the main clone's, for a worktree without node_modules).
import { createRequire } from 'node:module';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';

const here = dirname(fileURLToPath(import.meta.url));
const dir = [join(here, '../../../../e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
if (!dir) throw new Error('no playwright: run npm ci in e2e/');
export const { chromium } = createRequire(join(dir, 'package.json'))('playwright');
