# hummlist.com waitlist (off in production)

hummlist.com/de and /en show a landing page with a waitlist form instead of links to the browser app: an email field, iPhone or Android, an optional launch-news checkbox, the button and the consent text under it. A sign-up gets a confirmation mail; the address counts only after its owner presses „E-Mail bestätigen“ on the confirmation page. Every mail can delete the entry. Production keeps the old site (with the browser-app links) until Peter turns the waitlist on (docs/WAITLIST.md); preview and local builds show the waitlist, with unapproved texts behind visible `⟦…⟧` tags.

## Sub-features

- `form` email (required, hint „Am besten die E-Mail deiner Apple-ID bzw. deines Google-Kontos“), platform radio (required), launch-news checkbox (optional, unticked), consent text under the button.
- `form-errors` empty or invalid fields show labeled, announced errors and send nothing.
- `form-success` after sending: „Fast geschafft, check dein Postfach“; the same answer for a new, known or confirmed address.
- `confirm` the link in the mail opens /de/warteliste/bestaetigen (EN /en/waitlist/confirm); nothing happens until the button is pressed; then „Du stehst auf der Warteliste“; the same link again shows the neutral page.
- `unsubscribe` the link in every mail opens /de/warteliste/abmelden (EN /en/waitlist/unsubscribe); the button deletes the entry at once. Later mails also offer one-click unsubscribe in the mail client.
- `no-app-links` no page on hummlist.com links to or loads anything from app.hummlist.com.
- `support-faq` /support and /en/support: questions and answers plus support@hummlist.com.

## How to get to it (user POV)

1. Open hummlist.com (redirects to /de or /en by browser language).
2. Header „Auf die Warteliste“ / "Join the waitlist" or the form in the hero.
3. Fill „E-Mail-Adresse“ / "Email address", pick „iPhone“ or „Android“, optionally tick the launch-news box, press „Auf die Warteliste“ / "Join the waitlist".
4. In the mail: „E-Mail bestätigen“ / "Confirm email", then the button on the page.
5. In any mail: „Eintrag sofort löschen“ / "Delete this sign-up now" (confirmation mail) or „Abmelden“ / "Unsubscribe" (later mails), then the button on the page.

## Driving it with Playwright

Preconditions: a local Supabase stack with this checkout's migrations; `supabase functions serve` with `WAITLIST_PROXY_SECRET`, `WAITLIST_HMAC_SECRET`, `RESEND_API_KEY` and `RESEND_API_URL` pointing at a stand-in that logs mails; `cd site && npm run build`; the preview server (`scripts/preview.mjs`, `startPreview({ port })`) with `WAITLIST_UPSTREAM_URL=http://127.0.0.1:<api port>/functions/v1/waitlist` and the same proxy secret. Only `hello+<anything>@hummlist.com` addresses.

- Form, stub upstream: `flock /tmp/fg-e2e.lock node site/checks/waitlist.mjs site/dist` checks errors, success, honeypot, confirm and unsubscribe pages, no cookies, no off-origin requests, no console errors.
- Sign up: `getByLabel(/E-Mail-Adresse/)`, `getByRole('radio', { name: 'iPhone' })`, wait 2 s (sends within 1.5 s of page load are dropped as bots), `getByRole('button', { name: 'Auf die Warteliste' }).last()`; result: an element with `data-state="done"`.
- Confirm: open the confirm URL from the stand-in's log, `getByRole('button')` with „bestätigen“; result `data-state="confirmed"`; again: `data-state="invalid"`.
- Unsubscribe: the URL from the welcome mail, button with „löschen“; result `data-state="deleted"`, and the row count for that address is 0.

## Gotchas

- Production builds leave all of this out until `HUMMLIST_WAITLIST=on` in Vercel, and a production build fails while any `⟦…⟧` text is left.
- The local stack's oneshot workers drop work after the answer, so locally the function answers after storing; hosted it answers first.
- Sends within 1.5 s of page load, or with the hidden `website` field filled, answer like a success and store nothing.
- Without `WAITLIST_MAIL_ALLOW=*` only `hello+…@hummlist.com` addresses are stored.
- Never read real waitlist rows (Peter's rule); count only your own test addresses.
