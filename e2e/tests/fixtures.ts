import { mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { test as base, type BrowserContext, type TestInfo } from '@playwright/test';

export * from '@playwright/test';

/**
 * A runner pause this long is the host (VM freeze, mem-guard SIGSTOP), not load: under 12 CPU
 * burners and a disk writer (load 21) the 1 s tick below ran at most 16 ms late (job 18c).
 */
const hostStallMs = 2_000;

/** Where a failed attempt the host paused leaves its mark, so its retry may run. */
const stallMark = (testInfo: TestInfo) => join(testInfo.project.outputDir, '.host-stalls', testInfo.testId);

/** The e2e build's PostHog host (app/config/e2e.json), a `.invalid` host no request reaches. */
const posthogHost = (JSON.parse(readFileSync(new URL('../../app/config/e2e.json', import.meta.url), 'utf8')) as {
  POSTHOG_HOST: string;
}).POSTHOG_HOST;

/** Answers the app's flag request without consent (Legal §18 FL1') with no flags, as PostHog would. */
async function quietPostHog(context: BrowserContext): Promise<void> {
  await context.route(`${posthogHost}/**`, (route) => route.fulfill({
    status: 200,
    contentType: 'application/json',
    headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type' },
    body: '{"flags":{}}',
  }));
}

/**
 * Playwright's `test`, plus four auto fixtures:
 * - quietPostHog answers the e2e PostHog host in every context a test opens. Every start asks it
 *   for flags, also without consent, and an unanswered request is a console error that specs
 *   watching the console fail on. `fakeCollector`, routed later, takes precedence.
 * - closeContexts closes every browser context a test opened. Specs open their own contexts (one
 *   per user), and the browser outlives the test, so without this each test leaves its Flutter
 *   apps running and later tests boot into a crowded browser.
 * - hostStall names a test the host paused. A host pause that keeps the clock running resumes
 *   with every deadline already passed (the test's, an expect's, Kong's), so the test fails
 *   however its waits are written; the line says why.
 * - stallRetry lets the config's one retry run only after such a pause. A failure without one is
 *   the test's or the app's, and its retry fails at once instead of hiding it.
 */
export const test = base.extend<{ quietPostHog: void; stallRetry: void; hostStall: void; closeContexts: void }>({
  quietPostHog: [
    async ({ browser }, use) => {
      const onContext = (context: BrowserContext) => void quietPostHog(context).catch(() => {});
      browser.on('context', onContext);
      await use();
      browser.off('context', onContext);
    },
    { auto: true },
  ],
  stallRetry: [
    // deno-lint-ignore no-empty-pattern -- Playwright reads fixture dependencies from this pattern; {} means none
    async ({}, use, testInfo) => {
      const mark = stallMark(testInfo);
      // A pause in an attempt that passed leaves its mark; only this test's failed attempt may use one.
      if (testInfo.retry === 0) rmSync(mark, { force: true });
      if (testInfo.retry > 0) {
        if (!existsSync(mark)) throw new Error('not retried: the failed attempt had no host stall, so its failure is real');
        rmSync(mark);
        console.error(`[host-stall] ${testInfo.titlePath.join(' › ')}: retry ${testInfo.retry} after a host stall`);
      }
      await use();
    },
    { auto: true },
  ],
  hostStall: [
    // deno-lint-ignore no-empty-pattern -- Playwright reads fixture dependencies from this pattern; {} means none
    async ({}, use, testInfo) => {
      let last = Date.now();
      let worst = 0;
      // Marks the pause when the tick sees it, not after use(): a fixture teardown the pause
      // timed out ends the test, and Playwright skips the teardowns still to come, this one too.
      const measure = () => {
        const now = Date.now();
        const paused = now - last - 1_000;
        last = now;
        if (paused < hostStallMs) return;
        worst = Math.max(worst, paused);
        const description = `the host paused the test runner for ${Math.round(paused / 1_000)} s`;
        console.error(`[host-stall] ${testInfo.titlePath.join(' › ')}: ${description}`);
        mkdirSync(join(testInfo.project.outputDir, '.host-stalls'), { recursive: true });
        writeFileSync(stallMark(testInfo), description);
      };
      const tick = setInterval(measure, 1_000);
      await use();
      clearInterval(tick);
      measure();
      if (worst > 0) {
        testInfo.annotations.push({ type: 'host-stall', description: `the host paused the test runner for ${Math.round(worst / 1_000)} s` });
      }
    },
    { auto: true },
  ],
  closeContexts: [
    async ({ browser }, use) => {
      const before = new Set(browser.contexts());
      await use();
      await Promise.all(browser.contexts().filter((c) => !before.has(c)).map((c) => c.close()));
    },
    { auto: true },
  ],
});
