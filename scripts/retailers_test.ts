import { assertEquals, assertThrows } from '@std/assert';
import { blockOf, dataBlock, newestWithBlock, parseRegistry, readMigrations, readRegistry, type Registry } from './retailers.ts';

const lidl = {
  chain: 'lidl',
  country: 'DE',
  name: 'Lidl',
  aliases: [],
  web: 'www.lidl.de',
  apps: [{ name: 'Lidl Plus', android: 'com.lidl.eci.lidlplus', ios: '1238611143', universalLink: null }],
  status: 'verified',
  verified: '2026-11-18',
  sources: ['https://itunes.apple.com/lookup?id=1238611143&country=de'],
  note: 'One app everywhere.',
};
const registry = (...entries: unknown[]) => ({ version: 2, updated: '2026-11-19', entries });

Deno.test('the repository registry parses and its newest migration is current', async () => {
  const parsed = await readRegistry();
  const de = parsed.entries.filter((e) => e.country === 'DE').map((e) => `${e.name} (${e.apps[0]?.name})`);
  assertEquals(de, [
    'Lidl (Lidl Plus)',
    'ALDI Nord (ALDI Nord)',
    'ALDI SÜD (ALDI SÜD)',
    'EDEKA (EDEKA)',
    'Netto Marken-Discount (Netto)',
    'REWE (REWE)',
    'Kaufland (Kaufland)',
    'PENNY (PENNY)',
    'dm (Mein dm)',
    'Rossmann (Rossmann)',
  ]);
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
  bad({ apps: [lidl.apps[0], lidl.apps[0]] }, 'an android package twice');
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
