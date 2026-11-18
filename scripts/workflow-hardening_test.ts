import { assert, assertEquals } from '@std/assert';
import { check } from './workflow-hardening.ts';

const SHA = '3d3c42e5aac5ba805825da76410c181273ba90b1';
const WF = '.github/workflows/w.yml';

function repo(files: Record<string, string>, entries?: unknown[]): string {
  const dir = Deno.makeTempDirSync();
  const all = { ...files };
  if (entries) all['scripts/workflow-hardening.allow.json'] = JSON.stringify({ entries });
  for (const [path, text] of Object.entries(all)) {
    Deno.mkdirSync(`${dir}/${path.split('/').slice(0, -1).join('/')}`, { recursive: true });
    Deno.writeTextFileSync(`${dir}/${path}`, text);
  }
  return dir;
}

// The shapes the repo's workflows use: the run's own token in a job's env, a step id named
// `secrets`, a `vars.X || secrets.X` fallback, a secret as an action's input, local actions.
const clean = `
name: Clean
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  plan:
    runs-on: ubuntu-24.04
    permissions: {}
    outputs:
      ios: \${{ steps.secrets.outputs.ios }}
    steps:
      - id: secrets
        run: echo "ios=true" >>"$GITHUB_OUTPUT"
  ship:
    needs: plan
    if: needs.plan.outputs.ios == 'true'
    runs-on: ubuntu-24.04
    environment: release
    env:
      GH_TOKEN: \${{ github.token }}
      OTHER_TOKEN: \${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@${SHA} # v7
      - uses: ./.github/actions/deno
        with:
          cache: false
      - uses: webfactory/ssh-agent@${SHA}
        with:
          ssh-private-key: \${{ secrets.DEPLOY_KEY }}
      # A comment may name secrets.COMMENTED without reading it.
      - name: Upload
        if: steps.secrets.outputs.ios == 'true'
        env:
          TEAM: \${{ vars.TEAM || secrets.TEAM }}
          PASSWORD: \${{ secrets.PASSWORD }}
        run: |
          echo "Repository secret PASSWORD and secrets.TEAM are only words here."
`;
const action = `
name: Deno
runs:
  using: composite
  steps:
    - uses: actions/cache/restore@${SHA} # v6
      with:
        path: x
    - shell: bash
      run: echo hi
`;
const cleanRepo = { [WF]: clean, '.github/actions/deno/action.yml': action };

// One job `job` whose body is `body` (indented four spaces).
const workflow = (body: string, top = '') => `on: push\n${top}jobs:\n  job:\n${body}`;
const problemsOf = (text: string, entries?: unknown[]) => check(repo({ [WF]: text }, entries));

Deno.test('workflows and actions that keep the rules pass', () => {
  assertEquals(check(repo(cleanRepo)), []);
});

Deno.test('an action by tag, branch or short SHA fails with file, job and the fix', () => {
  for (const ref of ['actions/checkout@v7', 'actions/checkout@main', 'actions/checkout@3d3c42e']) {
    const problems = problemsOf(workflow(`    steps:\n      - uses: ${ref} # v7\n`));
    assertEquals(problems.length, 1, ref);
    assert(problems[0]?.startsWith(`${WF}: job 'job': 'uses: ${ref}' is not pinned.`));
    assert(problems[0]?.includes('full 40-hex commit SHA'));
    assert(problems[0]?.includes('action-pinned'));
  }
});

Deno.test('a -latest runner label fails, a numbered one passes', () => {
  for (const runsOn of ['ubuntu-latest', '[ubuntu-latest]', '{ labels: [macos-latest] }']) {
    const problems = problemsOf(workflow(`    runs-on: ${runsOn}\n    steps: []\n`));
    assertEquals(problems.length, 1, runsOn);
    assert(problems[0]?.startsWith(`${WF}: job 'job': 'runs-on: `), problems[0]);
    assert(problems[0]?.includes('runner-pinned'));
  }
  for (const runsOn of ['ubuntu-24.04', 'macos-26', '${{ matrix.os }}', '{ group: big-latest }']) {
    assertEquals(problemsOf(workflow(`    runs-on: ${runsOn}\n    steps: []\n`)), [], runsOn);
  }
});

Deno.test('a reusable workflow by tag fails, a local one passes', () => {
  const problems = problemsOf(workflow('    uses: org/repo/.github/workflows/x.yml@v1\n'));
  assertEquals(problems.length, 1);
  assert(problems[0]?.includes('action-pinned'));
  assertEquals(problemsOf(workflow('    uses: ./.github/workflows/x.yml\n')), []);
});

Deno.test('a tag in a composite action fails', () => {
  const files = {
    ...cleanRepo,
    '.github/actions/deno/action.yml': action.replace(`@${SHA}`, '@v6'),
  };
  const problems = check(repo(files));
  assertEquals(problems.length, 1);
  assert(
    problems[0]?.startsWith(".github/actions/deno/action.yml: 'uses: actions/cache/restore@v6'"),
  );
});

Deno.test('a container action passes by digest only', () => {
  const step = (ref: string) => workflow(`    steps:\n      - uses: ${ref}\n`);
  assertEquals(problemsOf(step(`docker://alpine@sha256:${'a'.repeat(64)}`)), []);
  for (const ref of ['docker://alpine:3.20', `docker://alpine@${SHA}`]) {
    const problems = problemsOf(step(ref));
    assert(problems.length === 1 && problems[0]?.includes('by its digest'), `${ref}: ${problems}`);
  }
});

Deno.test('an input named uses is not an action', () => {
  const body = `    steps:\n      - uses: a/b@${SHA}\n        with:\n          uses: a/b@v1\n`;
  assertEquals(problemsOf(workflow(body)), []);
});

Deno.test("a secret in a job's env fails with file, job and the fix", () => {
  const body = `    environment: ops
    env:
      TOKEN: \${{ secrets.TOKEN }}
    steps:
      - run: deploy
`;
  const problems = problemsOf(workflow(body));
  assertEquals(problems.length, 1);
  assert(
    problems[0]?.startsWith(`${WF}: job 'job': secrets.TOKEN is read in the job's env.TOKEN.`),
  );
  assert(problems[0]?.includes('Move it to the env: (or with:) of the one step that needs it'));
  assert(problems[0]?.includes('secret-in-step'));
});

Deno.test("a secret in the workflow's env fails, and so does every job without an environment", () => {
  const body = '    environment: ops\n    steps:\n      - run: deploy\n';
  const other = '  other:\n    steps:\n      - run: echo\n';
  const problems = problemsOf(workflow(body + other, 'env:\n  TOKEN: ${{ secrets.TOKEN }}\n'));
  assertEquals(problems.length, 2);
  assert(problems[0]?.startsWith(`${WF}: secrets.TOKEN is read in env.TOKEN.`));
  assert(problems[1]?.startsWith(`${WF}: job 'other' reads secrets.TOKEN but declares no`));
});

Deno.test('a secret in a script, a condition or a job-level input fails', () => {
  const inScript = '    environment: ops\n    steps:\n      - run: deploy ${{ secrets.TOKEN }}\n';
  assert(problemsOf(workflow(inScript))[0]?.includes("is read in the job's steps[0].run."));
  const inCondition = "    environment: ops\n    if: secrets.TOKEN != ''\n    steps: []\n";
  assert(problemsOf(workflow(inCondition))[0]?.includes("is read in the job's if."));
  const passed = `    environment: ops
    uses: ./.github/workflows/x.yml
    secrets:
      token: \${{ secrets.TOKEN }}
`;
  assert(problemsOf(workflow(passed))[0]?.includes("is read in the job's secrets.token."));
  const service = `    environment: ops
    services:
      db:
        env:
          PASSWORD: \${{ secrets.TOKEN }}
`;
  assert(problemsOf(workflow(service))[0]?.includes("the job's services.db.env.PASSWORD."));
});

Deno.test('every way to write the secrets context counts, the built-in token does not', () => {
  const step = (value: string) =>
    workflow(`    steps:\n      - env:\n          X: \${{ ${value} }}\n        run: x\n`);
  const reads = (value: string) => problemsOf(step(value))[0] ?? '';
  assert(reads('secrets.TOKEN').includes("job 'job' reads secrets.TOKEN but"));
  assert(reads('SECRETS.TOKEN').includes('reads secrets.TOKEN but'));
  assert(reads("secrets['TOKEN']").includes('reads secrets.TOKEN but'));
  assert(reads('vars.TOKEN || secrets.TOKEN').includes('reads secrets.TOKEN but'));
  assert(reads('toJSON(secrets)').includes('reads the whole secrets context but'));
  assertEquals(reads('secrets.GITHUB_TOKEN'), '');
  assertEquals(reads('secrets.github_token'), '');
  assertEquals(reads('github.token'), '');
  assertEquals(reads("hashFiles('secrets.json')"), '');
});

Deno.test("a secret in a mapping's key counts like one in a value", () => {
  const body = (env: string) =>
    workflow(`    environment: ops\n${env}    steps:\n      - run: x\n        env:
          \${{ secrets.B }}: y\n`);
  assertEquals(problemsOf(body('')), []);
  const bare = workflow(
    '    steps:\n      - run: x\n        env:\n          ${{ secrets.B }}: y\n',
  );
  assert(problemsOf(bare)[0]?.includes("job 'job' reads secrets.B but declares no environment"));
  const inJob = problemsOf(body('    env:\n      ${{ secrets.A }}: x\n'));
  assert(inJob.length === 1 && inJob[0]?.includes("secrets.A is read in the job's env."));
});

Deno.test('a }} in a quoted string does not hide the rest of the expression', () => {
  const body = `    environment: ops
    env:
      X: \${{ format('}}{0}', secrets.TOKEN) }}
    steps: []
`;
  assert(problemsOf(workflow(body))[0]?.includes("secrets.TOKEN is read in the job's env.X."));
});

Deno.test('secrets: inherit reads the whole context', () => {
  const body = '    uses: ./.github/workflows/x.yml\n    secrets: inherit\n';
  const problems = problemsOf(workflow(body));
  assertEquals(problems.length, 2);
  assert(problems[0]?.includes("the whole secrets context is read in the job's secrets."));
  assert(problems[1]?.includes("job 'job' reads the whole secrets context but declares no"));
  const entry = { file: WF, job: 'job', rule: 'secret-in-step', secrets: ['*'], reason: 'why' };
  const allowed = [entry, { ...entry, rule: 'secret-needs-environment' }];
  assertEquals(problemsOf(workflow(body), allowed), []);
});

Deno.test('a job that reads a secret needs an environment, as a name or a mapping', () => {
  const steps = '    steps:\n      - env:\n          X: ${{ secrets.A }}\n        run: x\n';
  const problems = problemsOf(workflow(steps));
  assertEquals(problems.length, 1);
  assert(problems[0]?.startsWith(`${WF}: job 'job' reads secrets.A but declares no environment.`));
  assert(problems[0]?.includes("Add 'environment: ops'"));
  assert(problems[0]?.includes('secret-needs-environment'));
  assertEquals(problemsOf(workflow(`    environment: ops\n${steps}`)), []);
  const mapping = (keys: string) => workflow(`    environment:\n${keys}${steps}`);
  assertEquals(problemsOf(mapping('      name: ops\n      deployment: false\n')), []);
  assertEquals(problemsOf(workflow(`    environment: ''\n${steps}`)).length, 1);
  assertEquals(problemsOf(mapping('      deployment: false\n')).length, 1);
  assertEquals(problemsOf(mapping("      name: ''\n")).length, 1);
});

Deno.test('an environment that is not one of the known ones fails', () => {
  const steps = '    steps:\n      - env:\n          X: ${{ secrets.A }}\n        run: x\n';
  for (const name of ['opps', '${{ inputs.environment }}']) {
    const problems = problemsOf(workflow(`    environment: ${name}\n${steps}`));
    assertEquals(problems.length, 1, name);
    assert(problems[0]?.includes(`in the environment '${name}', which is none of release, ops`));
    assert(problems[0]?.includes('secret-needs-environment'));
  }
  assertEquals(problemsOf(workflow(`    environment: Release\n${steps}`)), []);
  assertEquals(problemsOf(workflow('    environment: staging\n    steps: []\n')), []);
});

const allowsToken = {
  file: WF,
  job: 'job',
  rule: 'secret-in-step',
  secrets: ['TOKEN'],
  reason: 'owned by job 209',
};

Deno.test('an entry allows its file, job and rule only', () => {
  const body = `    env:
      TOKEN: \${{ secrets.TOKEN }}
    steps:
      - uses: a/b@v1
`;
  const entry = allowsToken;
  const environment = { ...entry, rule: 'secret-needs-environment' };
  assertEquals(problemsOf(workflow(body)).length, 3);
  const left = problemsOf(workflow(body), [entry, environment]);
  assertEquals(left.length, 1);
  assert(left[0]?.includes('action-pinned'));
  const elsewhere = problemsOf(workflow(body), [{ ...entry, job: 'other' }, environment]);
  assertEquals(elsewhere.filter((p) => p.includes('secret-in-step')).length, 2);
});

Deno.test('an entry allows nothing in another file or in a job it does not name', () => {
  const body = workflow('    env:\n      TOKEN: ${{ secrets.TOKEN }}\n    steps: []\n');
  const other = '.github/workflows/other.yml';
  const environment = { ...allowsToken, rule: 'secret-needs-environment' };
  const twice = check(repo({ [WF]: body, [other]: body }, [allowsToken, environment]));
  assertEquals(twice.length, 2, `${twice}`);
  assert(twice.every((p) => p.startsWith(`${other}: job 'job'`)), `${twice}`);

  const { job: _, ...noJob } = allowsToken;
  const unnamed = problemsOf(body, [noJob, environment]);
  assertEquals(unnamed.filter((p) => p.includes('secret-in-step')).length, 2, `${unnamed}`);
  assert(unnamed.some((p) => p.includes('stale')), `${unnamed}`);
});

Deno.test('an entry allows the actions it lists only', () => {
  const body = (more: string) => workflow(`    steps:\n      - uses: a/b@v1\n${more}`);
  const entry = { file: WF, job: 'job', rule: 'action-pinned', actions: ['A/b'], reason: 'why' };
  assertEquals(problemsOf(body(''), [entry]), []);
  const added = problemsOf(body('      - uses: evil/other@main\n'), [entry]);
  assertEquals(added.length, 1);
  assert(added[0]?.includes("'uses: evil/other@main' is not pinned."));
  assert(added[0]?.includes('with its reason and the action'));
  const gone = problemsOf(body(''), [{ ...entry, actions: ['a/b', 'c/d'] }]);
  assertEquals(gone.length, 1);
  assert(gone[0]?.includes("action-pinned lists 'c/d', which nothing there uses against the rule"));
});

Deno.test('an entry allows a finding outside a job when it names none', () => {
  const files = {
    ...cleanRepo,
    '.github/actions/deno/action.yml': action.replace(`@${SHA}`, '@v6'),
  };
  const entry = {
    file: '.github/actions/deno/action.yml',
    rule: 'action-pinned',
    actions: ['actions/cache/restore'],
    reason: 'why',
  };
  assertEquals(check(repo(files, [entry])), []);
});

Deno.test('an entry allows the secrets it lists only', () => {
  const body = (more: string) =>
    workflow(`    env:
      TOKEN: \${{ secrets.token }}
${more}    steps: []
`);
  const environment = { ...allowsToken, rule: 'secret-needs-environment' };
  assertEquals(problemsOf(body(''), [allowsToken, environment]), []);
  const added = problemsOf(body('      PASSWORD: ${{ secrets.PASSWORD }}\n'), [
    allowsToken,
    environment,
  ]);
  assertEquals(added.length, 2);
  assert(added[0]?.includes("secrets.PASSWORD is read in the job's env.PASSWORD."));
  assert(added[0]?.includes('with its reason and the secret'));
  assert(added[1]?.includes("job 'job' reads secrets.token, secrets.PASSWORD but declares no"));
  const whole = problemsOf(body('      ALL: ${{ toJSON(secrets) }}\n'), [allowsToken, environment]);
  assert(whole[0]?.includes('the whole secrets context is read'));
});

Deno.test('a listed secret that nothing reads any more fails', () => {
  const body = workflow(
    '    environment: ops\n    env:\n      A: ${{ secrets.A }}\n    steps: []\n',
  );
  const problems = problemsOf(body, [{ ...allowsToken, secrets: ['A', 'GONE'] }]);
  assertEquals(problems.length, 1);
  assert(problems[0]?.includes('secret-in-step lists secrets.GONE, which nothing there reads'));
  assert(problems[0]?.includes('Remove it from the entry'));
});

Deno.test('a stale entry fails', () => {
  const entry = { ...allowsToken, job: 'ship' };
  const problems = check(repo(cleanRepo, [entry]));
  assertEquals(problems.length, 1);
  assert(problems[0]?.includes(`the entry for ${WF}, job 'ship', secret-in-step is stale`));
  assert(problems[0]?.includes('Remove it'));
  const gone = check(repo(cleanRepo, [{ ...entry, file: '.github/workflows/gone.yml' }]));
  assert(gone.length === 1 && gone[0]?.includes('stale'));
});

Deno.test('an entry without a reason or with an unknown rule fails', () => {
  const body = '    env:\n      TOKEN: ${{ secrets.TOKEN }}\n    environment: ops\n';
  const entry = { ...allowsToken, reason: ' ' };
  const unexplained = problemsOf(workflow(body), [entry]);
  assert(unexplained.some((p) => p.includes('entry 1') && p.includes('has no reason')));
  assert(unexplained.some((p) => p.includes('secrets.TOKEN is read in')));
  const unknown = problemsOf(workflow(body), [{ ...entry, rule: 'anything', reason: 'why' }]);
  assert(unknown.some((p) => p.includes('entry 1') && p.includes('needs a file and a rule')));
});

Deno.test('an entry lists secrets for a secret rule and actions for the others, never both', () => {
  const body = `    env:
      TOKEN: \${{ secrets.TOKEN }}
    environment: ops
    steps:
      - uses: a/b@v1
`;
  const pinned = { file: WF, job: 'job', rule: 'action-pinned', actions: ['a/b'], reason: 'why' };
  assertEquals(problemsOf(workflow(body), [allowsToken, pinned]), []);
  const { secrets: _, ...unlisted } = allowsToken;
  const { actions: __, ...unnamed } = pinned;
  const wrong = [
    [unlisted, pinned],
    [{ ...allowsToken, secrets: 'TOKEN' }, pinned],
    [{ ...allowsToken, secrets: [] }, pinned],
    [{ ...allowsToken, actions: ['a/b'] }, pinned],
    [{ ...unlisted, actions: ['TOKEN'] }, pinned],
    [allowsToken, unnamed],
    [allowsToken, { ...pinned, actions: [''] }],
    [allowsToken, { ...pinned, secrets: ['TOKEN'] }],
    [allowsToken, { ...unnamed, secrets: ['a/b'] }],
  ];
  for (const [i, entries] of wrong.entries()) {
    const problems = problemsOf(workflow(body), entries);
    assertEquals(problems.length, 2, `${i}: ${problems}`);
    assert(problems.some((p) => p.includes('an entry lists what it covers and nothing else')));
    assert(problems.some((p) => p.includes('is read in') || p.includes('is not pinned')));
  }
});

// A job with `steps` (indented six spaces) that is trusted because of `trust`.
const TRUSTED = {
  secret: '    environment: ops\n',
  environment: '    permissions: {}\n    environment: ops\n',
  write: '    permissions:\n      contents: write\n',
  'write-all': '    permissions: write-all\n',
  'no permissions': '',
};
const READ_ONLY = ['    permissions: {}\n', '    permissions:\n      contents: read\n'];
const secretStep = '      - run: deploy\n        env:\n          TOKEN: ${{ secrets.TOKEN }}\n';
function cacheProblems(trust: string, steps: string, files: Record<string, string> = {}) {
  const problems = check(repo({ ...files, [WF]: workflow(`${trust}    steps:\n${steps}`) }));
  assert(!problems.some((p) => p.includes('is not valid YAML')), problems.join('\n'));
  return problems.filter((p) => p.includes('no-cache-in-trusted-job'));
}

const CACHING_STEPS = {
  [`      - uses: actions/cache@${SHA}\n        with:\n          path: x\n`]:
    "runs 'actions/cache'",
  [`      - uses: actions/cache/restore@${SHA}\n`]: "runs 'actions/cache/restore'",
  [`      - uses: subosito/flutter-action@${SHA}\n        with:\n          cache: true\n`]:
    "'cache: true'",
  [`      - uses: actions/setup-java@${SHA}\n        with:\n          cache: gradle\n`]:
    `'cache: "gradle"'`,
  [`      - uses: ruby/setup-ruby@${SHA}\n        with:\n          bundler-cache: true\n`]:
    "'bundler-cache: true'",
  [`      - uses: actions/setup-java@${SHA}\n        with:\n          cache-jdk: true\n`]:
    "'cache-jdk: true'",
  [`      - uses: subosito/flutter-action@${SHA}\n        with:\n          Cache: true\n`]:
    "'Cache: true'",
  [`      - uses: Swatinem/rust-cache@${SHA}\n`]: "runs 'swatinem/rust-cache'",
  [`      - uses: some/action@${SHA}\n        with:\n          pub-cache: true\n`]:
    "'pub-cache: true'",
  [`      - uses: actions/setup-node@${SHA}\n`]: "without 'package-manager-cache: false'",
  [`      - uses: Actions/Setup-Node@${SHA}\n`]: "'actions/setup-node' without",
  [`      - uses: oven-sh/setup-bun@${SHA}\n`]: "without 'no-cache: true'",
  [`      - uses: oven-sh/setup-bun@${SHA}\n        with:\n          no-cache: false\n`]:
    "'no-cache: false'",
  [`      - uses: supabase/setup-cli@${SHA}\n        with:\n          version: 2.0.0\n`]:
    "'supabase/setup-cli', which restores an Actions cache and has no input to turn that off",
  [`      - uses: ./.github/actions/deno/\n`]: "'./.github/actions/deno' without 'cache: false'",
  [`      - uses: ./.github/actions/deno\n`]: "'./.github/actions/deno' without 'cache: false'",
  [
    `      - uses: ./.github/actions/deno\n        with:\n          cache: \${{ inputs.cache }}\n`
  ]: "the input 'cache: ",
};
const QUIET_STEPS = [
  `      - uses: subosito/flutter-action@${SHA}\n        with:\n          cache: false\n`,
  `      - uses: subosito/flutter-action@${SHA}\n`,
  `      - uses: ./.github/actions/deno\n        with:\n          cache: 'false'\n`,
  `      - uses: actions/setup-node@${SHA}\n        with:\n          package-manager-cache: false\n`,
  `      - uses: actions/setup-node@${SHA}\n        with:\n          package-manager-cache: 'false'\n`,
  `      - uses: oven-sh/setup-bun@${SHA}\n        with:\n          no-cache: true\n`,
  `      - uses: oven-sh/setup-bun@${SHA}\n        with:\n          no-cache: 'true'\n`,
  `      - uses: actions/setup-java@${SHA}\n        with:\n          cache-dependency-path: x\n`,
  `      - uses: actions/setup-java@${SHA}\n        with:\n          cache-jdk: false\n`,
  "      - run: 'echo actions/cache and cache: true are only words here'\n",
];

Deno.test('a job that reads a secret restores no cache, whichever way', () => {
  for (const [step, how] of Object.entries(CACHING_STEPS)) {
    const problems = cacheProblems(TRUSTED.secret, secretStep + step);
    assert(problems.length === 1 && problems[0]?.includes(how), `${step}: ${problems}`);
    assert(problems[0]?.includes("job 'job' reads secrets and "));
  }
});

Deno.test('an environment or a token that may write makes a job trusted too', () => {
  const step = `      - uses: actions/cache@${SHA}\n`;
  const why = {
    environment: "is in the environment 'ops'",
    write: "holds 'contents: write'",
    'write-all': "holds 'permissions: write-all'",
    'no permissions': 'declares no permissions, so its token may write',
  };
  for (const [trust, text] of Object.entries(why)) {
    const problems = cacheProblems(TRUSTED[trust as keyof typeof TRUSTED], step);
    assert(problems.length === 1 && problems[0]?.includes(text), `${trust}: ${problems}`);
  }
  const top = check(
    repo({ [WF]: workflow(`    steps:\n${step}`, 'permissions:\n  issues: write\n') }),
  );
  assert(top.length === 1 && top[0]?.includes("holds 'issues: write'"));
  const own = workflow(`${TRUSTED.write}    steps:\n${step}`, 'permissions: {}\n');
  assert(problemsOf(own)[0]?.includes("holds 'contents: write'"));
});

Deno.test('a job with a read-only token and no secret may use caches', () => {
  for (const permissions of [...READ_ONLY, '    permissions: read-all\n']) {
    for (const step of Object.keys(CACHING_STEPS)) {
      assertEquals(cacheProblems(permissions, step), []);
    }
  }
  const step = `    steps:\n      - uses: actions/cache@${SHA}\n`;
  assertEquals(problemsOf(workflow(step, 'permissions: {}\n')), []);
  const own = workflow(`${READ_ONLY[0]}${step}`, 'permissions:\n  contents: write\n');
  assertEquals(problemsOf(own), []);
});

Deno.test('a trusted job may run actions with the cache turned off', () => {
  for (const trust of Object.values(TRUSTED)) {
    assertEquals(cacheProblems(trust, secretStep + QUIET_STEPS.join('')), []);
  }
  for (const step of QUIET_STEPS) {
    assertEquals(cacheProblems(TRUSTED.secret, secretStep + step), []);
  }
});

Deno.test('a local action that caches counts in the job that runs it', () => {
  const setup = (steps: string) => `runs:\n  using: composite\n  steps:\n${steps}`;
  const files = {
    '.github/actions/deno/action.yml': action,
    '.github/actions/setup/action.yml': setup('    - uses: ./.github/actions/deno\n'),
    '.github/actions/outer/action.yml': setup('    - uses: ./.github/actions/setup\n'),
    '.github/actions/quiet/action.yml': setup(
      '    - uses: ./.github/actions/deno\n      with:\n        cache: false\n',
    ),
    '.github/actions/loop/action.yml': setup('    - uses: ./.github/actions/loop\n'),
    '.github/actions/late/action.yaml': setup(
      `    - shell: bash\n      run: true\n    - uses: supabase/setup-cli@${SHA}\n`,
    ),
  };
  const direct = cacheProblems(TRUSTED.write, '      - uses: ./.github/actions/setup\n', files);
  assert(
    direct.length === 1 &&
      direct[0]?.includes(
        "runs './.github/actions/setup', which runs './.github/actions/deno' without",
      ),
  );
  const nested = cacheProblems(TRUSTED.write, '      - uses: ./.github/actions/outer\n', files);
  assert(nested.length === 1 && nested[0]?.includes("'./.github/actions/outer', which runs"));
  const late = cacheProblems(TRUSTED.write, '      - uses: ./.github/actions/late\n', files);
  assert(
    late.length === 1 &&
      late[0]?.includes("runs './.github/actions/late', which runs 'supabase/setup-cli', which"),
  );
  const quiet = '      - uses: ./.github/actions/quiet\n      - uses: ./.github/actions/loop\n';
  assertEquals(cacheProblems(TRUSTED.write, quiet, files), []);
  assertEquals(
    cacheProblems(READ_ONLY[0] ?? '', '      - uses: ./.github/actions/setup\n', files),
    [],
  );
});

Deno.test('an entry allows the caching action it lists in one job, and is stale without it', () => {
  const entry = {
    file: WF,
    job: 'job',
    rule: 'no-cache-in-trusted-job',
    actions: ['supabase/setup-cli'],
    reason: 'why',
  };
  const steps = (more: string) =>
    workflow(`${TRUSTED.write}    steps:\n      - uses: supabase/setup-cli@${SHA}\n${more}`);
  assertEquals(problemsOf(steps(''), [entry]), []);
  const more = problemsOf(steps(`      - uses: actions/cache@${SHA}\n`), [entry]);
  assert(more.length === 1 && more[0]?.includes("runs 'actions/cache'"), `${more}`);
  const stale = problemsOf(workflow(`${TRUSTED.write}    steps:\n      - run: true\n`), [entry]);
  assert(stale.length === 1 && stale[0]?.includes('stale'));
});

Deno.test('a .yaml workflow is read too', () => {
  const text = workflow('    steps:\n      - uses: a/b@v1\n');
  const problems = check(repo({ '.github/workflows/w.yaml': text }));
  assert(problems.length === 1 && problems[0]?.includes('action-pinned'));
});

Deno.test('a workflow that does not parse, or no workflow at all, fails', () => {
  const broken = problemsOf('jobs:\n  job: [unclosed\n');
  assert(broken.length === 1 && broken[0]?.startsWith(`${WF}: is not valid YAML`));
  const none = check(repo({ 'README.md': 'no workflows' }));
  assert(none.length === 1 && none[0]?.startsWith('No workflow in'));
});
