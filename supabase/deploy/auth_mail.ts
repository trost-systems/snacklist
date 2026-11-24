// Puts the auth mail sender name, subjects and templates from supabase/config.toml ([auth.email.template.*])
// onto the hosted project, so production sends the same German or English mails as the local
// stack (docs/AUTH.md "Mail language"). Converges: rerunning changes nothing.
//
// Usage: deno run --allow-read --allow-env --allow-net --config supabase/deploy/deno.json \
//          supabase/deploy/auth_mail.ts [--dry-run]
// Env: SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF. Prints only which keys change.
import { parse } from '@std/toml';

/** The templates the app's flows send; each has a German and an English branch. */
export const templates = [
  'confirmation',
  'magic_link',
  'recovery',
  'email_change',
  'invite',
  'reauthentication',
] as const;

/** The From display name Auth mail goes out under. */
export const senderName = 'Snacklist';

type Config = {
  auth?: { email?: { template?: Record<string, { subject?: string; content_path?: string }> } };
};

/** The Management API's subject and content keys for every template in config.toml. */
export async function desired(
  root: URL = new URL('../../', import.meta.url),
): Promise<Record<string, string>> {
  const config = parse(
    await Deno.readTextFile(new URL('supabase/config.toml', root)),
  ) as Config;
  // The From display name of every Auth mail; the address stays hello@ (Resend, docs/AUTH.md).
  const out: Record<string, string> = { 'smtp_sender_name': senderName };
  for (const name of templates) {
    const t = config.auth?.email?.template?.[name];
    if (!t?.subject || !t.content_path) {
      throw new Error(`[auth.email.template.${name}] needs subject and content_path`);
    }
    out[`mailer_subjects_${name}`] = t.subject;
    out[`mailer_templates_${name}_content`] = await Deno.readTextFile(
      new URL(t.content_path.replace(/^\.\//, ''), root),
    );
  }
  return out;
}

/** The keys whose template still holds a line nobody approved (emails/, `data-hl-draft`). */
export function drafts(keys: Record<string, string>): string[] {
  return Object.keys(keys).filter((k) => keys[k]?.includes('data-hl-draft'));
}

if (import.meta.main) {
  const dryRun = Deno.args.includes('--dry-run');
  const token = Deno.env.get('SUPABASE_ACCESS_TOKEN');
  const ref = Deno.env.get('SUPABASE_PROJECT_REF');
  if (!token || !ref) {
    console.error(
      'usage: auth_mail.ts [--dry-run]; needs SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF',
    );
    Deno.exit(1);
  }
  const api = `https://api.supabase.com/v1/projects/${ref}/config/auth`;
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const res = await fetch(api, { headers });
  if (!res.ok) throw new Error(`GET config/auth ${res.status}`);
  const current = await res.json() as Record<string, unknown>;
  const next = await desired();
  const changed = Object.keys(next).filter((k) => current[k] !== next[k]);
  for (const k of changed) console.log(`${k}: changes`);
  if (!changed.length) console.log('auth mail templates already up to date');
  if (dryRun || !changed.length) Deno.exit(0);
  const unapproved = drafts(next);
  if (unapproved.length) {
    console.error(
      `not applied: draft lines in ${
        unapproved.join(', ')
      } (emails/COPY_NEEDED.md; confirm them in emails/src/emails/auth.tsx)`,
    );
    Deno.exit(1);
  }
  const body = Object.fromEntries(changed.map((k) => [k, next[k]]));
  const patch = await fetch(api, { method: 'PATCH', headers, body: JSON.stringify(body) });
  // The status only: an error body may quote template text.
  if (!patch.ok) throw new Error(`PATCH config/auth ${patch.status}`);
  const check = await fetch(api, { headers });
  if (!check.ok) throw new Error(`GET config/auth after PATCH ${check.status}`);
  const after = await check.json() as Record<string, unknown>;
  const off = changed.filter((k) => after[k] !== next[k]);
  if (off.length) throw new Error(`not applied: ${off.join(', ')}`);
  console.log(`updated ${changed.length} keys`);
}
