import { assertEquals } from '@std/assert';
import { maxItems } from './parse.ts';
import { parseEnglish, spokenEnglish } from './parse_en.ts';

/** Sentence -> items as read back ("2 cucumbers"). */
const cases: [string, string[]][] = [
  ['milk, eggs and bread', ['milk', 'eggs', 'bread']],
  // Job 256: English in-app dictation on Android sends these.
  ['milk, two bananas and bread', ['milk', '2 bananas', 'bread']],
  ['add eggs', ['eggs']],
  ['milk, eggs, and bread', ['milk', 'eggs', 'bread']],
  ['Milk, eggs and bread.', ['Milk', 'eggs', 'bread']],
  ['two cucumbers and a pack of eggs', ['2 cucumbers', '1 pack of eggs']],
  ['add milk to Hummlist', ['milk']],
  ['Add milk to my Hummlist', ['milk']],
  // Job 71: how English Siri may write the app name (INAlternativeAppNames).
  ['add milk to my Humm List', ['milk']],
  ['put milk on the hum list', ['milk']],
  ['add milk to Humlist', ['milk']],
  // Job 174: Snacklist's names.
  ['add milk to Snacklist', ['milk']],
  ['put milk on my Snack List', ['milk']],
  ['add milk and eggs to the snack-list', ['milk', 'eggs']],
  ['add milk to my shopping list', ['milk']],
  ['put eggs on the list please', ['eggs']],
  ['Hey Siri, add milk', ['milk']],
  ['we need milk plus eggs', ['milk', 'eggs']],
  ['I need bread, also butter', ['bread', 'butter']],
  ['cheese as well as crackers', ['cheese', 'crackers']],
  ["we're out of coffee", ['coffee']],
  ["don't forget the bananas", ['bananas']],
  ['some apples', ['apples']],
  ['an apple', ['apple']],
  ['a couple of lemons', ['a couple of lemons']],
  ['a few onions', ['a few onions']],
  ['twelve eggs', ['12 eggs']],
  // A count said after the item is its quantity, like one said before it (job 89).
  ['cucumbers two', ['2 cucumbers']],
  ['cucumbers 2', ['2 cucumbers']],
  ['two cucumbers', ['2 cucumbers']],
  ['add cucumbers two to my list', ['2 cucumbers']],
  ['milk, cucumbers two and bread', ['milk', '2 cucumbers', 'bread']],
  ['diapers size 4', ['diapers size 4']],
  ['cucumbers a', ['cucumbers a']],
  ['a dozen eggs', ['1 dozen eggs']],
  ['two dozen eggs', ['2 dozen eggs']],
  ['3 bottles of wine', ['3 bottles of wine']],
  ['one bottle of wine', ['1 bottle of wine']],
  ['2 kg of potatoes', ['2 kg of potatoes']],
  ['500g flour', ['500 g of flour']],
  ['1.5 liters of milk', ['1.5 l of milk']],
  ['two litres of juice', ['2 l of juice']],
  ['a loaf of bread and two packs of butter', ['1 loaf of bread', '2 packs of butter']],
  ['mac and cheese', ['mac and cheese']],
  ['mac and cheese and milk', ['mac and cheese', 'milk']],
  ['half and half, salt and pepper', ['half and half', 'salt', 'pepper']],
  ['milk and milk', ['milk']],
  ['milk & eggs; bread', ['milk', 'eggs', 'bread']],
  ['Milk', ['Milk']],
  ['please, thanks', []],
  ['um uh', []],
  ['add to Hummlist', []],
  ['12', []],
  ['', []],
];

for (const [sentence, expected] of cases) {
  Deno.test(`EN "${sentence}" -> ${JSON.stringify(expected)}`, () => {
    assertEquals(parseEnglish(sentence).map(spokenEnglish), expected);
  });
}

Deno.test('EN keeps the quantity apart from the name', () => {
  assertEquals(parseEnglish('two cucumbers and a pack of eggs'), [
    { name: 'cucumbers', quantity: '2' },
    { name: 'eggs', quantity: '1 pack' },
  ]);
});

const spokenCounts: [string, string][] = [
  ['one', '1'],
  ['two', '2'],
  ['three', '3'],
  ['four', '4'],
  ['five', '5'],
  ['six', '6'],
  ['seven', '7'],
  ['eight', '8'],
  ['nine', '9'],
  ['ten', '10'],
  ['eleven', '11'],
  ['twelve', '12'],
  ['twenty', '20'],
  ['thirty', '30'],
];
for (const [word, count] of spokenCounts) {
  Deno.test(`EN "cucumbers ${word}" and "cucumbers ${count}" are ${count} cucumbers`, () => {
    const expected = [{ name: 'cucumbers', quantity: count }];
    assertEquals(parseEnglish(`cucumbers ${word}`), expected);
    assertEquals(parseEnglish(`cucumbers ${count}`), expected);
    assertEquals(parseEnglish(`${word} cucumbers`), expected);
  });
}

Deno.test('EN stops at the item cap', () => {
  const sentence = Array.from({ length: 40 }, (_, i) => `thing${i}`).join(', ');
  assertEquals(parseEnglish(sentence).length, maxItems);
  assertEquals(parseEnglish(sentence, maxItems + 1).length, maxItems + 1);
});

// Job 159: a name that starts with a number word keeps it, as typed (job 104).
for (
  const [sentence, expected] of [
    ['seven up and four roses', ['seven up', 'four roses']],
    ['two seven up', ['2 seven up']],
    ['seven apples', ['7 apples']],
  ] as [string, string[]][]
) {
  Deno.test(`"${sentence}" -> ${JSON.stringify(expected)}`, () => {
    assertEquals(parseEnglish(sentence).map(spokenEnglish), expected);
  });
}
