import { assert, assertEquals } from '@std/assert';
import { BASELINE, check, importsIn } from './import-direction.ts';

function repo(files: Record<string, string>, baseline?: string[]): string {
  const dir = Deno.makeTempDirSync();
  const all: Record<string, string> = {};
  for (const [path, text] of Object.entries(files)) {
    all[`app/lib/${path}`] = text;
  }
  if (baseline) all[BASELINE] = `# header\n${baseline.join('\n')}\n`;
  for (const [path, text] of Object.entries(all)) {
    Deno.mkdirSync(`${dir}/${path.split('/').slice(0, -1).join('/')}`, {
      recursive: true,
    });
    Deno.writeTextFileSync(`${dir}/${path}`, text);
  }
  return dir;
}

const imports = (...paths: string[]) =>
  paths.map((p) => `import 'package:family_groceries/${p}';\n`).join('');
const clean = {
  'main.dart': imports('shell/app.dart', 'list/model.dart'),
  'shell/app.dart': imports(
    'list/list_screen.dart',
    'household/page.dart',
    'core/theme.dart',
  ),
  'core/theme.dart': imports('design/tokens.dart'),
  'design/tokens.dart': '',
  'list/model.dart': '',
  'list/list_screen.dart': imports(
    'list/model.dart',
    'core/theme.dart',
    'session/s.dart',
  ),
  'household/page.dart': imports('core/theme.dart'),
  'session/s.dart': '',
};

Deno.test('the layer rules pass a tree that keeps them', () => {
  assertEquals(check(repo(clean), undefined), []);
});

Deno.test('a feature importing another feature fails and names the fix', () => {
  const problems = check(
    repo({ ...clean, 'household/page.dart': imports('list/model.dart') }),
    undefined,
  );
  assertEquals(problems.length, 1);
  assert(
    problems[0]?.startsWith(
      'app/lib/household/page.dart imports list/model.dart: feature',
    ),
  );
  assert(problems[0]?.includes('let the shell wire them'));
});

Deno.test('core importing a feature fails', () => {
  const problems = check(
    repo({ ...clean, 'core/theme.dart': imports('list/model.dart') }),
    undefined,
  );
  assertEquals(problems.length, 1);
  assert(problems[0]?.includes('core folder core/ imports the feature list/'));
});

Deno.test('a feature or core importing the shell fails', () => {
  const problems = check(
    repo({
      ...clean,
      'household/page.dart': imports('shell/app.dart'),
      'design/tokens.dart': imports('shell/app.dart'),
    }),
    undefined,
  );
  assertEquals(problems.length, 2);
  assert(problems.every((p) => p.includes('imports the shell (shell/)')));
});

Deno.test('a folder without a layer fails', () => {
  const problems = check(repo({ ...clean, 'newthing/a.dart': '' }), undefined);
  assertEquals(problems, [
    'app/lib/newthing/ has no layer: add it to LAYERS in scripts/import-direction.ts ' +
    '(core, feature or shell; docs/DECISIONS.md job 305 says which is which).',
  ]);
});

Deno.test('a listed import passes, a listed import that is gone is stale', () => {
  const tree = { ...clean, 'household/page.dart': imports('list/model.dart') };
  assertEquals(
    check(repo(tree, ['household/page.dart -> list/model.dart']), undefined),
    [],
  );
  assertEquals(
    check(repo(clean, ['household/page.dart -> list/model.dart']), undefined),
    [
      `${BASELINE}: "household/page.dart -> list/model.dart" no longer occurs. Delete the line.`,
    ],
  );
});

Deno.test('the baseline may not grow for a pair of folders, but a file may move', () => {
  const tree = {
    ...clean,
    'household/page.dart': imports('list/model.dart', 'list/list_screen.dart'),
  };
  const both = [
    'household/page.dart -> list/list_screen.dart',
    'household/page.dart -> list/model.dart',
  ];
  const base = 'household/old.dart -> list/model.dart\n';
  const problems = check(repo(tree, both), base);
  assertEquals(problems.length, 1);
  assert(
    problems[0]?.includes(
      '2 lines for household -> list, the base branch has 1',
    ),
  );

  const moved = { ...clean, 'household/page.dart': imports('list/model.dart') };
  assertEquals(
    check(repo(moved, ['household/page.dart -> list/model.dart']), base),
    [],
  );
});

Deno.test('conditional, relative and export directives count; comments and dart: do not', () => {
  const source = [
    "import 'dart:async';",
    "// import 'package:family_groceries/trip/a.dart';",
    "import 'package:family_groceries/core/x.dart' // not 'package:family_groceries/log/c.dart'",
    "    /* nor 'package:family_groceries/log/d.dart' */",
    "    if (dart.library.js_interop) 'package:family_groceries/trip/web.dart';",
    "export '../household/h.dart';",
    "import 'same.dart';",
  ].join('\n');
  assertEquals(importsIn('list/a.dart', source).map((i) => i.to), [
    'core/x.dart',
    'trip/web.dart',
    'household/h.dart',
    'list/same.dart',
  ]);
});
