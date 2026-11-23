// Legal N-423: the household-add alert never names an item of a pharmacy. The words that make a
// store a pharmacy are listed in supabase/tests/pharmacy_words.json, which the app's Store
// .pharmacyWords is pinned to (app/test/push/pharmacy_words_test.dart). The pgTAP file
// supabase/tests/push_household_add.test.sql compares the functions in the database with its
// `pharmacy words` line; this pins that line to the JSON, so the lists cannot drift.
import { assertEquals } from '@std/assert';

const words: string[] = JSON.parse(
  Deno.readTextFileSync(new URL('../../tests/pharmacy_words.json', import.meta.url)),
);

Deno.test('the pgTAP pharmacy words line is the list of pharmacy_words.json', () => {
  const sql = Deno.readTextFileSync(
    new URL('../../tests/push_household_add.test.sql', import.meta.url),
  );
  const line = /^-- pharmacy words: ([a-z|]+)$/m.exec(sql);
  assertEquals((line?.[1] ?? '').split('|').sort(), [...words].sort());
});
