import { assertEquals, assertThrows } from '@std/assert';
import {
  type Action,
  type DesiredFlag,
  desiredFlags,
  type ExistingFlag,
  type Filters,
  InputError,
  parseExistingFlags,
  parseFlagsDart,
  parseLatestStore,
  plan,
  type PropertyFilter,
} from './plan.ts';

const internal: PropertyFilter = {
  key: 'is_internal',
  type: 'person',
  operator: 'exact',
  value: ['true'],
};
const version = (value: string): PropertyFilter => ({
  key: 'app_version',
  type: 'person',
  operator: 'semver_gte',
  value,
});
const build = (value: number): PropertyFilter => ({
  key: 'app_build',
  type: 'person',
  operator: 'gte',
  value,
});
const buildSet: PropertyFilter = {
  key: 'app_build',
  type: 'person',
  operator: 'is_set',
  value: 'is_set',
};
const platform = (value: string): PropertyFilter => ({
  key: 'platform',
  type: 'person',
  operator: 'exact',
  value: [value],
});
const notPlatforms = (...value: string[]): PropertyFilter => ({
  key: 'platform',
  type: 'person',
  operator: 'is_not',
  value,
});

const dart = (...keys: string[]): string =>
  keys.map((k) => `/// The flag ${k}\n/// on two lines.\nconst x${k.length}Flag = '${k}';\n`)
    .join('\n');

const desired = (key: string, minVersion?: unknown): DesiredFlag[] => [
  ...desiredFlags(
    `const aFlag = '${key}';`,
    JSON.stringify({
      flags: minVersion === undefined
        ? {}
        : { [key]: { rollout: 'off', note: '', min_version: minVersion } },
      holds: {},
    }),
  ),
];

const flag = (key: string, filters: Filters, extra: Partial<ExistingFlag> = {}): ExistingFlag => ({
  id: 7,
  key,
  filters,
  active: true,
  ...extra,
});

const everyone = { properties: [], 'rollout_percentage': 100 };
const internalGroup = { properties: [internal], 'rollout_percentage': 100 };

/** Applies a plan's flag updates to the flags it planned on, as PostHog would. */
const applied = (flags: readonly ExistingFlag[], actions: readonly Action[]): ExistingFlag[] =>
  flags.map((f) => {
    const update = actions.find((a) => a.kind === 'update-flag-filters' && a.id === f.id);
    return update?.kind === 'update-flag-filters' ? { ...f, filters: update.after } : f;
  });

const groupsAfter = (actions: readonly Action[]): unknown => {
  const [update] = actions;
  return update?.kind === 'update-flag-filters' ? update.after.groups : update;
};

Deno.test('a key PostHog does not have is created for internal installs at 100 %, active', () => {
  const result = plan(desired('new-thing'), []);
  assertEquals(result.errors, []);
  assertEquals(result.actions, [{
    kind: 'create-flag',
    key: 'new-thing',
    body: {
      key: 'new-thing',
      name: 'new-thing',
      active: true,
      filters: { groups: [{ properties: [internal], 'rollout_percentage': 100 }] },
    },
  }]);
});

Deno.test('a deleted flag counts as missing and is created again', () => {
  const deleted = flag('gone', { groups: [everyone] }, { deleted: true });
  assertEquals(
    plan(desired('gone'), [deleted]).actions.map((a) => a.kind),
    [
      'create-flag',
    ],
  );
});

Deno.test('an existing flag without min_version is never touched, active or not', () => {
  const existing = [
    flag('on', { groups: [everyone] }),
    flag('off', { groups: [{ properties: [version('1.0.0')], 'rollout_percentage': 0 }] }, {
      id: 8,
      active: false,
    }),
  ];
  const result = plan([...desired('on'), ...desired('off')], existing);
  assertEquals(result.actions, []);
  assertEquals(result.errors, []);
});

Deno.test('min_version "1.4.0" conditions every user group on the version and app_build set', () => {
  const existing = flag('f', { groups: [internalGroup, everyone], multivariate: null });
  const result = plan(desired('f', '1.4.0'), [existing]);
  assertEquals(result.actions, [{
    kind: 'update-flag-filters',
    id: 7,
    key: 'f',
    before: existing.filters,
    after: {
      multivariate: null,
      groups: [internalGroup, {
        properties: [version('1.4.0'), buildSet],
        'rollout_percentage': 100,
      }],
    },
  }]);
});

Deno.test('the internal group stays byte for byte and at its place', () => {
  const odd = {
    properties: [{ key: 'is_internal', value: 'TRUE', extra: 1 }],
    'rollout_percentage': 5,
  };
  const existing = flag('f', { groups: [everyone, odd] });
  assertEquals(groupsAfter(plan(desired('f', '2.0.0+3'), [existing]).actions), [
    { properties: [version('2.0.0'), build(3)], 'rollout_percentage': 100 },
    odd,
  ]);
});

Deno.test('a build in min_version becomes app_build >= build', () => {
  const existing = flag('f', {
    groups: [{ properties: [], 'rollout_percentage': 30, variant: null }],
  });
  assertEquals(groupsAfter(plan(desired('f', '1.4.0+1420'), [existing]).actions), [
    { properties: [version('1.4.0'), build(1420)], 'rollout_percentage': 30, variant: null },
  ]);
});

Deno.test('platform versions split a group: one per platform, then the rest at the default', () => {
  const other: PropertyFilter = { key: 'email', type: 'person', operator: 'icontains', value: 'x' };
  const existing = flag('f', { groups: [{ properties: [other], 'rollout_percentage': 50 }] });
  const min = { default: '1.4.0', ios: '1.4.1+1420', android: '1.4.0' };
  assertEquals(groupsAfter(plan(desired('f', min), [existing]).actions), [
    {
      properties: [other, platform('android'), version('1.4.0'), buildSet],
      'rollout_percentage': 50,
    },
    {
      properties: [other, platform('ios'), version('1.4.1'), build(1420)],
      'rollout_percentage': 50,
    },
    {
      properties: [other, notPlatforms('android', 'ios'), version('1.4.0'), buildSet],
      'rollout_percentage': 50,
    },
  ]);
});

Deno.test('a second run on the result plans nothing', () => {
  for (const min of ['1.4.0', '1.4.0+9', { default: '1.0.0', ios: '1.1.0+2', web: '1.0.1' }]) {
    const flags = [
      flag('f', {
        groups: [everyone, internalGroup, { properties: [], 'rollout_percentage': 10 }],
      }),
    ];
    const first = plan(desired('f', min), flags);
    assertEquals(first.actions.length, 1, JSON.stringify(min));
    const second = plan(desired('f', min), applied(flags, first.actions));
    assertEquals(second.actions, [], JSON.stringify(min));
  }
});

Deno.test('a changed min_version replaces the version conditions where they stand', () => {
  const flags = [flag('f', { groups: [internalGroup, everyone] })];
  const first = plan(desired('f', { default: '1.0.0', ios: '1.0.1+5' }), flags);
  const second = plan(desired('f', '2.0.0+20'), applied(flags, first.actions));
  assertEquals(groupsAfter(second.actions), [
    internalGroup,
    { properties: [platform('ios'), version('2.0.0'), build(20)], 'rollout_percentage': 100 },
    { properties: [notPlatforms('ios'), version('2.0.0'), build(20)], 'rollout_percentage': 100 },
  ]);
});

/** Runs the sync [times] times, PostHog taking each plan, and returns the flags after it. */
const runs = (min: unknown, flags: readonly ExistingFlag[], times: number): ExistingFlag[] => {
  let now = [...flags];
  for (let i = 0; i < times; i++) now = applied(now, plan(desired('f', min), now).actions);
  return now;
};
const groupsOf = (flags: readonly ExistingFlag[]): unknown => flags[0]?.filters.groups;

Deno.test('platform conditions a human set survive every run, rollouts untouched (review 0)', () => {
  const flags = [flag('f', {
    groups: [
      internalGroup,
      { properties: [platform('ios')], 'rollout_percentage': 100 },
      { properties: [platform('android')], 'rollout_percentage': 20 },
    ],
  })];
  const once = runs('1.4.0', flags, 1);
  assertEquals(groupsOf(once), [
    internalGroup,
    { properties: [platform('ios'), version('1.4.0'), buildSet], 'rollout_percentage': 100 },
    { properties: [platform('android'), version('1.4.0'), buildSet], 'rollout_percentage': 20 },
  ]);
  assertEquals(plan(desired('f', '1.4.0'), once).actions, []);
});

Deno.test('a split pair whose iOS rollout was raised by hand keeps both rollouts (review 0)', () => {
  const min = { default: '0.1.0+1500', ios: '0.1.0+1510' };
  const split = runs(
    min,
    [flag('f', { groups: [{ properties: [], 'rollout_percentage': 20 }] })],
    1,
  );
  const [first] = split;
  const [ios, rest] = first?.filters.groups ?? [];
  if (first === undefined || ios === undefined || rest === undefined) throw new Error('no split');
  const edited = [{ ...first, filters: { groups: [{ ...ios, 'rollout_percentage': 50 }, rest] } }];
  assertEquals(plan(desired('f', min), edited).actions, []);
  assertEquals(groupsOf(edited), [
    { properties: [platform('ios'), version('0.1.0'), build(1510)], 'rollout_percentage': 50 },
    { properties: [notPlatforms('ios'), version('0.1.0'), build(1500)], 'rollout_percentage': 20 },
  ]);
});

Deno.test('a human web group with per-platform versions is not split or widened (review 0)', () => {
  const min = { default: '1.0.0', ios: '1.1.0', android: '1.2.0' };
  const flags = [
    flag('f', { groups: [{ properties: [platform('web')], 'rollout_percentage': 30 }] }),
  ];
  const once = runs(min, flags, 1);
  assertEquals(groupsOf(once), [
    { properties: [platform('web'), version('1.0.0'), buildSet], 'rollout_percentage': 30 },
  ]);
  assertEquals(plan(desired('f', min), once).actions, []);
  const ios = [
    flag('f', { groups: [{ properties: [platform('ios')], 'rollout_percentage': 30 }] }),
  ];
  assertEquals(groupsOf(runs(min, ios, 2)), [
    { properties: [platform('ios'), version('1.1.0'), buildSet], 'rollout_percentage': 30 },
  ]);
});

Deno.test('a platform newly given its own version leaves the "is not" group with a new group', () => {
  const first = runs({ default: '1.0.0', ios: '1.1.0' }, [flag('f', { groups: [everyone] })], 1);
  const min = { default: '1.0.0', ios: '1.1.0', android: '1.2.0' };
  const second = runs(min, first, 1);
  assertEquals(groupsOf(second), [
    { properties: [platform('ios'), version('1.1.0'), buildSet], 'rollout_percentage': 100 },
    {
      properties: [notPlatforms('ios'), platform('android'), version('1.2.0'), buildSet],
      'rollout_percentage': 100,
    },
    {
      properties: [notPlatforms('ios'), notPlatforms('android'), version('1.0.0'), buildSet],
      'rollout_percentage': 100,
    },
  ]);
  assertEquals(plan(desired('f', min), second).actions, []);
});

Deno.test('version conditions a human set stay, ANDed with the sync pair (review 1)', () => {
  const excluded: PropertyFilter = { ...version('1.5.0'), operator: 'semver_neq' };
  const newer = build(1600);
  for (
    const [min, human, pair] of [
      ['1.4.0', excluded, [version('1.4.0'), buildSet]],
      ['1.4.0+1500', newer, [version('1.4.0'), build(1500)]],
    ] as const
  ) {
    const flags = [flag('f', { groups: [{ properties: [human], 'rollout_percentage': 50 }] })];
    const once = runs(min, flags, 1);
    assertEquals(groupsOf(once), [{ properties: [human, ...pair], 'rollout_percentage': 50 }]);
    assertEquals(plan(desired('f', min), once).actions, [], min);
  }
});

Deno.test('a raised min_version replaces the sync pair, never adds a second one', () => {
  const flags = [flag('f', { groups: [{ properties: [build(1600)], 'rollout_percentage': 10 }] })];
  const raised = runs('1.5.0', runs('1.4.0', flags, 1), 1);
  assertEquals(groupsOf(raised), [
    { properties: [build(1600), version('1.5.0'), buildSet], 'rollout_percentage': 10 },
  ]);
});

Deno.test('one condition over platforms with different versions is an error, left as it is', () => {
  const both = { ...platform('ios'), value: ['ios', 'android'] };
  const existing = flag('f', { groups: [{ properties: [both], 'rollout_percentage': 10 }] });
  const result = plan(desired('f', { default: '1.0.0', ios: '1.1.0' }), [existing]);
  assertEquals(result.actions, []);
  assertEquals(result.errors.length, 1);
  assertEquals(plan(desired('f', '1.0.0'), [existing]).errors, []);
});

Deno.test('a flag whose only groups are internal gets no version condition', () => {
  const existing = flag('f', { groups: [internalGroup] });
  assertEquals(plan(desired('f', '1.0.0'), [existing]).actions, []);
});

Deno.test('a group-based flag with min_version is an error and stays as it is', () => {
  const existing = flag('f', { groups: [everyone], aggregation_group_type_index: 0 });
  const result = plan(desired('f', '1.0.0'), [existing]);
  assertEquals(result.actions, []);
  assertEquals(result.errors.length, 1);
});

Deno.test('a bad min_version is an error naming the flag', () => {
  for (
    const bad of [
      '1.4',
      '1.4.0+0',
      '01.4.0',
      'v1.4.0',
      '1.4.0-beta',
      14,
      { ios: '1.0.0' },
      { default: '1.0.0', tv: '1.0.0' },
      { default: '1.0.0', ios: '1.0' },
    ]
  ) {
    assertThrows(() => desired('my-flag', bad), InputError, 'flags.my-flag.min_version');
  }
});

Deno.test('a min_version for a key flags.dart does not have is an error', () => {
  const json = JSON.stringify({
    flags: { other: { rollout: 'off', note: '', min_version: '1.0.0' } },
  });
  assertThrows(() => desiredFlags(dart('mine'), json), InputError, "no flag 'other'");
});

Deno.test('flags.dart: keys of top-level const ...Flag with their doc comment on one line', () => {
  const text = [
    "import 'package:x/x.dart';",
    '',
    '/// The flag that shows the Verlauf tab, the grocery log',
    '/// (job 199).',
    "const groceryLogFlag = 'grocery-log';",
    '',
    "const bareFlag = 'bare';",
    "const notAFlagName = 'ignored';",
    "  const indentedFlag = 'ignored-too';",
  ].join('\n');
  assertEquals(parseFlagsDart(text), [
    {
      key: 'grocery-log',
      description: 'The flag that shows the Verlauf tab, the grocery log (job 199).',
    },
    { key: 'bare', description: 'bare' },
  ]);
  assertThrows(() => parseFlagsDart("const xFlag = 'Bad_Key';"), InputError, 'Bad_Key');
  assertThrows(() => parseFlagsDart('class Flags {}'), InputError, 'no `const');
});

const release = (v: string, b: number, stores: Record<string, boolean>) => ({
  version: v,
  channel: 'public',
  build: b,
  stores: { app_store: false, play: false, web: false, ...stores },
});

Deno.test('the latest store release per platform, by version then build', () => {
  const releases = JSON.stringify({
    releases: [
      release('1.2.0', 30, { app_store: true, play: true }),
      release('1.10.0', 40, { play: true }),
      release('1.9.0', 50, { app_store: true }),
      release('1.9.0', 45, { app_store: true }),
    ],
  });
  assertEquals(parseLatestStore(releases), {
    ios: { version: '1.9.0', build: 50 },
    android: { version: '1.10.0', build: 40 },
  });
  assertEquals(parseLatestStore(JSON.stringify({ releases: [] })), {});
});

Deno.test('PostHog lists parse with unknown fields kept, and refuse a wrong shape', () => {
  const [parsed] = parseExistingFlags([{
    id: 1,
    key: 'k',
    filters: { groups: [{ properties: [{ key: 'a', negation: false }], extra: 1 }], payloads: {} },
    active: false,
    created_by: { email: 'x' },
  }]);
  assertEquals(parsed, {
    id: 1,
    key: 'k',
    filters: { groups: [{ properties: [{ key: 'a', negation: false }], extra: 1 }], payloads: {} },
    active: false,
  });
  assertThrows(() => parseExistingFlags([{ id: '1', key: 'k' }]), InputError);
  assertThrows(
    () => parseExistingFlags([{ id: 1, key: 'k', filters: { groups: {} } }]),
    InputError,
  );
});

const repo = new URL('../../', import.meta.url);
const read = (path: string): Promise<string> => Deno.readTextFile(new URL(path, repo));

Deno.test("the repo's real flags.dart, flags.json and releases.json parse and plan against an empty PostHog", async () => {
  const flags = desiredFlags(
    await read('app/lib/analytics/flags.dart'),
    await read('releases/flags.json'),
  );
  parseLatestStore(await read('releases/releases.json'));
  const result = plan(flags, []);
  assertEquals(result.errors, []);
  assertEquals(
    result.actions.filter((a) => a.kind === 'create-flag').length,
    flags.length,
  );
});
