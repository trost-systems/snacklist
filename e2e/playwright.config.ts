import { defineConfig, devices } from '@playwright/test';
import { readFileSync } from 'node:fs';
import process from 'node:process';
import { fakeOidcPort, webPort as port, stack } from './stack';

// Job 28: the timings in tests/perf.spec.ts take 4-5 minutes, so they run only when named:
// `npx playwright test tests/perf.spec.ts`, or `scripts/ci-e2e.sh --spec tests/perf.spec.ts`.
const timingsAsked = process.argv.some((arg) => /perf/.test(arg));
// Job 33c: the e2e build's stand-in PostHog host, for the production CSP serve.mjs sends.
// Job 50: the run of integration-lock.spec.ts alone (scripts/gates/e2e.sh).
const lockRun = process.env.FG_E2E_INTEGRATION_LOCK === '1';
const posthogHost = JSON.parse(readFileSync(new URL('../app/config/e2e.json', import.meta.url), 'utf8')).POSTHOG_HOST;

export default defineConfig({
  testDir: './tests',
  ...(timingsAsked ? {} : { grepInvert: /@perf/ }),
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  // One locally: the box's RAM is shared by parallel jobs (COORDINATION.md, Memory).
  workers: process.env.CI ? 2 : 1,
  // One retry, which fixtures.ts lets run only after a host stall (VM pause) cut the attempt.
  retries: 1,
  // The JSON report is what the job summary and scripts/ci-e2e.sh read (scripts/e2e-summary.sh).
  // The integration-lock run (below) writes its own, so the suite's stay what CI summarizes.
  reporter: process.env.CI
    ? [
      ['list'],
      ['html', { open: 'never', outputFolder: `playwright-report${lockRun ? '-integration-lock' : ''}` }],
      ['json', { outputFile: `playwright-results${lockRun ? '-integration-lock' : ''}.json` }],
    ]
    : 'list',
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    locale: 'de-DE',
    timezoneId: 'Europe/Berlin',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  // Job 50: integration-lock.spec.ts flips the server's integration_lock switch, which every Siri,
  // Alexa and MCP spec relies on being off, so it runs alone after the suite (scripts/gates/e2e.sh
  // sets FG_E2E_INTEGRATION_LOCK=1 for that run).
  projects: lockRun ? [{
    name: 'integration-lock',
    testMatch: /integration-lock\.spec\.ts/,
    use: { ...devices['Desktop Chrome'], viewport: { width: 480, height: 900 } },
  }] : [
    {
      name: 'chromium',
      testIgnore: /(iphone|integration-lock)\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 480, height: 900 },
        // Supabase Auth sends the browser to the fake identity provider by the
        // name its container knows it under.
        launchOptions: { args: ['--host-resolver-rules=MAP host.docker.internal 127.0.0.1'] },
      },
    },
    // Job 28: Safari's engine. As an iPhone for the tap focus, as a desktop for the timings
    // (the mouse wheel does not scroll a mobile WebKit page).
    { name: 'iphone', testMatch: /iphone\.spec\.ts/, use: { ...devices['iPhone 15'] } },
    // Job 33c: no request to Google in every engine. Job 201: each engine runs the wasm app.
    { name: 'webkit', testMatch: /(perf|no-google|wasm-boot|tick-leave)\.spec\.ts/, use: { ...devices['Desktop Safari'] } },
    {
      name: 'firefox',
      testMatch: /(perf|no-google|wasm-boot|tick-leave)\.spec\.ts/,
      use: {
        ...devices['Desktop Firefox'],
        viewport: { width: 480, height: 900 },
        // Headless Firefox has no WebGL, so no skwasm: it would run the JS app. Headed on a display
        // (scripts/gates/e2e.sh runs Playwright under xvfb-run), it renders with Mesa's llvmpipe.
        headless: !process.env.DISPLAY,
      },
      // A precaution, not a measured fix: one headed window at a time on the shared display.
      workers: 1,
    },
  ],
  webServer: [
    {
      command: `node serve.mjs ../app/build/web ${port} --csp ${stack.url} ${posthogHost}`,
      url: `http://127.0.0.1:${port}`,
      reuseExistingServer: !process.env.CI,
    },
    {
      // Every copy signs with the same key, so one left running is reusable.
      command: `node fake-oidc.mjs ${fakeOidcPort}`,
      url: `http://127.0.0.1:${fakeOidcPort}/realms/test/.well-known/openid-configuration`,
      reuseExistingServer: true,
    },
  ],
});
