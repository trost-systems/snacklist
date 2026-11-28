// AC11 and the skill package's structure (alexa/skill-package, alexa/account-linking.json): the
// rules ASK CLI's and certification's checks apply, checked locally since nothing here talks to
// Amazon (docs/ALEXA.md, "Skill package"; docs/ALEXA_CERTIFICATION.md).
import { assert, assertEquals, assertFalse } from '@std/assert';
import skill from '../../../alexa/skill-package/skill.json' with { type: 'json' };
import deDE from '../../../alexa/skill-package/interactionModels/custom/de-DE.json' with {
  type: 'json',
};
import enUS from '../../../alexa/skill-package/interactionModels/custom/en-US.json' with {
  type: 'json',
};
import enGB from '../../../alexa/skill-package/interactionModels/custom/en-GB.json' with {
  type: 'json',
};
import enAU from '../../../alexa/skill-package/interactionModels/custom/en-AU.json' with {
  type: 'json',
};
import enCA from '../../../alexa/skill-package/interactionModels/custom/en-CA.json' with {
  type: 'json',
};
import enIN from '../../../alexa/skill-package/interactionModels/custom/en-IN.json' with {
  type: 'json',
};
import linking from '../../../alexa/account-linking.json' with { type: 'json' };
import resources from '../../../alexa/ask-resources.json' with { type: 'json' };
import { createHandler, type Deps } from './handler.ts';
import { speech } from './speech.ts';
import { speechEnglish } from './speech_en.ts';
import { speechFor } from './voices.ts';
import { testSkillId } from './test_ca.ts';

type Model = typeof deDE;
const models: Record<string, Model> = {
  'de-DE': deDE,
  'en-US': enUS,
  'en-GB': enGB,
  'en-AU': enAU,
  'en-CA': enCA,
  'en-IN': enIN,
};
const englishLocales = ['en-US', 'en-GB', 'en-AU', 'en-CA', 'en-IN'];
const publishing = skill.manifest.publishingInformation;
const localeInfo = (locale: string) =>
  (publishing.locales as Record<string, typeof publishing.locales['de-DE']>)[locale];
const language = (locale: string) => models[locale].interactionModel.languageModel;

/** Every string anywhere in a JSON value. */
const strings = (value: unknown): string[] =>
  typeof value === 'string'
    ? [value]
    : Array.isArray(value)
    ? value.flatMap(strings)
    : value && typeof value === 'object'
    ? Object.values(value).flatMap(strings)
    : [];

Deno.test('AC11 (S4): skill name "Snacklist", invocation name "snacklist", no Hummlist left', () => {
  assertEquals(Object.keys(publishing.locales), Object.keys(models));
  for (const locale of Object.keys(models)) {
    assertEquals(localeInfo(locale).name, 'Snacklist', locale);
    assertEquals(language(locale).invocationName, 'snacklist', locale);
  }
  // S4 rename: the package names Snacklist only. The one exception is the old app host
  // app.hummlist.com in the account-linking domains, kept while Hummlist builds are alive (S5).
  const { domains, ...request } = linking.accountLinkingRequest;
  assertEquals(domains, [
    'app.snacklist.app',
    'app.hummlist.com',
    'jdwqrallbpdbshrdhenk.supabase.co',
  ]);
  for (const text of [...strings(skill), ...strings(models), ...strings(request)]) {
    assertFalse(/humm/i.test(text), `Hummlist left in: ${text}`);
  }
});

Deno.test('the English locales share one model', () => {
  for (const locale of englishLocales) assertEquals(models[locale], enUS, locale);
});

Deno.test('Alexa is not Premium: the package and every reply never mention Premium or unlocking', () => {
  for (
    const text of [
      ...strings(skill),
      ...strings(models),
      ...strings(speech),
      ...strings(speechEnglish),
    ]
  ) {
    assertFalse(/premium|freischalt|unlock/i.test(text), text);
  }
});

Deno.test('the testing instructions cover every language and hold no credentials', () => {
  const text = publishing.testingInstructions;
  assert(text.length <= 4000, 'at most 4000 characters');
  for (const phrase of ['Alexa, sag Snacklist', 'Alexa, ask Snacklist', 'test-account field']) {
    assert(text.includes(phrase), phrase);
  }
  assertFalse(/passw(?:or)?t?\s*[:=]\s*[^\s<]/i.test(text), 'no password in the repo');
  assertFalse(
    /@(?!snacklist\.app\b)[\w-]+\.\w+/.test(text),
    'no test account address',
  );
});

Deno.test('manifestVersion sits inside manifest, where ask deploy keeps it', () => {
  // At the top level, ask deploy uploaded the manifest without it (job 31b).
  assertEquals(Object.keys(skill), ['manifest']);
  assertEquals(skill.manifest.manifestVersion, '1.0');
});

Deno.test('worldwide, with a privacy policy per locale and no terms until the page is live', () => {
  assertEquals(publishing.isAvailableWorldwide, true);
  assertFalse('distributionCountries' in publishing, 'worldwide takes no country list');
  const privacy = skill.manifest.privacyAndCompliance.locales as Record<string, object>;
  assertEquals(Object.keys(privacy), Object.keys(models));
  for (const locale of Object.keys(models)) {
    assertEquals(privacy[locale], {
      privacyPolicyUrl: locale === 'de-DE'
        ? 'https://snacklist.app/datenschutz'
        : 'https://snacklist.app/en/privacy',
    }, locale);
  }
  const compliance = skill.manifest.privacyAndCompliance;
  assertEquals(compliance.allowsPurchases, false);
  assertEquals(compliance.containsAds, false);
  assertEquals(compliance.isChildDirected, false);
});

Deno.test('the manifest points Alexa and skill events at the alexa function', () => {
  const endpoint =
    'https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/alexa?forceFunctionRegion=eu-central-1';
  assertEquals(skill.manifest.apis.custom.endpoint, {
    uri: endpoint,
    sslCertificateType: 'Wildcard',
  });
  assertEquals(skill.manifest.events.endpoint.uri, endpoint);
  assertEquals(
    skill.manifest.events.subscriptions.map((s) => s.eventName).sort(),
    ['SKILL_ACCOUNT_LINKED', 'SKILL_DISABLED'],
  );
  assertEquals(resources.profiles.default.skillMetadata.src, './skill-package');
  for (const locale of Object.keys(models)) {
    const info = localeInfo(locale);
    assertEquals(
      [info.smallIconUri, info.largeIconUri],
      [
        'file://assets/images/de-DE_smallIconUri.png',
        'file://assets/images/de-DE_largeIconUri.png',
      ],
      `${locale}: the icons design/app-icon/build.mjs writes`,
    );
    assert(info.summary.length <= 160, `${locale} summary: at most 160 characters`);
    assert(info.description.length <= 4000, `${locale} description: at most 4000 characters`);
    assert(info.keywords.length <= 30, `${locale} keywords: at most 30`);
  }
});

/** A sample as Alexa matches it: lowercase words, slots as {name}. */
const words = (sample: string) =>
  sample.toLowerCase().replace(/[,.!?]/g, '').split(/\s+/).filter(Boolean);

function matchesSample(phrase: string, samples: readonly string[]): boolean {
  const said = words(phrase);
  return samples.some((sample) => {
    const pattern = words(sample).map((w) =>
      w.startsWith('{') ? '(.+)' : w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    );
    return new RegExp(`^${pattern.join(' ')}$`).test(said.join(' '));
  });
}

/** "Alexa, <verb> snacklist, <rest>" (de) or "Alexa, <verb> snacklist [to] <rest>" (en). */
const examplePattern: Record<'de' | 'en', RegExp> = {
  de: /^Alexa, (?:sag|frag|öffne|starte) snacklist(?:, (.+))?$/,
  en: /^Alexa, (?:ask|tell|open|launch|start) snacklist(?: (?:to )?(.+))?$/,
};
const lang = (locale: string) => (locale.startsWith('en') ? 'en' : 'de');

Deno.test('every example phrase has the invocation shape and matches a sample', () => {
  for (const locale of Object.keys(models)) {
    const phrases = localeInfo(locale).examplePhrases;
    assert(phrases.length >= 1 && phrases.length <= 3, locale);
    const samples = language(locale).intents.flatMap((i) => i.samples);
    for (const phrase of phrases) {
      const m = examplePattern[lang(locale)].exec(phrase);
      assert(m, `${locale} example phrase shape: ${phrase}`);
      if (m[1]) assert(matchesSample(m[1], samples), `${locale}: no sample matches "${m[1]}"`);
    }
  }
  // The spec's own sentences.
  const de = language('de-DE').intents.flatMap((i) => i.samples);
  assert(matchesSample('füg Milch und Eier hinzu', de));
  assert(matchesSample('was auf der Liste steht', de));
});

const oneShots: Record<'de' | 'en', string[]> = {
  de: [
    'ich brauche Milch',
    'ich brauche noch Milch',
    'wir brauchen Milch',
    'füg Milch hinzu',
    'füge Milch hinzu',
    'füg noch Milch hinzu',
    'setz Milch drauf',
    'setze Milch drauf',
    'pack Milch drauf',
    'schreib Milch drauf',
    'setz Milch auf die Liste',
    'schreib Milch auf',
  ],
  en: [
    'add milk',
    'add milk and eggs to the list',
    'add milk to my shopping list',
    'put milk on the list',
    'we need milk',
    'i need milk',
    "we're out of milk",
    'write down milk',
  ],
};

Deno.test('common one-shot requests after the invocation reach AddItemIntent', () => {
  for (const locale of Object.keys(models)) {
    const add = language(locale).intents.find((i) => i.name === 'AddItemIntent')!.samples;
    for (const rest of oneShots[lang(locale)]) {
      assert(matchesSample(rest, add), `${locale}: no AddItemIntent sample matches "${rest}"`);
    }
  }
});

Deno.test('the interaction models: required built-ins, one SearchQuery with carrier phrases', () => {
  for (const locale of Object.keys(models)) {
    const intents = language(locale).intents;
    const names = intents.map((i) => i.name);
    for (
      const required of [
        'AMAZON.HelpIntent',
        'AMAZON.StopIntent',
        'AMAZON.CancelIntent',
        'AMAZON.NavigateHomeIntent',
        'AMAZON.FallbackIntent',
        'AddItemIntent',
        'AddToListIntent',
        'ReadListIntent',
      ]
    ) assert(names.includes(required), `${locale}: ${required}`);
    assertEquals(new Set(names).size, names.length);

    const add = intents.find((i) => i.name === 'AddItemIntent')!;
    assertEquals(add.slots, [{ ...add.slots![0], name: 'items', type: 'AMAZON.SearchQuery' }]);
    const allowed = lang(locale) === 'de' ? /^[a-zäöüß{} ]+$/ : /^[a-z'{} ]+$/;
    const seen = new Set<string>();
    for (const [intent, sample] of intents.flatMap((i) => i.samples.map((s) => [i.name, s]))) {
      assert(allowed.test(sample), `${locale}: letters, spaces and slots only: "${sample}"`);
      assertFalse(seen.has(sample), `${locale}: sample used twice: "${sample}"`);
      seen.add(sample);
      const slots = sample.match(/\{(\w+)\}/g) ?? [];
      if (intent === 'AddItemIntent') {
        assertEquals(slots, ['{items}'], sample);
        assert(words(sample).length > 1, `SearchQuery needs a carrier phrase: "${sample}"`);
      } else if (intent === 'AddToListIntent') {
        // A SearchQuery may be the only slot of a sample, so the list gets its own intent (job 207).
        // The phrase slot is itemphrase: Amazon forbids the name `items` with two types.
        assertEquals(slots, ['{itemphrase}', '{list}'], sample);
      } else {
        assertEquals(slots, [], sample);
      }
    }
    // Slot samples (answers to "Was soll auf die Liste?") may be the slot alone.
    assert(add.slots![0].samples!.includes('{items}'), locale);
  }
});

Deno.test('the dialog models elicit the items with the prompt the handler speaks', () => {
  for (const locale of Object.keys(models)) {
    const model = models[locale].interactionModel;
    for (const name of ['AddItemIntent', 'AddToListIntent']) {
      const dialog = model.dialog.intents.find((i) => i.name === name)!;
      const slot = dialog.slots[0];
      assertEquals(slot.name, name === 'AddToListIntent' ? 'itemphrase' : 'items');
      const prompt = model.prompts.find((p) => p.id === slot.prompts.elicitation);
      assertEquals(
        prompt?.variations[0].value,
        speechFor(locale).speech.launch,
        `${locale} ${name}`,
      );
    }
  }
});

Deno.test('AddToListIntent: items and a list name in custom slot types the model defines (job 207)', () => {
  for (const locale of Object.keys(models)) {
    const model = language(locale);
    const intent = model.intents.find((i) => i.name === 'AddToListIntent')!;
    assertEquals(intent.slots?.map((s) => [s.name, s.type]), [
      ['itemphrase', 'ITEM_PHRASE'],
      ['list', 'LIST_NAME'],
    ]);
    const types = new Map(model.types.map((t) => [t.name, t.values.map((v) => v.name.value)]));
    for (const type of ['ITEM_PHRASE', 'LIST_NAME']) {
      const values = types.get(type) ?? [];
      assert(values.length >= 5, `${locale} ${type}: sample values`);
      assertEquals(
        new Set(values.map((v) => v.toLowerCase())).size,
        values.length,
        `${locale} ${type}`,
      );
    }
    // The dialog model names the same slots with the same types.
    const dialog = models[locale].interactionModel.dialog.intents.find((i) =>
      i.name === 'AddToListIntent'
    )!;
    assertEquals(dialog.slots.map((s) => [s.name, s.type]), [
      ['itemphrase', 'ITEM_PHRASE'],
      ['list', 'LIST_NAME'],
    ]);
  }
});

Deno.test('a slot name keeps one type across the skill (Amazon model build)', () => {
  for (const locale of Object.keys(models)) {
    const types = new Map<string, string>();
    for (const intent of language(locale).intents) {
      for (const slot of intent.slots ?? []) {
        const prev = types.get(slot.name);
        assertEquals(
          prev ?? slot.type,
          slot.type,
          `${locale}: slot "${slot.name}" has types ${prev} and ${slot.type}`,
        );
        types.set(slot.name, slot.type);
      }
    }
  }
});

const listShots: Record<'de' | 'en', string[]> = {
  de: [
    // Peter's sentence after "Alexa, öffne Snacklist".
    'füge Luftballons zur Geburtstag Liste hinzu',
    'füge Luftballons auf die Geburtstag Liste hinzu',
    'füge Luftballons zu Geburtstag hinzu',
    'setz Schrauben auf die Baumarkt Liste',
    'pack Chips auf die Party Liste',
    'schreib Milch auf die Alltag Liste',
  ],
  en: [
    'add balloons to the birthday list',
    'add balloons to birthday',
    'add balloons onto the birthday list',
  ],
};

Deno.test('requests that name a list reach AddToListIntent', () => {
  for (const locale of Object.keys(models)) {
    const add = language(locale).intents.find((i) => i.name === 'AddToListIntent')!.samples;
    for (const rest of listShots[lang(locale)]) {
      assert(matchesSample(rest, add), `${locale}: no AddToListIntent sample matches "${rest}"`);
    }
  }
});

Deno.test('every intent of each model has its own answer in the handler', async () => {
  const deps = {
    verify: (_h: Headers, body: Uint8Array) =>
      Promise.resolve(JSON.parse(new TextDecoder().decode(body))),
    authenticate: () => Promise.resolve({ userId: 'u', householdId: 'h', sessionId: 's' }),
    takeAdds: () => Promise.resolve(true),
    lists: () =>
      Promise.resolve({
        lists: [{ id: 'l', name: 'Einkaufsliste', seedKey: 'main' }],
        defaultList: { id: 'l', name: 'Einkaufsliste', seedKey: 'main' },
      }),
    addItems: () => Promise.resolve([]),
    listItems: () => Promise.resolve([]),
    remember: () => Promise.resolve(),
    revoke: () => Promise.resolve(),
    counted: () => Promise.resolve(),
    report: () => {},
    log: () => {},
  } as unknown as Deps;
  const handler = createHandler(deps);
  for (const locale of Object.keys(models)) {
    const { speech } = speechFor(locale);
    for (const intent of language(locale).intents) {
      const res = await handler(
        new Request('http://local/alexa', {
          method: 'POST',
          body: JSON.stringify({
            version: '1.0',
            context: {
              System: { application: { applicationId: testSkillId }, user: { accessToken: 't' } },
            },
            request: {
              type: 'IntentRequest',
              locale,
              timestamp: new Date().toISOString(),
              intent: {
                name: intent.name,
                slots: intent.name === 'AddToListIntent'
                  ? { itemphrase: { name: 'itemphrase', value: 'Milch' } }
                  : { items: { name: 'items', value: 'Milch' } },
              },
            },
          }),
        }),
      );
      const text = (await res.json()).response.outputSpeech.text as string;
      if (intent.name === 'AMAZON.FallbackIntent') {
        assertEquals(text, speech.notUnderstoodOnce, locale);
      } else assert(text !== speech.notUnderstoodOnce, `${locale} ${intent.name} is not handled`);
    }
  }
});

Deno.test('account linking: auth code with PKCE S256 against Supabase Auth, no secret in the repo', () => {
  const request = linking.accountLinkingRequest;
  assertEquals(request.type, 'AUTH_CODE');
  assertEquals(
    request.authorizationUrl,
    'https://jdwqrallbpdbshrdhenk.supabase.co/auth/v1/oauth/authorize',
  );
  assertEquals(
    request.accessTokenUrl,
    'https://jdwqrallbpdbshrdhenk.supabase.co/auth/v1/oauth/token',
  );
  assertEquals(request.accessTokenScheme, 'HTTP_BASIC');
  assertEquals(request.pkceConfiguration, { status: 'ENABLED', codeChallengeMethod: 'S256' });
  assertFalse('clientSecret' in request, 'the client secret is set at deploy time only');
  assertEquals(request.clientId, 'REPLACE_WITH_CLIENT_ID');
});
