# Alexa skill

A household member says "Alexa, sag Snacklist, füg Milch und Eier hinzu" and the items land on the household's list, categorized like typed ones and visible to every member within seconds; Alexa reads back what it added ("Ich habe Milch und Eier auf die Snacklist gesetzt."). "Alexa, frag Snacklist, was auf der Liste steht" reads the open items. The account is linked once in the Alexa app through the app's consent page ("Amazon Alexa"), shows under Mehr → Zugänge, and is cut off there, by disabling the skill, or by linking again.

## Sub-features

- `alexa-add` adds the items of one phrase (several, quantities, umlauts, a count said after the item such as "Karotten zwei" or "Karotten 2") to the linked user's current household and reads them back.
- `alexa-english` an en-US (or other en-*) request is split by the English parser and answered in English ("I put milk and eggs on Snacklist."); de-DE and a request without a locale stay German.
- `alexa-duplicate` names open items ("Schon auf der Snacklist: Milch.") without adding them again.
- `alexa-similar` a new item whose spelling variant or synonym is open is added anyway and the open one named ("Ich habe Karotten auf die Snacklist gesetzt. Schon auf der Snacklist: Möhren.").
- `alexa-read` reads the open items in aisle order, at most 10, then "und N weitere"; an empty list has its own sentence.
- `alexa-reprompt` asks once when nothing was understood, then says "… Ich habe nichts auf die Snacklist gesetzt."; nothing is added.
- `alexa-unlinked` asks to link the account (LinkAccount card) when there is no token or it was revoked.
- `alexa-link` is account linking: the consent page shows "Amazon Alexa", after "Erlauben" "Verbunden" / "Fertig, du kannst zu Amazon Alexa zurückkehren.", and Mehr → Zugänge lists it afterwards.
- `alexa-revoke` cuts Alexa off at once: "Amazon Alexa trennen" under Zugänge, or the skill disabled in the Alexa app.
- `alexa-verify` refuses unsigned, tampered, stale and foreign-skill requests with 400 before anything is read.
- `alexa-help` help ("Mit Snacklist setzt du Sachen auf eure Einkaufsliste. …", session open) and stop, cancel or home ("Bis bald.").
- `alexa-locked` is gone: the integration gate always lets Alexa through (Alexa is free like Siri), and the function has no locked sentence (`e2e/tests/integration-lock.spec.ts`, „Alexa is never locked“).
- `alexa-named-list` (job 207) `AddToListIntent` („füge {items} zur {list} Liste hinzu“), or a list phrase at the end of an add, puts the items on that list: „Ich habe Luftballons auf die Liste Geburtstag gesetzt.“ Locally: `scripts/alexa-say.sh … --list Geburtstag "Luftballons"`.
- `alexa-confirm` (Q79) a plain name whose item is open with a brand or „Bio“ is held and Alexa asks (`Dialog.ConfirmIntent`); locally `scripts/alexa-say.sh … --confirm CONFIRMED|DENIED --attributes '<the question's session attributes>'` answers it.
## How to get to it (user POV)

- An Echo or the Alexa app, after the skill is enabled and linked (docs/ALEXA.md): "Alexa, sag Snacklist, …", "Alexa, frag Snacklist, …", "Alexa, öffne Snacklist". Without one of these patterns ("Alexa, setz Milch auf die Snacklist") Alexa's own lists take the sentence (docs/ALEXA.md, "Invocation name and Alexa's own lists").
- Linking: Alexa app → Skills → Snacklist → Konto verknüpfen, which opens the app's consent page (web).
- Locally there is no Alexa: `scripts/alexa-say.sh` sends the request Alexa would send, signed with the local test CA.

## Driving it with fg

Preconditions:

- Run `scripts/alexa-test-ca.sh` once before `fg up` (it writes the test CA into `supabase/functions/.env`, which fg's stack links; `fg up` doesn't run it). A running stack doesn't load the new variables, and `fg up --fresh` only resets the database: run `fg down`, then `fg up`. Baseline from `features/README.md`; peter and lea signed in.
- An access token for peter as Alexa holds it: run the linking in a browser as `e2e/tests/alexa-helpers.ts` `linkAccount` does (register with `scripts/alexa-oauth-client.sh <vendor id, 6-20 capitals or digits such as LOCALTEST1> "$(fg env | jq -r .apiUrl)"`, open the authorize URL with PKCE and the layla redirect, "Erlauben" on peter's web client, exchange the code with HTTP Basic). Keep the token in a shell variable `TOKEN`, never in a file.

- **Add.** `scripts/alexa-say.sh --url "$(fg env | jq -r .apiUrl)" --token "$TOKEN" "Milch und Eier"` answers `outputSpeech.text` "Ich habe Milch und Eier auf die Snacklist gesetzt."; `fg wait --client lea --text Eier` succeeds on lea's client within 5 seconds without a tap. `fg db query --as peter "select i.name, c.name from items i join categories c on c.id = i.category_id where i.status = 'active'"` shows Kühlregal for both.
- **Carrier word left in the slot.** The same call with "Milch drauf" adds "Milch" (the splitter drops a trailing "drauf"); `fg fn call voice --body '{"text":"Setz Milch drauf"}'` shows the same through Siri's path.
- **English.** Add `--locale en-US` to any call: "two liters of milk and eggs" answers "I put 2 liters of milk and eggs on Snacklist." and stores `milk` (2 l) and `eggs`; `--launch --locale en-US` without a token answers "Please link your Snacklist account in the Alexa app first. …". `e2e/tests/alexa-en.spec.ts` runs it with linking.
- **Duplicate.** The same call with "Milch" answers "Schon auf der Snacklist: Milch."; the Milch count stays 1.
- **Read.** `scripts/alexa-say.sh … --token "$TOKEN" --read` answers "Auf der Snacklist stehen 2 Sachen: …".
- **Re-prompt.** `… --token "$TOKEN" "äh"` answers "Das habe ich nicht verstanden. Was soll auf die Liste?" with `shouldEndSession` false; `… --token "$TOKEN" --retry "ähm"` answers "Das habe ich leider nicht verstanden. Ich habe nichts auf die Snacklist gesetzt."
- **Unlinked.** `scripts/alexa-say.sh … --launch` (no token) answers "Bitte verknüpfe zuerst dein Snacklist-Konto in der Alexa-App. Ich habe dir dort eine Karte dazu geschickt." with `card.type` LinkAccount (an add without a token answers the same; passed 2026-11-23 on d023441d, also in English).
- **Revoke.** On peter's client: `fg tap --key tab-more`, `fg tap --key more-access`, tap "Amazon Alexa trennen" and confirm "Trennen". The add call with `$TOKEN` now answers the link sentence and adds nothing. Or `scripts/alexa-say.sh … --disable` (SkillDisabled for the default Alexa user that made the earlier calls) with the same result.
- **Verify.** `… --unsigned "Bier"` and `… --stale "Bier"` answer 400 `missing_signature` and `stale_timestamp` (stale passed 2026-11-23); no Bier row exists.
- **Proof.** The JSON answers, `fg screenshot --name alexa-<sub-feature>` of lea's list, and the `fg db query` rows.

## Gotchas

- The local function trusts the test CA only inside a local stack; it never accepts a request a hosted project would refuse, and `scripts/alexa-say.sh` cannot reach a hosted project.
- A stack started before `scripts/alexa-test-ca.sh` ran doesn't trust the test CA: every signed request answers a 400 before any intent runs (`{"error":"cert_expired"}` on 2026-10-31). Restart it with `fg down` and `fg up`. Without the CA at all, `scripts/alexa-say.sh` refuses to sign ("no test CA").
- `--disable` revokes the sessions of the Alexa user id in the request (default `amzn1.ask.account.LOCAL`); use the same `--user` for the add calls and the disable.
- Alexa itself, the spoken voice and the Alexa app's linking screens can only be checked on a real device (docs/NEEDS_PETER.md, Job 31 beta checklist). Report them as not drivable here.
