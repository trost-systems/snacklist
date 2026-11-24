# Snacklist mails

Every mail Snacklist sends is built from one React Email source in `emails/`, with the RD1 tokens
from `design/tokens/snacklist.tokens.json`. The same components make the Supabase Auth
templates (`supabase/templates/`), the onboarding mails Snacklist PM writes, and the service
notices. Job 55 built it, job 177 brought it to Snacklist and to AL4's German and English auth
mails. The six Auth templates and the sender name `Snacklist` went live on the hosted project on 2026-11-24 (job 434, `auth_mail.ts`).

- Component reference with props and examples: [`emails/README.md`](../emails/README.md).
- What Snacklist PM still has to write: [`emails/COPY_NEEDED.md`](../emails/COPY_NEEDED.md).
- Previews: [`docs/screenshots/177-mail-design-snacklist/`](screenshots/177-mail-design-snacklist/)
  (a selection); `npm run preview` renders all of them with one review page.

## The parts

| Part | Where | What |
| --- | --- | --- |
| Tokens | `emails/src/tokens.ts` | Reads the token JSON at render time; no colour or size is copied by hand. |
| Theme | `emails/src/theme.ts` | Inline styles, the dark-mode and narrow-screen `<style>`, Outlook's head. |
| Components | `emails/src/components/` | Header, Heading, Greeting, Paragraph, TextLink, Steps, TipBox, CodeBox, PrimaryButton, PhoneScreenshot, Signature, Draft, TransactionalFooter, OnboardingFooter. |
| Layouts | `emails/src/layouts.tsx` | `AuthLayout` (transactional) and `OnboardingLayout`. |
| Mails | `emails/src/emails/` | `auth.tsx` (the 13 Supabase templates as one table), `onboarding.tsx`, `notices.tsx`, `catalog.tsx`. |
| Registry | `emails/src/registry.tsx` | Every mail once, with subject, language and demo values. Build, previews and tests read it. |
| Render | `emails/src/render.ts` | `renderEmail(element, { production })` returns `{ html, text }` and refuses what must not ship. |

## Build, check, preview

```sh
cd emails
npm ci
npm run build        # supabase/templates/*.html and config.toml's template block (subjects)
npm test             # tsc type checks, then the unit tests (also fails on stale templates)
npm run production   # exit 1 while a draft line or the demo unsubscribe link is in a mail
flock /tmp/fg-e2e.lock npm run preview -- --out /tmp/fg-email-previews   # PNGs, contact sheet, index.html
```

The CI job `emails` runs `scripts/gates/emails.sh` (`npm ci && npm test`) whenever `emails/`,
`supabase/templates/`, `supabase/config.toml`, the design tokens or `site/public/email/` change.
The `Generated from emails/ ..., do not edit` Go comment heads every built template.

Previews render with Playwright's Chromium. Requests to `https://snacklist.app/` are answered from
`site/public/`, so a preview shows the assets this branch ships before they are deployed; every
other request is blocked.

## How Snacklist PM writes a new mail

1. Pick the layout. Anything a reader asked for by signing up for tips is `OnboardingLayout` (it
   carries the unsubscribe footer). Anything the service must send (sign-in, account, a member
   joined) is `AuthLayout` with a `reason` line, and nothing promotional.
2. Copy a mail in `emails/src/emails/onboarding.tsx` (for example `NudgeDe`), rename it, change only
   the words. Components set every colour, size and space. No `style` props, no hex values.
3. Add it to `EMAILS` in `emails/src/registry.tsx` with its subject and demo values (fixture
   people: Anna, `anna.beispiel@example.com`). Subjects say what is inside: no "Re:", no first
   names (Legal N-15, N-20).
4. `npm test`, then `npm run preview -- <id>` and look at the PNGs (light, dark, phone).
5. Lines nobody has approved yet go in as `<Draft>` or `reason={{ draft: '…' }}`. They render
   so Peter can review, and `npm run production` refuses them until they are confirmed.

Rules the components and tests enforce:

- One `PrimaryButton` per mail (`renderEmail` throws on a second).
- `Steps` takes two to four steps (a type error otherwise).
- `PhoneScreenshot` takes only `https://snacklist.app/….png` images and needs alt text; demo data
  only (fixture households, never real lists).
- Always "Snacklist", never shortened; no `#F5B400`; no request outside `https://snacklist.app/`.
- Under 100 KB of HTML (Gmail clips at 102 KB). The largest mail today (the welcome) is about 17 KB.

## Sending (when a sender exists)

Nothing sends mail from this package today. A sender (an Edge Function with Resend, for example)
would call `renderEmail` and pass `{ html, text }` to Resend's API:

```ts
const { html, text } = await renderEmail(<NudgeDe name="Anna" unsubscribeUrl={url} />, { production: true });
await resend.emails.send({
  from: '"Peter · Snacklist" <hello@snacklist.app>', to, subject: 'Ein Tipp für deinen nächsten Einkauf', html, text,
  headers: onboardingHeaders(token),  // onboarding only; transactional mails get none
});
```

- **From:** every mail comes from `"Peter · Snacklist" <hello@snacklist.app>`, the sender Supabase
  Auth (Resend's SMTP, docs/AUTH.md) and the waitlist mails (docs/WAITLIST.md) use since #357.
- **Headers:** `onboardingHeaders(token)` returns `List-Unsubscribe` (the one-click URL with the
  reader's opaque token, plus `mailto:hello@snacklist.app?subject=unsubscribe`) and
  `List-Unsubscribe-Post: List-Unsubscribe=One-Click` (Legal N-16, RFC 8058). It refuses an
  address as the token.
- **Tracking:** Resend's open and click tracking stay off. No pixels, no rewritten links.
- The unsubscribe endpoint `https://app.snacklist.app/email/abmelden?t=…` does not exist yet, and
  neither does consent storage or a sequence. Both wait for Peter's decision.

## Footers (Legal Review 2026-11-01, N-15, pending Peter's approval)

| Footer | Used by | Content |
| --- | --- | --- |
| `TransactionalFooter` | `AuthLayout`: auth templates, account deletion, partner joined | One reason line, sender line, imprint and privacy links. No unsubscribe, nothing promotional. |
| `OnboardingFooter` | `OnboardingLayout`: welcome, nudge, later tips | Optional note (feedback), reason, one-click unsubscribe link, unsubscribe by reply, objection notice (Art. 21), sender line, imprint and privacy links. Refuses a missing unsubscribe URL. |

The sender line and both footer texts are Legal's wording, DE and EN, in
`emails/src/components/Footer.tsx`. Change them only with Legal.

## Template inventory

The 13 mails Supabase Auth can send, each in German and English. A built template is one Go
template with AL4's pick (docs/AUTH.md, "Mail language"): the German mail when the account's
`user_metadata.mail_locale` is `de`, the English one otherwise (no metadata, `en`, any other
value). The subject in `config.toml` branches the same way. The six mails the app's flows send keep
AL4's wording word for word; the tests compare them with AL4's files
(`emails/test/fixtures/al4/`), and `supabase/deploy/auth_mail_test.ts` still checks the pick, the
name and the link in both branches. Supabase fills the Go template variables when it sends; they
stay unescaped in the output.

| Template (`supabase/templates/`) | Subject (EN) | Variables | Hosted status | Reason line |
| --- | --- | --- | --- | --- |
| `confirmation` | Confirm your email address for Snacklist | `.ConfirmationURL` | sent (sign-up) | draft |
| `magic_link` | Your Snacklist sign-in link | `.ConfirmationURL` | sent | Legal's (confirmed) |
| `recovery` | Reset your Snacklist password | `.ConfirmationURL` | sent | draft |
| `email_change` | Confirm your new email address for Snacklist | `.ConfirmationURL`, `.NewEmail` | sent (secure change: old and new address) | draft |
| `invite` | You've been invited to Snacklist | `.ConfirmationURL` | **unused**: the app never calls `inviteUserByEmail`. Must not be used for household invites (Legal N-18); invites are shared from the user's own phone. | draft |
| `reauthentication` | `{{ .Token }}` is your Snacklist verification code | `.Token` | sent | draft |
| `password_changed_notification` | Your password was changed | none | disabled | draft |
| `email_changed_notification` | Your email address was changed | `.OldEmail`, `.Email` | disabled | draft |
| `phone_changed_notification` | Your phone number was changed | `.OldPhone`, `.Phone` | disabled | draft |
| `mfa_factor_enrolled_notification` | A new verification method was added to your account | `.FactorType` | disabled | draft |
| `mfa_factor_unenrolled_notification` | A verification method was removed from your account | `.FactorType` | disabled | draft |
| `identity_linked_notification` | A new sign-in method was linked to your account | `.Provider`, `.Email` | disabled | draft |
| `identity_unlinked_notification` | A sign-in method was removed from your account | `.Provider`, `.Email` | disabled | draft |

The seven notifications keep Supabase's English; their German is job 177's draft. Supabase sends
HTML only, so the plain text `renderEmail` makes is for previews and for senders that send
multipart.

The local stack (`supabase/config.toml`) uses the same templates, so Mailpit shows them and the
e2e sign-in tests read them. The notifications stay disabled locally, as on hosted.

**Going live.** Merging changes nothing on the hosted project. `supabase/deploy/auth_mail.ts`
(AL4) puts AL4's six templates and their subjects on it through the Management API; it runs by
hand, after the merge has put `site/public/email/` on snacklist.app (the logo), and refuses a
template that still holds a draft line (`data-hl-draft`). Steps: docs/NEEDS_PETER.md, "Job 177".

Other mails in the registry:

| Id | Layout | Status |
| --- | --- | --- |
| `welcome-android-de`, `welcome-android-en` | Onboarding | Snacklist PM's tester welcome, word for word. Sendable once Peter approves the footer. |
| `nudge-de`, `nudge-en` | Onboarding | Snacklist PM's day-3 nudge, word for word. |
| `partner-joined-de`, `partner-joined-en` | Auth (transactional) | Legal N-14's sentence and one button (the English is job 177's translation). Subject and reason line are drafts; no sender. |
| `account-deleted-de`, `account-deleted-en` | Auth (transactional) | Layout and Legal's reason line; body is a `Draft` for Snacklist PM; no sender. |
| `catalog-de` | Onboarding | Every component once. Never sent. |

The iPhone welcome drafts are not built: iOS is not installable yet ("not sendable yet" in Snacklist PM's
draft README). Building them is copying `WelcomeAndroidDe` with the iOS wording.

## Clients

- **Layout:** tables, inline styles, fluid up to 600 px. Outlook on Windows gets a 600 px ghost
  table and a VML button through `<!--[if mso]>` comments. No flex, grid or CSS variables.
- **Supabase strips comments.** GoTrue renders templates with Go's `html/template`, which drops
  every HTML comment, the MSO ones included (seen in Mailpit, 2026-11-01). Through Supabase,
  Outlook on Windows gets the plain table button (square corners), a card as wide as the
  reading pane, and no Arial override, so Word may set the text in Times New Roman where neither
  Bricolage Grotesque nor Inter is installed (inferred from how Word handles font stacks, not
  tested: there is no Outlook here). Mails sent through Resend's API keep the comments. A Send
  Email Hook would avoid all three (DECISIONS job 55, 8).
- **Dark mode:** `color-scheme` and `supported-color-schemes` meta, `prefers-color-scheme` overrides
  with the dark tokens (Apple Mail, iOS, Outlook for Mac), `[data-ogsc]`/`[data-ogsb]` for
  Outlook.com. Gmail's apps invert on their own; the light palette survives that (navy on white,
  navy on yellow). The logo is a square PNG with its own cobalt ground, so no client inverts dark
  ink on a transparent background.
- **Images blocked:** the logo cell keeps its size and cobalt ground beside the live "Snacklist"
  wordmark (the image's alt is empty, because the wordmark already says the name). A screenshot
  shows its alt text inside the frame.
- **Fonts:** no web fonts (next section). Bricolage Grotesque and Inter render only where installed;
  the stacks fall back to Trebuchet MS / Helvetica Neue / Arial and the system UI font.

### Fonts

No `@font-face`, not even from snacklist.app. Every remote load in a mail tells the sender the
reader's IP address and when they opened it, which is a tracking pixel by another name. Gmail's
image proxy does not cover fonts, and only Apple Mail, iOS Mail and Thunderbird would load them.
The logo is the one remote load (from snacklist.app, proxied by Gmail and Apple Mail Privacy
Protection). The display stack is
`"Bricolage Grotesque", "Trebuchet MS", "Helvetica Neue", Arial, sans-serif`, the body stack
`Inter, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`. The first family of each
comes from the tokens.

## Drafts

`npm run production` lists what blocks sending. Today:

- The reason lines of every auth template except `magic_link` and of `partner-joined-*` (drafts
  for Snacklist PM or Peter to confirm; Legal wrote the sign-in, deletion and E1 lines).
- `account-deleted-*`'s body.
- The demo unsubscribe link in the onboarding previews. A real send passes the reader's.
