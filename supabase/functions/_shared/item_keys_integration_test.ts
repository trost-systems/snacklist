// Job 470: public.item_key and public.fold_key write supabase/tests/item_keys.tsv, German, English
// and the letters of other languages (folded, never a split word), as the app's itemKey and foldKey
// do (app/test/list/item_key_test.dart checks that side). The db gate sets FG_DB_TEST=1 and
// SUPABASE_DB_URL to the local stack; without FG_DB_TEST the test is skipped.
import { assertEquals } from '@std/assert';
import postgres from 'postgres';
import { databaseUrl } from './db.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

Deno.test({
  name: 'public.item_key and fold_key are supabase/tests/item_keys.tsv',
  ignore: !enabled,
  sanitizeResources: false,
  fn: async () => {
    const rows = (await Deno.readTextFile(new URL('../../tests/item_keys.tsv', import.meta.url)))
      .split('\n')
      .filter((line) => line.trim() !== '' && !line.startsWith('#'))
      .map((line) => line.split('\t'));
    const sql = postgres(databaseUrl(), { max: 1, prepare: false });
    try {
      const actual = await sql<{ name: string; key: string; folded: string }[]>`
        select n as name, public.item_key(n) as key, public.fold_key(public.item_key(n)) as folded
        from jsonb_array_elements_text(${JSON.stringify(rows.map(([name]) => name))}::text::jsonb)
          with ordinality t (n, ord)
        order by ord`;
      assertEquals(actual.map((r) => [r.name, r.key, r.folded]), rows);
    } finally {
      await sql.end();
    }
  },
});
