import { assertEquals, assertThrows } from '@std/assert';
import { blockOf, COVERAGE, coverageFile, DART, dartFile, dataBlock, newestWithBlock, parseRegistry, readMigrations, readRegistry, type Registry } from './retailers.ts';

const lidl = {
  chain: 'lidl',
  country: 'DE',
  name: 'Lidl',
  aliases: [],
  web: 'www.lidl.de',
  apps: [{ name: 'Lidl Plus', android: 'com.lidl.eci.lidlplus', ios: '1238611143', universalLink: null, scheme: 'lidlplus' }],
  status: 'verified',
  verified: '2026-11-18',
  sources: ['https://itunes.apple.com/lookup?id=1238611143&country=de'],
  note: 'One app everywhere.',
};
const registry = (...entries: unknown[]) => ({ version: 2, updated: '2026-11-19', entries });

Deno.test('the repository registry parses and its newest migration is current', async () => {
  const parsed = await readRegistry();
  const de = parsed.entries.filter((e) => e.country === 'DE' && e.chain !== 'ikea').map((e) => `${e.name} (${e.apps[0]?.name})`);
  // The onboarding chips' order (job 321): today's German chips, then Austria's most stores first.
  assertEquals(de, [
    'EDEKA (EDEKA)',
    'REWE (REWE)',
    'Lidl (Lidl Plus)',
    'ALDI SÜD (ALDI SÜD)',
    'ALDI Nord (ALDI Nord)',
    'Kaufland (Kaufland)',
    'Netto Marken-Discount (Netto)',
    'PENNY (PENNY)',
    'dm (Mein dm)',
    'Rossmann (Rossmann)',
  ]);
  assertEquals(
    parsed.entries.filter((e) => e.country === 'AT' && e.chain !== 'ikea').map((e) => e.short ?? e.name),
    ['BILLA', 'SPAR', 'Hofer', 'Lidl', 'PENNY', 'MPREIS', 'dm'],
  );
  // IKEA is no chip (job 408): the app skips chain ikea, so its entries come after each country's chips.
  assertEquals(parsed.entries.filter((e) => e.chain === 'ikea').map((e) => e.country).length, 22);
  assertEquals(parsed.entries.find((e) => e.chain === 'netto-md')?.short, 'Netto');
  assertEquals(await Deno.readTextFile(DART), dartFile(parsed));
  assertEquals(await Deno.readTextFile(COVERAGE), coverageFile(parsed));
  const [, sql] = newestWithBlock(await readMigrations()) ?? [];
  assertEquals(blockOf(sql ?? ''), await dataBlock(parsed));
});

Deno.test('schema problems are named', () => {
  const bad = (entry: Record<string, unknown>, message: string) =>
    assertThrows(() => parseRegistry(registry({ ...lidl, ...entry })), Error, message);
  bad({ country: 'de' }, 'country is not ISO alpha-2');
  bad({ aliases: ['Aldi'] }, 'aliases are lower-case');
  bad({ aliases: ['ah'] }, 'aliases are lower-case');
  bad({ apps: [] }, 'a verified entry lists an app');
  bad({ status: 'no-app' }, 'a no-app entry lists none');
  bad({ apps: [{ ...lidl.apps[0], ios: null }] }, 'bad ios id');
  bad({ apps: [{ ...lidl.apps[0], storeFallback: {} }] }, 'unknown keys storeFallback');
  for (const scheme of [undefined, '', 'lidlplus://', 'LidlPlus', 'https', 'itms-apps', 7]) {
    bad({ apps: [{ ...lidl.apps[0], scheme }] }, 'scheme must be');
  }
  bad({ apps: [lidl.apps[0], lidl.apps[0]] }, 'an android package twice');
  bad({ short: 'Lidl' }, 'short is a name shorter than name');
  bad({ short: '' }, 'short is a name shorter than name');
  assertThrows(() => parseRegistry(registry(lidl, lidl)), Error, 'DE/lidl twice');
});

Deno.test('the block changes with the rows the database keeps, not with notes', async () => {
  const base = parseRegistry(registry(lidl));
  const noted: Registry = parseRegistry(registry({ ...lidl, note: 'Another note.' }));
  const renamed: Registry = parseRegistry(registry({ ...lidl, name: 'Lidl Markt' }));
  assertEquals(await dataBlock(noted), await dataBlock(base));
  assertEquals((await dataBlock(renamed)) === (await dataBlock(base)), false);
  assertEquals(blockOf(`x\n${await dataBlock(base)}\ny`), await dataBlock(base));
});

Deno.test('the app copy keeps a short name and lays out as dart format does', () => {
  const dart = dartFile(parseRegistry(registry({ ...lidl, short: 'L', aliases: ['lidl markt'] })));
  assertEquals(dart.split('\n').filter((l) => l.length > 80), []);
  assertEquals(dart.includes("    short: 'L',\n    aliases: ['lidl markt'],\n"), true);
  assertEquals(
    dart.includes(
      "    apps: [\n      RetailerApp(\n        name: 'Lidl Plus',\n        android: 'com.lidl.eci.lidlplus',\n",
    ),
    true,
  );
});
