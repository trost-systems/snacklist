// What scripts/posthog/sync-flags.ts changes in PostHog (job 332, docs/ANALYTICS.md "Flags from
// main and minimum versions"): the repo's inputs and PostHog's flags parsed into types, and the plan
// that makes PostHog match. Pure: no I/O.

export const PLATFORMS = ['android', 'ios', 'linux', 'macos', 'web', 'windows'] as const;
export type Platform = typeof PLATFORMS[number];

/** An app version, `MAJOR.MINOR.PATCH`, and optionally the lowest build of it. */
export interface Requirement {
  readonly version: string;
  readonly build?: number;
}

export interface MinVersion {
  readonly default: Requirement;
  readonly platforms: ReadonlyMap<Platform, Requirement>;
}

export interface DesiredFlag {
  readonly key: string;
  readonly description: string;
  readonly minVersion?: MinVersion;
}

/** The newest public release in each store, from releases/releases.json (latest-store.ts). */
export interface LatestStore {
  readonly ios?: Requirement;
  readonly android?: Requirement;
}

// PostHog's shapes keep every field they came with, so an update never drops one.
export interface PropertyFilter {
  readonly key: string;
  readonly type?: string;
  readonly value?: unknown;
  readonly operator?: string;
  readonly [extra: string]: unknown;
}

export interface Group {
  readonly properties?: readonly PropertyFilter[];
  readonly 'rollout_percentage'?: number | null;
  readonly variant?: string | null;
  readonly [extra: string]: unknown;
}

export interface Filters {
  readonly groups?: readonly Group[];
  readonly [extra: string]: unknown;
}

export interface ExistingFlag {
  readonly id: number;
  readonly key: string;
  readonly filters: Filters;
  readonly active?: boolean;
  readonly deleted?: boolean;
}

export interface CreateFlagBody {
  readonly key: string;
  readonly name: string;
  readonly active: true;
  readonly filters: { readonly groups: readonly Group[] };
}

export type Action =
  | { readonly kind: 'create-flag'; readonly key: string; readonly body: CreateFlagBody }
  | {
    readonly kind: 'update-flag-filters';
    readonly id: number;
    readonly key: string;
    readonly before: Filters;
    readonly after: Filters;
  };

export interface Plan {
  readonly actions: readonly Action[];
  readonly errors: readonly string[];
}

export class InputError extends Error {}

const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const REQUIREMENT = /^((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))(?:\+([1-9]\d*))?$/;
const FLAG_KEY = /^[a-z0-9][a-z0-9-]*$/;

const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isPlatform = (value: string): value is Platform =>
  (PLATFORMS as readonly string[]).includes(value);

function parseJson(text: string, source: string): unknown {
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new InputError(`${source}: not valid JSON (${String(error)})`);
  }
}

/** `"1.4.0"` or `"1.4.0+1420"`. */
export function parseRequirement(value: unknown, where: string): Requirement {
  const match = typeof value === 'string' ? REQUIREMENT.exec(value) : null;
  const version = match?.[1];
  if (version === undefined) {
    throw new InputError(
      `${where}: ${JSON.stringify(value)} is not a version "MAJOR.MINOR.PATCH" or ` +
        `"MAJOR.MINOR.PATCH+BUILD" (BUILD a whole number above 0)`,
    );
  }
  const build = match?.[2];
  return build === undefined ? { version } : { version, build: Number(build) };
}

function parseMinVersion(value: unknown, where: string): MinVersion {
  if (!isRecord(value)) return { default: parseRequirement(value, where), platforms: new Map() };
  if (!('default' in value)) {
    throw new InputError(`${where}: an object needs "default" (the version for other platforms)`);
  }
  const platforms = new Map<Platform, Requirement>();
  for (const [name, requirement] of Object.entries(value)) {
    if (name === 'default') continue;
    if (!isPlatform(name)) {
      throw new InputError(
        `${where}.${name}: unknown platform (allowed: default, ${PLATFORMS.join(', ')})`,
      );
    }
    platforms.set(name, parseRequirement(requirement, `${where}.${name}`));
  }
  return { default: parseRequirement(value['default'], `${where}.default`), platforms };
}

/**
 * Every top-level `const [String] <name>Flag = '<key>';` of app/lib/analytics/flags.dart, its `///` doc
 * comment as one line. A declaration may span lines (`dart format` wraps a long one after `=`);
 * one the parser cannot read throws instead of being skipped.
 */
export function parseFlagsDart(text: string): readonly { key: string; description: string }[] {
  const lines = text.split('\n');
  const flags: { key: string; description: string }[] = [];
  lines.forEach((line, index) => {
    if (!/^const\s+(?:\w+\s+)?\w+Flag\b/.test(line)) return;
    const declaration = lines.slice(index).join('\n');
    const match = /^const\s+(?:String\s+)?\w+Flag\s*=\s*'([^'\n]*)'\s*;/.exec(declaration);
    if (match === null) {
      throw new InputError(
        `flags.dart line ${index + 1}: cannot read the flag key of '${line.trim()}' ` +
          "(write const <name>Flag = '<key>';)",
      );
    }
    const key = match[1] ?? '';
    if (!FLAG_KEY.test(key)) {
      throw new InputError(
        `flags.dart line ${index + 1}: flag key '${key}' must match ${FLAG_KEY}`,
      );
    }
    if (flags.some((f) => f.key === key)) {
      throw new InputError(`flags.dart line ${index + 1}: flag key '${key}' is declared twice`);
    }
    const doc: string[] = [];
    for (let i = index - 1; i >= 0; i--) {
      const comment = /^\s*\/\/\/ ?(.*)$/.exec(lines[i] ?? '');
      if (comment === null) break;
      doc.unshift(comment[1] ?? '');
    }
    flags.push({ key, description: doc.join(' ').replace(/\s+/g, ' ').trim() || key });
  });
  if (flags.length === 0) {
    throw new InputError("flags.dart: no `const <name>Flag = '<key>';` found");
  }
  return flags;
}

/** The flags of flags.dart with releases/flags.json's `min_version`s. */
export function desiredFlags(flagsDart: string, flagsJson: string): readonly DesiredFlag[] {
  const fromDart = parseFlagsDart(flagsDart);
  const data = parseJson(flagsJson, 'releases/flags.json');
  const entries = isRecord(data) && isRecord(data['flags']) ? data['flags'] : {};
  const minVersions = new Map<string, MinVersion>();
  for (const [key, entry] of Object.entries(entries)) {
    if (!isRecord(entry) || !('min_version' in entry)) continue;
    const where = `releases/flags.json flags.${key}.min_version`;
    if (!fromDart.some((f) => f.key === key)) {
      throw new InputError(
        `${where}: app/lib/analytics/flags.dart has no flag '${key}' (a const <name>Flag)`,
      );
    }
    minVersions.set(key, parseMinVersion(entry['min_version'], where));
  }
  return fromDart.map((flag) => {
    const minVersion = minVersions.get(flag.key);
    return minVersion === undefined ? flag : { ...flag, minVersion };
  });
}

const compareRequirements = (a: Requirement, b: Requirement): number => {
  const pa = a.version.split('.').map(Number);
  const pb = b.version.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d;
  }
  return (a.build ?? 0) - (b.build ?? 0);
};

/** The newest public release per store in releases/releases.json. */
export function parseLatestStore(releasesJson: string): LatestStore {
  const data = parseJson(releasesJson, 'releases/releases.json');
  const releases = isRecord(data) && Array.isArray(data['releases']) ? data['releases'] : [];
  let ios: Requirement | undefined;
  let android: Requirement | undefined;
  releases.forEach((release: unknown, i) => {
    const where = `releases/releases.json releases[${i}]`;
    if (!isRecord(release) || release['channel'] !== 'public') return;
    const { version, build, stores } = release;
    if (typeof version !== 'string' || !SEMVER.test(version)) {
      throw new InputError(`${where}.version: not MAJOR.MINOR.PATCH`);
    }
    if (typeof build !== 'number' || !Number.isInteger(build) || build < 1) {
      throw new InputError(`${where}.build: not a whole number above 0`);
    }
    const requirement = { version, build };
    const newer = (current: Requirement | undefined): boolean =>
      current === undefined || compareRequirements(requirement, current) > 0;
    if (isRecord(stores) && stores['app_store'] === true && newer(ios)) ios = requirement;
    if (isRecord(stores) && stores['play'] === true && newer(android)) android = requirement;
  });
  return { ...(ios === undefined ? {} : { ios }), ...(android === undefined ? {} : { android }) };
}

function parseFilters(value: unknown, where: string): Filters {
  if (value === null || value === undefined) return {};
  if (!isRecord(value)) throw new InputError(`${where}.filters: not an object`);
  const groups = value['groups'];
  if (groups === undefined || groups === null) return value;
  if (!Array.isArray(groups)) throw new InputError(`${where}.filters.groups: not an array`);
  return {
    ...value,
    groups: groups.map((group: unknown, g): Group => {
      const at = `${where}.filters.groups[${g}]`;
      if (!isRecord(group)) throw new InputError(`${at}: not an object`);
      const properties = group['properties'];
      if (properties === undefined || properties === null) return group;
      if (!Array.isArray(properties)) throw new InputError(`${at}.properties: not an array`);
      return {
        ...group,
        properties: properties.map((property: unknown, p): PropertyFilter => {
          if (!isRecord(property) || typeof property['key'] !== 'string') {
            throw new InputError(`${at}.properties[${p}]: not an object with a key`);
          }
          const { operator } = property;
          if (operator !== undefined && operator !== null && typeof operator !== 'string') {
            throw new InputError(`${at}.properties[${p}].operator: not a string`);
          }
          return { ...property, key: property['key'] };
        }),
      };
    }),
  };
}

const optionalBoolean = (value: unknown, where: string): { readonly [k: string]: boolean } => {
  if (value === undefined || value === null) return {};
  if (typeof value !== 'boolean') throw new InputError(`${where}: not a boolean`);
  return { [where.split('.').pop() ?? '']: value };
};

/** The `results` of GET /feature_flags/. */
export function parseExistingFlags(results: readonly unknown[]): readonly ExistingFlag[] {
  return results.map((flag, i) => {
    const where = `feature flag [${i}]`;
    if (!isRecord(flag) || typeof flag['id'] !== 'number' || typeof flag['key'] !== 'string') {
      throw new InputError(`${where}: not an object with a numeric id and a key`);
    }
    return {
      id: flag['id'],
      key: flag['key'],
      filters: parseFilters(flag['filters'], where),
      ...optionalBoolean(flag['active'], `${where}.active`),
      ...optionalBoolean(flag['deleted'], `${where}.deleted`),
    };
  });
}

// Equal JSON whatever the key order; `undefined` fields count as missing.
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (isRecord(value)) {
    return `{${
      Object.keys(value).filter((k) => value[k] !== undefined).sort().map((k) =>
        `${JSON.stringify(k)}:${canonical(value[k])}`
      ).join(',')
    }}`;
  }
  return JSON.stringify(value) ?? 'null';
}

// A group's properties are ANDed, so their order does not matter.
const canonicalGroup = (group: Group): string =>
  canonical({ ...group, properties: (group.properties ?? []).map(canonical).sort() });

const sameGroups = (a: readonly Group[], b: readonly Group[]): boolean =>
  a.length === b.length && a.every((group, i) => {
    const other = b[i];
    return other !== undefined && canonicalGroup(group) === canonicalGroup(other);
  });

const isTrue = (value: unknown): boolean =>
  value === true || (typeof value === 'string' && value.toLowerCase() === 'true') ||
  (Array.isArray(value) && value.length === 1 && isTrue(value[0]));

const INTERNAL: PropertyFilter = {
  key: 'is_internal',
  type: 'person',
  operator: 'exact',
  value: ['true'],
};

export const isInternalGroup = (group: Group): boolean =>
  (group.properties ?? []).some((p) =>
    p.key === 'is_internal' && (p.operator === undefined || p.operator === 'exact') &&
    isTrue(p.value)
  );

const isSyncVersion = (p: PropertyFilter | undefined): boolean =>
  p?.key === 'app_version' && p.operator === 'semver_gte';
const isSyncBuild = (p: PropertyFilter | undefined): boolean =>
  p?.key === 'app_build' && (p.operator === 'gte' || p.operator === 'is_set');

/**
 * The properties without the version pair this sync writes: `app_version` semver ≥ directly
 * followed by `app_build` ≥ or set, the last such pair. Every other version condition is a
 * human's (an excluded release, a newer build) and stays, ANDed with the sync's pair.
 */
function withoutSyncPair(properties: readonly PropertyFilter[]): readonly PropertyFilter[] {
  for (let i = properties.length - 2; i >= 0; i--) {
    if (isSyncVersion(properties[i]) && isSyncBuild(properties[i + 1])) {
      return [...properties.slice(0, i), ...properties.slice(i + 2)];
    }
  }
  return properties;
}

// app_build goes only with an analytics yes; the shared no-consent request sends app_version and
// platform, and Legal §18 L2 forbids property targeting without consent: every version condition
// needs app_build.
function versionConditions(r: Requirement): readonly PropertyFilter[] {
  const version = { key: 'app_version', type: 'person', operator: 'semver_gte', value: r.version };
  return r.build === undefined
    ? [version, { key: 'app_build', type: 'person', operator: 'is_set', value: 'is_set' }]
    : [version, { key: 'app_build', type: 'person', operator: 'gte', value: r.build }];
}

const platformCondition = (operator: 'exact' | 'is_not', value: readonly string[]) => ({
  key: 'platform',
  type: 'person',
  operator,
  value: [...value],
});

const requirementOf = (minVersion: MinVersion, platform: string): Requirement =>
  (isPlatform(platform) ? minVersion.platforms.get(platform) : undefined) ?? minVersion.default;

const platformValues = (p: PropertyFilter): readonly string[] =>
  (Array.isArray(p.value) ? p.value : [p.value])
    .filter((v): v is string => typeof v === 'string')
    // PostHog's `exact` and `is_not` ignore case: `iOS` is ios.
    .map((v) => v.toLowerCase());

/**
 * One group with [minVersion]. The sync's version pair is replaced; the group's other conditions,
 * version, platform and rollout ones a human set included, are never touched, so a hand edit in
 * PostHog survives every run. Only a group without a platform condition is split by platform, and
 * a group excluding platforms (`platform is not`) that now have their own version gets those
 * platforms as new groups. Throws for a group the sync cannot read.
 */
function versionedGroup(group: Group, minVersion: MinVersion): readonly Group[] {
  const base = withoutSyncPair(group.properties ?? []);
  const withVersion = (extra: readonly PropertyFilter[], r: Requirement): Group => ({
    ...group,
    properties: [...base, ...extra, ...versionConditions(r)],
  });
  const platforms = base.filter((p) => p.key === 'platform');
  const overrides = [...minVersion.platforms.keys()].sort();
  if (platforms.length === 0) {
    if (overrides.length === 0) return [withVersion([], minVersion.default)];
    return [
      ...overrides.map((p) =>
        withVersion([platformCondition('exact', [p])], requirementOf(minVersion, p))
      ),
      withVersion([platformCondition('is_not', overrides)], minVersion.default),
    ];
  }
  const exact = platforms.filter((p) => p.operator === undefined || p.operator === 'exact');
  const excluded = platforms.filter((p) => p.operator === 'is_not');
  if (exact.length + excluded.length !== platforms.length) {
    throw new InputError('a platform condition other than "equals" or "is not"');
  }
  if (exact.length > 0) {
    const targets = new Set(exact.flatMap(platformValues));
    const requirements = new Set([...targets].map((t) => canonical(requirementOf(minVersion, t))));
    if (requirements.size !== 1) {
      throw new InputError(
        `platforms ${[...targets].sort().join(', ')} in one condition with different min_version`,
      );
    }
    return [withVersion([], requirementOf(minVersion, [...targets][0] ?? ''))];
  }
  const out = new Set(excluded.flatMap(platformValues));
  const missing = overrides.filter((p) => !out.has(p));
  if (missing.length === 0) return [withVersion([], minVersion.default)];
  return [
    ...missing.map((p) =>
      withVersion([platformCondition('exact', [p])], requirementOf(minVersion, p))
    ),
    withVersion([platformCondition('is_not', missing)], minVersion.default),
  ];
}

/** The groups that carry [minVersion]: internal groups as they are, every other one conditioned. */
export function versionedGroups(
  groups: readonly Group[],
  minVersion: MinVersion,
): readonly Group[] {
  return groups.flatMap((group) =>
    isInternalGroup(group) ? [group] : versionedGroup(group, minVersion)
  );
}

/**
 * What makes PostHog match the repo. Only adds: a missing flag for internal installs, and the
 * version conditions of a flag with a minimum version. Never anything else.
 */
export function plan(
  desired: readonly DesiredFlag[],
  existingFlags: readonly ExistingFlag[],
): Plan {
  const actions: Action[] = [];
  const errors: string[] = [];
  for (const flag of desired) {
    const existing = existingFlags.find((f) => f.deleted !== true && f.key === flag.key);
    if (existing === undefined) {
      actions.push({
        kind: 'create-flag',
        key: flag.key,
        body: {
          key: flag.key,
          name: flag.description,
          active: true,
          filters: { groups: [{ properties: [INTERNAL], 'rollout_percentage': 100 }] },
        },
      });
      continue;
    }
    if (flag.minVersion === undefined) continue;
    const aggregation = existing.filters['aggregation_group_type_index'];
    if (aggregation !== undefined && aggregation !== null) {
      errors.push(
        `flag ${flag.key}: a group-based flag (aggregation_group_type_index ${
          String(aggregation)
        }) cannot take a min_version; left as it is`,
      );
      continue;
    }
    const groups = existing.filters.groups ?? [];
    let next: readonly Group[];
    try {
      next = versionedGroups(groups, flag.minVersion);
    } catch (error) {
      if (!(error instanceof InputError)) throw error;
      errors.push(
        `flag ${flag.key}: ${error.message}; left as it is, fix the condition in PostHog`,
      );
      continue;
    }
    if (sameGroups(groups, next)) continue;
    actions.push({
      kind: 'update-flag-filters',
      id: existing.id,
      key: flag.key,
      before: existing.filters,
      after: { ...existing.filters, groups: next },
    });
  }
  return { actions, errors };
}
