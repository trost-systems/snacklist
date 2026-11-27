import { assert, assertEquals } from '@std/assert';
import { type Brand, check, findings, type LiveRow, parseBrandLive, type Rule } from './store-brands.ts';

const DE = 'app/fastlane/metadata/de-DE/description.txt';
const EN = 'app/fastlane/metadata/en-US/description.txt';
const KEYWORDS = 'app/fastlane/metadata/de-DE/keywords.txt';
const TODAY = '2026-11-27';

const notice = {
  Siri: 'Siri ist eine Marke von Apple Inc.',
  Alexa:
    'Amazon, Alexa und alle zugehörigen Marken sind Marken von Amazon.com, Inc. oder seinen verbundenen Unternehmen.',
  Claude: 'Claude ist eine Marke von Anthropic.',
  ChatGPT: 'ChatGPT ist eine Marke von OpenAI.',
};

function row(
  brand: Brand,
  live: boolean,
  verified: string | null = TODAY,
  texts = [DE, EN],
): LiveRow {
  return { brand, live, verified, texts };
}

function run(
  texts: Record<string, string>,
  rows: LiveRow[],
  opts: { publish?: boolean; nativeSiri?: boolean } = {},
): [string, Brand | null, Rule][] {
  return findings({
    texts: new Map(Object.entries(texts)),
    rows: new Map(rows.map((r) => [r.brand, r])),
    today: TODAY,
    publish: opts.publish ?? false,
    nativeSiri: opts.nativeSiri ?? false,
  }).map((f) => [f.file, f.brand, f.rule]);
}

const allLive = (['Siri', 'Alexa', 'Claude', 'ChatGPT'] as Brand[]).map((b) => row(b, true));

Deno.test('allowed: a live brand in BN-1 wording, once, with its notice, passes on publish day', () => {
  const de = [
    'Einkaufen zu zweit.',
    '• Einträge per Siri-Kurzbefehl hinzufügen.',
    '• Mit dem Snacklist-Skill für Amazon Alexa fügst du Einträge per Sprache hinzu.',
    '• Snacklist für Claude, mit Snacklist Premium.',
    '• Snacklist in ChatGPT, mit Snacklist Premium, je nach ChatGPT-Tarif und Land.',
    '',
    `${notice.Siri} ${notice.Alexa} ${notice.Claude} ${notice.ChatGPT}`,
  ].join('\n');
  assertEquals(run({ [DE]: de }, allLive, { publish: true }), []);
});

Deno.test('allowed: an English Alexa line and "with Siri" once the device test passed', () => {
  const en = 'Add items with Siri. With the Snacklist skill for Amazon Alexa you can add items.\n' +
    'Siri is a trademark of Apple Inc. Amazon, Alexa, and all related marks are trademarks of Amazon.com, Inc. or its affiliates.';
  assertEquals(run({ [EN]: en }, allLive, { nativeSiri: true }), []);
  assertEquals(run({ [EN]: en }, allLive).map(([, b, r]) => `${b}:${r}`), [
    'Siri:form',
  ]);
});

Deno.test('a brand that BRAND_LIVE.md does not mark live fails, and on publish day it must be verified today', () => {
  const de = `Per Siri-Kurzbefehl.\n${notice.Siri}`;
  assertEquals(run({ [DE]: de }, [row('Siri', false)]), [[DE, 'Siri', 'live']]);
  assertEquals(run({ [DE]: de }, [row('Siri', true, '2026-11-20')]), []);
  assertEquals(
    run({ [DE]: de }, [row('Siri', true, '2026-11-20')], { publish: true }),
    [[DE, 'Siri', 'live']],
  );
});

Deno.test('a text the brand row does not list fails', () => {
  const de = `Per Siri-Kurzbefehl.\n${notice.Siri}`;
  assertEquals(run({ [DE]: de }, [row('Siri', true, TODAY, [])]), [[
    DE,
    'Siri',
    'texts',
  ]]);
});

Deno.test('disallowed phrasing fails: works with, partner, powered by, by Brand, Brand app, ™, Alexa possessive', () => {
  const cases = [
    'Funktioniert mit Claude, mit Snacklist Premium.',
    'Works with Claude, with Snacklist Premium.',
    'Offizieller Partner für Claude, mit Snacklist Premium.',
    'Powered by Claude, mit Snacklist Premium.',
    'Snacklist für Claude™, mit Snacklist Premium.',
    'Die Claude App für Snacklist, mit Snacklist Premium.',
  ];
  for (const line of cases) {
    const rules = run({ [DE]: `${line}\n${notice.Claude}` }, allLive).map((
      [, , r],
    ) => r);
    assert(rules.includes('phrasing'), `${line} -> ${rules.join(', ')}`);
  }
  const alexa = run({
    [DE]: `Alexas Liste im Snacklist-Skill für Amazon Alexa.\n${notice.Alexa}`,
  }, allLive);
  assert(alexa.some(([, b, r]) => b === 'Alexa' && r === 'phrasing'));
});

Deno.test('disallowed form: Alexa without "Snacklist-Skill für Amazon Alexa", Claude as subject, Siri natively before the test', () => {
  const rules = (de: string) => run({ [DE]: de }, allLive).map(([, b, r]) => `${b}:${r}`);
  assertEquals(
    rules(`Mit dem Snacklist-Skill für Alexa fügst du hinzu.\n${notice.Alexa}`),
    ['Alexa:form'],
  );
  assertEquals(
    rules(`Claude liest deine Liste, mit Snacklist Premium.\n${notice.Claude}`),
    ['Claude:form'],
  );
  assertEquals(rules(`Sag es Siri.\n${notice.Siri}`), ['Siri:form']);
});

Deno.test('one plain mention per brand per text; the notice does not count', () => {
  const de = `Per Siri-Kurzbefehl.\nNoch einmal per Siri-Kurzbefehl.\n${notice.Siri}`;
  assertEquals(run({ [DE]: de }, allLive), [[DE, 'Siri', 'once']]);
});

Deno.test('Premium: Siri and Alexa lines never name it, AI lines always carry it, ChatGPT lines name the plan limit', () => {
  const rules = (de: string) => run({ [DE]: de }, allLive).map(([, b, r]) => `${b}:${r}`);
  assertEquals(rules(`Per Siri-Kurzbefehl, ohne Premium.\n${notice.Siri}`), [
    'Siri:premium',
  ]);
  assertEquals(rules(`Snacklist für Claude.\n${notice.Claude}`), [
    'Claude:premium',
  ]);
  assertEquals(
    rules(`Snacklist in ChatGPT, mit Snacklist Premium.\n${notice.ChatGPT}`),
    ['ChatGPT:qualifier'],
  );
});

Deno.test('a description naming a brand ends with its trademark notice', () => {
  assertEquals(run({ [DE]: 'Per Siri-Kurzbefehl.' }, allLive), [[
    DE,
    null,
    'notice',
  ]]);
});

Deno.test('keyword field and metadata: a brand fails even when live, on every never surface', () => {
  const live = allLive;
  const surfaces: [string, string][] = [
    [KEYWORDS, 'einkauf,liste,chatgpt'],
    [KEYWORDS, 'einkauf,alexa'],
    [KEYWORDS, 'einkauf,gpt'],
    [KEYWORDS, 'einkauf,Chat-GPT'],
    ['app/fastlane/metadata/de-DE/name.txt', 'Snacklist für Claude'],
    ['app/fastlane/metadata/en-US/subtitle.txt', 'Lists for Siri'],
    ['app/fastlane/metadata/de-DE/promotional_text.txt', 'Jetzt in ChatGPT'],
    ['app/fastlane/metadata/android/de-DE/title.txt', 'Snacklist Alexa'],
    [
      'app/fastlane/metadata/android/en-US/short_description.txt',
      'Shopping list for Amazon Echo',
    ],
    ['app/fastlane/metadata/iap/de-DE/yearly.txt', 'Premium\nMit OpenAI'],
  ];
  for (const [file, text] of surfaces) {
    assertEquals(run({ [file]: text }, live, { publish: true }), [[
      file,
      null,
      'surface',
    ]], file);
  }
  assertEquals(run({ [KEYWORDS]: 'einkauf,liste,haushalt' }, live), []);
});

Deno.test('BRAND_LIVE.md: rows parse, a live row needs URL, date and proof, a missing brand is named', () => {
  const md = [
    '| Brand | Live | URL | Last verified | Proof | Texts that depend on it | Wording |',
    '| --- | --- | --- | --- | --- | --- | --- |',
    `| Siri | yes | https://x | ${TODAY} | proof/siri.png | \`${DE}\`, \`${EN}\` | - |`,
    '| Alexa | yes | - | never | - | - | - |',
    '| Claude | no | - | never | - | - | - |',
  ].join('\n');
  const { rows, problems } = parseBrandLive(md);
  assertEquals(rows.get('Siri'), {
    brand: 'Siri',
    live: true,
    verified: TODAY,
    texts: [DE, EN],
  });
  assertEquals(rows.get('Claude')?.live, false);
  assertEquals(problems.length, 2);
  assert(problems[0]?.includes('Alexa: Live yes needs'));
  assert(problems[1]?.includes('no row for ChatGPT'));
});

function repo(files: Record<string, string>): string {
  const dir = Deno.makeTempDirSync();
  for (const [path, text] of Object.entries(files)) {
    Deno.mkdirSync(`${dir}/${path.split('/').slice(0, -1).join('/')}`, {
      recursive: true,
    });
    Deno.writeTextFileSync(`${dir}/${path}`, text);
  }
  return dir;
}

const brandLive = (siri: string) =>
  [
    '| Brand | Live | URL | Last verified | Proof | Texts that depend on it | Wording |',
    `| Siri | ${siri} | - | never | - | \`${DE}\` | - |`,
    '| Alexa | no | - | never | - | - | - |',
    '| Claude | no | - | never | - | - | - |',
    '| ChatGPT | no | - | never | - | - | - |',
  ].join('\n');

const baselined = (entries: unknown[]) => JSON.stringify({ entries });
const flags = JSON.stringify({ holds: { 'native-siri': { released: false } } });

Deno.test('the baseline lets approved findings pass in CI, never on publish day, and goes stale', () => {
  const base = {
    [DE]: `Per Siri-Kurzbefehl.\n${notice.Siri}\n`,
    'docs/store/BRAND_LIVE.md': brandLive('no'),
    'releases/flags.json': flags,
  };
  const entry = {
    file: DE,
    brand: 'Siri',
    rule: 'live',
    message: 'names Siri, which docs/store/BRAND_LIVE.md does not mark live (BN-1 point 1)',
    reason: 'approved before BN-1',
  };
  const ok = repo({
    ...base,
    'scripts/store-brands.baseline.json': baselined([entry]),
  });
  assertEquals(check(ok, { publish: false, today: TODAY }), []);
  assertEquals(check(ok, { publish: true, today: TODAY }).length, 1);

  const none = repo({
    ...base,
    'scripts/store-brands.baseline.json': baselined([]),
  });
  assertEquals(check(none, { publish: false, today: TODAY }).length, 1);

  const stale = repo({
    ...base,
    [DE]: 'Ohne Marke.\n',
    'scripts/store-brands.baseline.json': baselined([entry]),
  });
  const problems = check(stale, { publish: false, today: TODAY });
  assertEquals(problems.length, 1);
  assert(problems[0]?.includes('is stale'));
});

Deno.test('a surface finding is never baselined', () => {
  const dir = repo({
    [KEYWORDS]: 'einkauf,siri\n',
    'docs/store/BRAND_LIVE.md': brandLive('no'),
    'releases/flags.json': flags,
    'scripts/store-brands.baseline.json': baselined([
      { file: KEYWORDS, brand: null, rule: 'surface', reason: 'please' },
    ]),
  });
  const problems = check(dir, { publish: false, today: TODAY });
  assert(problems.some((p) => p.includes('never baselined')));
  assert(problems.some((p) => p.startsWith(`${KEYWORDS}: names "siri"`)));
});

Deno.test('a brand in capitals or lower case is still a brand', () => {
  for (const line of ['KI-ASSISTENTEN WIE CLAUDE', 'Frag einfach claude.', 'MIT CHATGPT']) {
    const rules = run({ [DE]: line }, []).map(([, b, r]) => `${b}:${r}`);
    assert(rules.includes('Claude:live') || rules.includes('ChatGPT:live'), `${line} -> ${rules.join(', ')}`);
  }
});

Deno.test('a brand inside a feature name fails the form check', () => {
  const rules = run({ [DE]: `Mit Claude-Connector, mit Snacklist Premium.\n${notice.Claude}` }, allLive)
    .map(([, b, r]) => `${b}:${r}`);
  assertEquals(rules, ['Claude:form']);
});

Deno.test('the baseline holds exact findings: a new sentence with the same rule in a baselined file fails', () => {
  const de = `Per Siri-Kurzbefehl.\nSag es Siri.\n${notice.Siri}\n`;
  const files = {
    [DE]: de,
    'docs/store/BRAND_LIVE.md': brandLive('no'),
    'releases/flags.json': flags,
  };
  const old = findings({
    texts: new Map([[DE, de.replace(/\n$/, '')]]),
    rows: new Map([['Siri', row('Siri', false, null, [DE])]]),
    today: TODAY,
    publish: false,
    nativeSiri: false,
  }).map((f) => ({ ...f, reason: 'approved before BN-1' }));
  const dir = repo({ ...files, 'scripts/store-brands.baseline.json': baselined(old) });
  assertEquals(check(dir, { publish: false, today: TODAY }), []);

  Deno.writeTextFileSync(`${dir}/${DE}`, `Per Siri-Kurzbefehl.\nSag es Siri.\nFrag Siri.\n${notice.Siri}\n`);
  const problems = check(dir, { publish: false, today: TODAY });
  assert(problems.some((p) => p.includes('Frag Siri.')), problems.join('\n'));
  assert(problems.some((p) => p.includes('3 times')), problems.join('\n'));
});

Deno.test('a brand glued into a compound on a never surface fails', () => {
  for (
    const [file, text] of [
      ['app/fastlane/metadata/de-DE/name.txt', 'Snacklist – Alexaliste'],
      [KEYWORDS, 'einkaufsliste,alexaliste,claudeapp'],
      ['app/fastlane/metadata/de-DE/subtitle.txt', 'Liste für Amazons Skill'],
    ] as [string, string][]
  ) {
    assertEquals(run({ [file]: text }, allLive), [[file, null, 'surface']], file);
  }
});

Deno.test('a notice sentence or the ChatGPT qualifier alone still names a brand', () => {
  const rules = (de: string) => run({ [DE]: de }, []).map(([, b, r]) => `${b}:${r}`);
  assert(rules(`Einkaufen zu zweit.\n${notice.Claude}`).includes('Claude:live'));
  assert(rules('Abrechnung je nach ChatGPT-Tarif und Land.').includes('ChatGPT:live'));
});

Deno.test('a brand without a BN-1 row fails in a description (point 9)', () => {
  assertEquals(run({ [DE]: 'Auch mit Gemini und Google Assistant.' }, allLive), [[DE, null, 'unknown']]);
});

Deno.test('Siri-Kurzbefehl needs „per“ and stays out of a feature name', () => {
  const rules = (de: string) => run({ [DE]: `${de}\n${notice.Siri}` }, allLive).map(([, b, r]) => `${b}:${r}`);
  assertEquals(rules('Die Siri-Kurzbefehl-Funktion.'), ['Siri:form']);
  assertEquals(rules('Mit einem Siri-Kurzbefehl.'), ['Siri:form']);
});

Deno.test('a possessive, plural or spaced brand in a description still names it while not live', () => {
  const probes: [string, Brand][] = [
    ['Für Claudes Nutzer.', 'Claude'],
    ['Nutze Snacklist mit Anthropics KI.', 'Claude'],
    ['ChatGPTs Nutzer lieben Snacklist.', 'ChatGPT'],
    ['Nutze Snacklist mit OpenAIs Modellen.', 'ChatGPT'],
    ['Jetzt in Chat GPT.', 'ChatGPT'],
    ['Läuft mit GPT-5 von Open AI.', 'ChatGPT'],
  ];
  const notLive = [row('Claude', false, null), row('ChatGPT', false, null)];
  for (const [line, brand] of probes) {
    const rules = run({ [DE]: `${line}\nEinkaufen zu zweit.` }, notLive).map(([, b, r]) => `${b}:${r}`);
    assert(rules.includes(`${brand}:live`), `${line} -> ${rules.join(', ')}`);
  }
});

Deno.test('a possessive or plural brand fails BN-1 point 4 even when live', () => {
  const cases: [string, Brand][] = [
    ['Für Claudes Nutzer, mit Snacklist Premium.', 'Claude'],
    ['Für ChatGPTs Nutzer, mit Snacklist Premium, je nach ChatGPT-Tarif und Land.', 'ChatGPT'],
    ["Snacklist in Siri's Shortcuts.", 'Siri'],
    ['Siris Kurzbefehl, per Siri-Kurzbefehl.', 'Siri'],
    ['Alexas Liste im Snacklist-Skill für Amazon Alexa.', 'Alexa'],
  ];
  for (const [line, brand] of cases) {
    const found = findings({
      texts: new Map([[DE, `${line}\n${notice[brand]}`]]),
      rows: new Map(allLive.map((r) => [r.brand, r])),
      today: TODAY,
      publish: false,
      nativeSiri: false,
    });
    assert(
      found.some((f) => f.brand === brand && f.rule === 'phrasing' && f.message.includes('point 4: never')),
      `${line} -> ${found.map((f) => f.message).join(' / ')}`,
    );
  }
});

Deno.test('other makers’ product names stay generic-only (point 9)', () => {
  for (const line of ['Auch auf dem Amazon Echo.', 'Mit Apple CarPlay.', 'Läuft mit GPT-5.']) {
    const rules = run({ [DE]: line }, allLive).map(([, b, r]) => `${b}:${r}`);
    assert(rules.includes('null:unknown'), `${line} -> ${rules.join(', ')}`);
  }
  assertEquals(run({ [DE]: `Snacklist in ChatGPT, mit Snacklist Premium, je nach ChatGPT-Tarif und Land.\n${notice.ChatGPT}` }, allLive), []);
});
