# Copy Snacklist PM still has to write

The components are done; these words are not. Write them in the files named, then run
`npm test` and `npm run production` (docs/EMAIL.md, "How Snacklist PM writes a new mail").

1. **Auth mails.** Done for the six the app sends: AL4's German and English wording
   (`src/emails/auth.tsx`, checked against `test/fixtures/al4/`). The seven security notices are
   off; their German is job 177's draft translation of Supabase's English.
2. **Reason lines marked draft** (`reason: { draft }`), German and English: the seven security
   notices and "partner joined". The six auth mails the app can send carry confirmed lines.
   `supabase/deploy/auth_mail.ts` refuses to put a template with a draft line live.
3. **Account deletion mail** (`src/emails/notices.tsx`, `AccountDeleted`, DE and EN): the body is a
   `Draft`. Subject is a draft too.
4. **Partner joined** (`PartnerJoined`, DE and EN): the sentence is Legal N-14's; the subject
   ("Neues Mitglied in deinem Haushalt", no first name per N-20) is a draft.
5. **Legal footer and unsubscribe line:** done by Legal Review (N-15 a and b), pending Peter's
   approval. Not Snacklist PM's to change.
6. **iPhone welcome** (DE, EN): build once iOS is installable, from Snacklist PM's existing drafts.
