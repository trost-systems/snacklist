# snacklist.app waitlist and the CTA stages

snacklist.app/de and /en keep their landing page (hummlist.com redirects here, S3); the calls to action follow `site/config/stage.ts`. In the `waitlist` stage (now) the header and hero buttons „Auf die Warteliste“ / "Join the waitlist" lead to a sign-up form in the closing block: an email field and iPhone or Android, with Legal's form text under the button. A sign-up gets a confirmation mail; the address counts only after its owner agrees on the confirmation page (consent text, an unticked launch-news box, „E-Mail bestätigen“). Every mail can delete the entry. The stages `beta` („Zur Beta anmelden“) and `launch` (store badges, QR code, snacklist.app/get) are built and off. In `waitlist` and `beta` the hero badge reads „Beta im November“ / "Beta in November" and a founder note „Von Peter“ / "From Peter" (`.founder-section`) sits between the privacy block and the form; `launch` drops both. No stage links the browser app. Live since 5 Nov (#210, then on hummlist.com; the badge and note since 6 Nov, #280), with noindex. Whether a sign-up gets through in production depends on server settings this repo cannot show (`docs/NEEDS_PETER.md`, "Job 82"): without them the form answers „Das hat gerade nicht geklappt. Bitte versuch es gleich noch mal.“, and until the waitlist goes public only `test@snacklist.app`, `test+…@snacklist.app` and (until the old allow-list entry goes) `hello+…@hummlist.com` addresses are stored.

## Sub-features

- `form` email (required, hint „Am besten die E-Mail deiner Apple-ID bzw. deines Google-Kontos“), platform radio (required), Legal's form text under the button; no launch-news box (it is on the confirmation page).
- `form-errors` empty or invalid fields show labeled, announced errors and send nothing.
- `form-success` after sending: „Fast geschafft, check dein Postfach“; the same answer for a new, known or confirmed address.
- `confirm` the link in the mail opens /de/warteliste/bestaetigen (EN /en/waitlist/confirm) with Legal's consent text and the launch-news box, unticked; nothing happens until the button is pressed; then „Du stehst auf der Warteliste“; the same link again shows the neutral page.
- `stages` `site/config/stage.ts`: `waitlist` (form), `beta` (form, „Zur Beta anmelden“), `launch` (badges in the hero, badges and from 720 px a QR code in the closing block, „App laden“ to `#app`).
- `get` snacklist.app/get sends an iPhone to the App Store and Android to Google Play once their URLs are set, everything else to /de or /en.
- `unsubscribe` the link in every mail opens /de/warteliste/abmelden (EN /en/waitlist/unsubscribe); the button deletes the entry at once. Later mails also offer one-click unsubscribe in the mail client.
- `no-app-links` no page of the site links to or loads anything from app.snacklist.app or app.hummlist.com.
- `support-faq` /support and /en/support: questions and answers plus support@snacklist.app.
- `landing-stores` (#290) the stores card: under „Tippe auf einen Laden:“ / "Tap a store:" (the hint labels the button group) the hex buttons „Drogerie“, „Getränkemarkt“, „Supermarkt“ / "Drugstore", "Drinks store", "Supermarket" (`aria-pressed`; Getränkemarkt replaced Bäckerei) re-order the five category stops below, a list named after the pressed store, with the app's category names. Without JavaScript the Supermarkt route shows. The hero still draws Bäckerei among its stores.
- `landing-videos` (#292, #301) four silent videos with written descriptions (the `aria-label`): typing „Honig“ and „Marmelade“ and ticking them off; three phones of the Brandt family in sync („1 neu von Mia Brandt“); adding by voice, „Pizza, Orangensaft und zwei Packungen Fischstäbchen“; an AI chat adding and ticking off. They show the floating add field and the tab pill.

## How to get to it (user POV)

1. Open snacklist.app (redirects to /de or /en by browser language).
2. Header or hero button „Auf die Warteliste“ / "Join the waitlist": it scrolls to the form in the closing block.
3. Fill „E-Mail-Adresse“ / "Email address", pick „iPhone“ or „Android“, press „Auf die Warteliste“ / "Join the waitlist".
4. In the mail: „E-Mail bestätigen“ / "Confirm email", then on the page optionally tick „Schreibt mir auch, wenn die App offiziell startet (eine E-Mail, freiwillig).“ and press „E-Mail bestätigen“.
5. In any mail: „Eintrag sofort löschen“ / "Delete this sign-up now" (confirmation mail) or „Abmelden“ / "Unsubscribe" (later mails), then the button on the page.

## Driving it with Playwright

Preconditions: a local Supabase stack with this checkout's migrations; `supabase functions serve` with `WAITLIST_PROXY_SECRET`, `WAITLIST_HMAC_SECRET`, `RESEND_API_KEY` and `RESEND_API_URL` pointing at a stand-in that logs mails; `cd site && npm run build`; the preview server (`scripts/preview.mjs`, `startPreview({ port })`) with `WAITLIST_UPSTREAM_URL=http://127.0.0.1:<api port>/functions/v1/waitlist` and the same proxy secret. Only `test@snacklist.app`, `test+<anything>@snacklist.app` and (until the old entry goes) `hello+<anything>@hummlist.com` addresses.

- Form, stub upstream: `cd site/checks && npm ci` once, then `node site/checks/waitlist.mjs site/dist --port <prefix>10` (default port 57640; `flock /tmp/fg-e2e.lock` when the box is busy) checks errors, success, honeypot, confirm and unsubscribe pages, no cookies, no off-origin requests, no console errors.
- Sign up: `getByLabel(/E-Mail-Adresse/)`, `getByRole('radio', { name: 'iPhone' })`, wait 2 s (sends within 1.5 s of page load are dropped as bots), `getByRole('button', { name: 'Auf die Warteliste' }).last()`; result: an element with `data-state="done"`; the form is `#test form`.
- Confirm: open the confirm URL from the stand-in's log, `getByRole('button')` with „bestätigen“; result `data-state="confirmed"`; again: `data-state="invalid"`.
- Landing: `PORT=<prefix>90 node site/scripts/preview.mjs` after the build. `getByRole('group', { name: 'Tippe auf einen Laden:' })`, click each `getByRole('button', { name: 'Getränkemarkt' })` (and the others); result `aria-pressed="true"` and `getByRole('list', { name: /Getränkemarkt/ }).getByRole('listitem')` starting with Getränke. `page.locator('video')`: four, each with an `aria-label` (DE and EN at /de and /en).
- Unsubscribe: the URL from the welcome mail, button with „löschen“; result `data-state="deleted"`, and the row count for that address is 0.

## Gotchas

- Every build fails on a `⟦…⟧` placeholder. The launch stage only builds once the `X-Robots-Tag` header is gone from `site/vercel.json` (job 93's guard); tests use `stageBuild('launch')`.
- A sign-up's `launch_news` is ignored; only the box on the confirmation page sets it.
- The local stack's oneshot workers drop work after the answer, so locally the function answers after storing; hosted it answers first.
- Sends within 1.5 s of page load, or with the hidden `website` field filled, answer like a success and store nothing.
- Without `WAITLIST_MAIL_ALLOW=*` only `test@snacklist.app`, `test+…@snacklist.app` and (until the old allow-list entry goes) `hello+…@hummlist.com` addresses are stored.
- Never read real waitlist rows (Peter's rule); count only your own test addresses.
