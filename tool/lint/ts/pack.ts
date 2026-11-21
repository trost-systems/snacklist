// The TypeScript and JavaScript sibling of flutter_agent_lints (docs/hillclimb/hc-strictness.md). Every rule of
// `deno lint --rules` and every strictness option of the compiler is listed exactly once, on or
// off, with the reason. `error` fails the lint gate; `pending` is in the target but still has
// findings (tool/hillclimb/hc-strictness counts them); `off` is never run.

export type Level = 'error' | 'pending' | 'off';

export interface Rule {
  readonly level: Level;
  readonly why: string;
  /** The fix needs a type annotation, so plain JavaScript files are skipped. */
  readonly tsOnly?: true;
}

const on = (why: string): Rule => ({ level: 'error', why });
const ts = (why: string): Rule => ({ level: 'error', why, tsOnly: true });
const off = (why: string): Rule => ({ level: 'off', why });

const recommended = 'Deno recommended set.';
const jsx = 'Deno recommended set; inert, the repo has no JSX.';

export const lintRules: Readonly<Record<string, Rule>> = {
  'adjacent-overload-signatures': on(recommended),
  'ban-ts-comment': on('A `@ts-ignore` hides the next type error too; fix the type.'),
  'ban-types': on(recommended),
  'ban-unknown-rule-code': on('An ignore naming no rule silences nothing and reads as if it did.'),
  'ban-untagged-ignore': on('An ignore must name the rule it silences.'),
  'ban-untagged-todo': on('A TODO without an owner or issue is never done.'),
  'ban-unused-ignore': on('A stale ignore hides the next real finding on that line.'),
  'camelcase': on(
    'One spelling for identifiers. A snake_case wire name (JSON, PostHog, OAuth, a DB column) is written as a quoted key, the form the rule accepts, or renamed on destructuring.',
  ),
  'constructor-super': on(recommended),
  'default-param-last': on('A defaulted parameter before a required one can only be defaulted with `undefined`.'),
  'eqeqeq': on('`==` coerces; one comparison operator.'),
  'explicit-function-return-type': off(
    'Local and private return types are inferred; writing them repeats the compiler. Exports are covered by explicit-module-boundary-types.',
  ),
  'explicit-module-boundary-types': ts(
    'An exported function is a contract; its return type is written so a body change cannot silently change it.',
  ),
  'for-direction': on(recommended),
  'fresh-handler-export': off('Fresh framework rule; the repo has no Fresh app.'),
  'fresh-server-event-handlers': off('Fresh framework rule; the repo has no Fresh app.'),
  'getter-return': on(recommended),
  'guard-for-in': on('`for...in` walks inherited keys; use Object.keys/entries.'),
  'jsx-boolean-value': on(jsx),
  'jsx-button-has-type': on(jsx),
  'jsx-curly-braces': on(jsx),
  'jsx-key': on(jsx),
  'jsx-no-children-prop': on(jsx),
  'jsx-no-comment-text-nodes': on(jsx),
  'jsx-no-duplicate-props': on(jsx),
  'jsx-no-unescaped-entities': on(jsx),
  'jsx-no-useless-fragment': on(jsx),
  'jsx-props-no-spread-multi': on(jsx),
  'jsx-void-dom-elements-no-children': on(jsx),
  'no-array-constructor': on(recommended),
  'no-async-promise-executor': on(recommended),
  'no-await-in-loop': off(
    'Sequential awaits are mostly intended here (UI steps in e2e, ordered writes, retries); a Promise.all rewrite would change behaviour and the rule cannot tell the cases apart.',
  ),
  'no-await-in-sync-fn': on(recommended),
  'no-boolean-literal-for-arguments': off(
    "Fires at call sites of APIs the repo does not own (assertEquals(x, true), Playwright's setChecked(true), JSON.stringify); the declaration side is what matters.",
  ),
  'no-case-declarations': on(recommended),
  'no-class-assign': on(recommended),
  'no-compare-neg-zero': on(recommended),
  'no-cond-assign': on(recommended),
  'no-console': off('CLI scripts print and edge functions log through console by design.'),
  'no-const-assign': on(recommended),
  'no-constant-condition': on(recommended),
  'no-control-regex': on(recommended),
  'no-debugger': on(recommended),
  'no-delete-var': on(recommended),
  'no-deprecated-deno-api': on(recommended),
  'no-dupe-args': on(recommended),
  'no-dupe-class-members': on(recommended),
  'no-dupe-else-if': on(recommended),
  'no-dupe-keys': on(recommended),
  'no-duplicate-case': on(recommended),
  'no-empty': on('An empty block is either a forgotten body or a swallowed error; say which.'),
  'no-empty-character-class': on(recommended),
  'no-empty-enum': on(recommended),
  'no-empty-interface': on(recommended),
  'no-empty-pattern': on(
    '`{}` destructures nothing. A Playwright fixture without dependencies needs it and carries an ignore saying so.',
  ),
  'no-eval': on('Code from strings bypasses every check here.'),
  'no-ex-assign': on(recommended),
  'no-explicit-any': on('`any` switches the type checker off for everything it touches.'),
  'no-external-import': off(
    'Flags `node:` built-ins and npm packages in the Node code; Deno code pins versions through import maps.',
  ),
  'no-extra-boolean-cast': on(recommended),
  'no-extra-non-null-assertion': on(recommended),
  'no-fallthrough': on(recommended),
  'no-func-assign': on(recommended),
  'no-global-assign': on(recommended),
  'no-implicit-declare-namespace-export': on('One export form.'),
  'no-import-assertions': on(recommended),
  'no-import-assign': on(recommended),
  'no-import-prefix': on('Versions live in the import map (deno.json), not inline `npm:`/`jsr:` specifiers.'),
  'no-inferrable-types': ts('A literal initializer already states the type.'),
  'no-inner-declarations': on(recommended),
  'no-invalid-regexp': on(recommended),
  'no-invalid-triple-slash-reference': on(recommended),
  'no-irregular-whitespace': on(recommended),
  'no-misused-new': on(recommended),
  'no-namespace': on(recommended),
  'no-new-symbol': on(recommended),
  'no-node-globals': on(
    'Buffer, global and friends are imported from `node:` so the runtime dependency is explicit.',
  ),
  'no-non-null-asserted-optional-chain': on('`a?.b!` asserts what the chain just said may be missing.'),
  'no-non-null-assertion': ts('`x!` is an unchecked cast; narrow or fail with a message instead.'),
  'no-obj-calls': on(recommended),
  'no-octal': on(recommended),
  'no-process-global': on('`process` is imported from `node:process` so the runtime dependency is explicit.'),
  'no-prototype-builtins': on(recommended),
  'no-redeclare': on(recommended),
  'no-regex-spaces': on('A run of spaces in a regex is unreadable; write ` {n}`.'),
  'no-self-assign': on(recommended),
  'no-self-compare': on('`x === x` is a NaN test or a typo; use Number.isNaN.'),
  'no-setter-return': on(recommended),
  'no-shadow-restricted-names': on(recommended),
  'no-sloppy-imports': on('Imports name the file with its extension; one resolution rule for Deno and Node.'),
  'no-slow-types': off('JSR publishing rule; nothing here is published to JSR.'),
  'no-sparse-arrays': on('`[a,,b]` is a typo more often than a hole.'),
  'no-sync-fn-in-async-fn': on('A sync file call in an async function blocks the event loop the function yields to.'),
  'no-this-alias': on(recommended),
  'no-this-before-super': on(recommended),
  'no-throw-literal': on('Only Error objects carry a stack.'),
  'no-top-level-await': off('Scripts and ES modules here use top-level await by design.'),
  'no-undef': off(
    'TypeScript already reports undefined names; for JavaScript the rule does not know DOM globals used in page.evaluate and site/public, and no-process-global/no-node-globals cover Node.',
  ),
  'no-unreachable': on(recommended),
  'no-unsafe-finally': on(recommended),
  'no-unsafe-negation': on(recommended),
  'no-unused-labels': on(recommended),
  'no-unused-vars': on('Dead names mislead the reader.'),
  'no-unversioned-import': on(recommended),
  'no-useless-rename': on('`{ a: a }` says the same twice.'),
  'no-var': on(recommended),
  'no-window': on('`globalThis` works in every runtime; one name for the global object.'),
  'no-window-prefix': on('`globalThis` works in every runtime; one name for the global object.'),
  'no-with': on(recommended),
  'prefer-as-const': on(recommended),
  'prefer-ascii': off('User-visible German copy has umlauts and must stay byte-identical.'),
  'prefer-const': on(recommended),
  'prefer-namespace-keyword': on(recommended),
  'prefer-primordials': off("Deno's internal-code rule against prototype pollution; unreadable in application code."),
  'react-no-danger': off('React rule; there is no React here.'),
  'react-no-danger-with-children': off('React rule; there is no React here.'),
  'react-rules-of-hooks': off("React rule; it mistakes Playwright's fixture `use()` for a hook."),
  'require-await': on('An async function without await hides that nothing is asynchronous.'),
  'require-yield': on(recommended),
  'single-var-declarator': on('One declaration per statement.'),
  'triple-slash-reference': on('Types come from imports.'),
  'use-isnan': on(recommended),
  'valid-typeof': on(recommended),
  'verbatim-module-syntax': ts(
    'Type-only imports are written `import type`, so erasure never changes what runs.',
  ),
};

/** Compiler options on top of `strict`, which every project already has. */
export const compilerOptions: Readonly<Record<string, Rule>> = {
  noUncheckedIndexedAccess: on('An index or record lookup may miss; the type says so.'),
  exactOptionalPropertyTypes: on('`x?: T` means absent, not `undefined`; one meaning.'),
  noImplicitReturns: on('Every path of a function returns explicitly.'),
  noFallthroughCasesInSwitch: on('A case falls through only when it says so.'),
  noImplicitOverride: on('An override is written `override`, so a renamed base method is caught.'),
  noUnusedLocals: off('no-unused-vars reports the same findings, with ignore support.'),
  noUnusedParameters: off('no-unused-vars reports the same findings, with ignore support.'),
  noPropertyAccessFromIndexSignature: off(
    'Forces `obj["key"]` on every Record read; noUncheckedIndexedAccess already types the miss.',
  ),
};

export interface Exclusion {
  readonly path: string;
  readonly why: string;
}

/** Paths under these prefixes are not linted or type-checked. */
export const excluded: readonly Exclusion[] = [
  { path: 'supabase/functions/alexa/', why: 'Alexa code is frozen for hill-climbs (job 101 brief).' },
  { path: 'supabase/functions/voice/', why: 'The Siri endpoint is frozen for hill-climbs (job 101 brief).' },
  { path: 'scripts/alexa/', why: 'Alexa operator scripts are frozen for hill-climbs (job 101 brief).' },
  { path: 'scripts/siri-phrases.ts', why: 'Siri tooling is frozen for hill-climbs (job 101 brief).' },
  { path: 'e2e/tests/alexa', why: 'Alexa specs and helpers are frozen for hill-climbs (job 101 brief).' },
  { path: 'e2e/tests/voice.spec.ts', why: 'Specs of the Siri endpoint are frozen for hill-climbs (job 101 brief).' },
  { path: 'scripts/iap/', why: 'In-app purchase store tooling is frozen for hill-climbs (job 101 brief: no IAP).' },
  {
    path: 'supabase/functions/purchases/',
    why: 'The RevenueCat webhook is IAP code, frozen for hill-climbs (job 101 brief).',
  },
  {
    path: 'supabase/functions/_shared/purchases',
    why: 'IAP entitlement code, frozen for hill-climbs (job 101 brief).',
  },
  {
    path: 'supabase/functions/_shared/premium',
    why: 'The Premium gate is IAP code, frozen for hill-climbs (job 101 brief).',
  },
  { path: 'e2e/tests/iap.ts', why: 'IAP test helpers, frozen for hill-climbs (job 101 brief).' },
  { path: 'e2e/tests/purchases.spec.ts', why: 'IAP specs, frozen for hill-climbs (job 101 brief).' },
  { path: 'e2e/tests/premium-yearly.spec.ts', why: 'IAP specs, frozen for hill-climbs (job 101 brief).' },
  {
    path: 'tool/hillclimb/hc-backend-perf/bench.ts',
    why:
      "Job 106's measurement harness: the hill-climb protocol freezes it after the baseline, so a lint fix would re-baseline that goal (follow-up in docs/NEEDS_PETER.md, Job 101).",
  },
  { path: 'app/web/posthog/', why: 'Vendored, minified posthog-js (app/web/posthog/VERSION).' },
  {
    path: 'docs/design/',
    why:
      'Archived design prototypes and their built bundles; nothing runs them, and they keep their own oxlint config.',
  },
];

/**
 * Type-checked TypeScript projects. `deno` ones use their deno.json if they have one, `tsc` ones
 * their tsconfig.json. A file belongs to the nearest project above it; strict.ts fails when an
 * in-scope TypeScript file belongs to none.
 */
export interface Project {
  readonly dir: string;
  readonly checker: 'deno' | 'tsc';
}

export const projects: readonly Project[] = [
  { dir: 'supabase/functions', checker: 'deno' },
  { dir: 'supabase/classifier', checker: 'deno' },
  { dir: 'supabase/deploy', checker: 'deno' },
  { dir: 'supabase/checks', checker: 'deno' },
  { dir: 'analytics', checker: 'deno' },
  { dir: '.cursor/skills/verify-family-groceries/cli', checker: 'deno' },
  { dir: 'tool/lint/ts', checker: 'deno' },
  { dir: 'scripts', checker: 'deno' },
  { dir: 'marketing/videos/capture', checker: 'deno' },
  { dir: 'site/config', checker: 'deno' },
  { dir: 'nexus', checker: 'deno' },
  { dir: 'docs/research/351-trip-detection', checker: 'deno' },
  { dir: 'e2e', checker: 'tsc' },
  { dir: 'emails', checker: 'tsc' },
];
