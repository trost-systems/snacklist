# Store captions for voice assistants and MCP

Research note for two Snacklist screenshot captions (App Store and Google Play, de-DE first, then en-US).
Caption A is about voice assistants (Siri, Alexa). Caption B is about MCP and the API for automations.
Access date of every source: 2026-11-14.

Labels used below:

- **sourced**: the linked page says it.
- **inferred**: my reading of one or more sourced rules.
- **open**: Legal decides.

Legal checks the final wording before any upload. Nothing here replaces that check.

## Snacklist facts this note assumes

- Siri works through an Apple Shortcut that the user sets up. The App Intents version ("Siri without setup") is built but not announced.
- The Alexa skill is an invite-only beta. Amazon has not certified it, and it is not in the Alexa Skill Store. Our own rules name it "Snacklist-Skill für Amazon Alexa" and never call Alexa "sie".
- AI assistants connect over MCP at `https://mcp.snacklist.app`. Legal N-80..N-86 forbids naming specific AI assistant brands or their makers in marketing.
- The public REST API exists but is off (flag `public-api`). It must not be announced.
- After the public launch, MCP access becomes part of Snacklist Premium. Siri and Alexa stay free. The screenshots show neither Premium nor a price.

## 1. Apple: naming Siri is allowed as a referential phrase

- **sourced.** Guideline 2.3 requires that screenshots "accurately reflect the app's core experience" and stay up to date. 2.3.1(a) calls promoting services the app "does not actually offer" grounds for removal ([Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).
- **sourced.** Guideline 2.3.2: if the app has in-app purchases, the description, screenshots, and previews must "clearly indicate whether any featured items, levels, subscriptions, etc. require additional purchases".
- **sourced.** Guideline 2.3.7: screenshots "should not include prices". Metadata must not be packed with trademarked terms "just to game the system".
- **sourced.** Guideline 5.2.1: no third-party trademarks without permission. The text has no Siri-specific rule under 5.2.
- **sourced.** Apple's third-party trademark guidelines allow an Apple word mark only "in a referential phrase" such as "for use with" or "compatible with". The mark must be less prominent than the product name and never part of it. No Apple logo or icon without a written license. No foreign-language equivalent of an Apple mark ([Guidelines for Using Apple Trademarks](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)).
- **sourced.** The Apple Trademark List has "Siri®" and "Siri Shortcuts®". It does not list "Hey Siri". Outside the US, publications carry no trademark symbols ([Apple Trademark List](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html)).
- **sourced.** The App Store Marketing Guidelines say to use "works with" or "compatible with" for compatibility. Siri is always in English and always capitalized. Headline copy gets no trademark symbols. Copy should "focus on your app, not on Apple product features". An app shown inside Siri appears "exactly as it appears when your app is running" ([Marketing Resources and Identity Guidelines](https://developer.apple.com/app-store/marketing/guidelines/)).
- **sourced.** The HIG Siri page says to refer to Siri by name, never "she" or "her". Do not use the reserved phrase "Hey Siri". If a localized text must say it, translate only "Hey" (de_DE stays "Hey Siri") ([HIG: Siri](https://developer.apple.com/design/human-interface-guidelines/siri.md)).
- **sourced.** Apple's badges are the App Store download and pre-order badges only. There is no "Works with Siri" badge for apps ([Marketing Guidelines](https://developer.apple.com/app-store/marketing/guidelines/)). Using the Siri icon in a caption would need a license (third-party trademark guidelines above).
- **open.** A search result quotes Apple's old Siri Style Guide as recommending "MyApp works with Siri". That URL now redirects to an unrelated page, so I could not read the text.

**Answer, inferred.** A caption may name Siri as plain text in a "works with" form: "Funktioniert mit Siri", "Works with Siri". Do not use a symbol, the Siri icon, "Hey Siri", or a pronoun. Snacklist must stay the subject of the sentence. The Shortcut setup is a fact the caption must not hide. "Sag Siri einfach..." implies no setup and is misleading under 2.3 until the App Intents version ships. If a screenshot shows the Siri UI, it must be a real capture.

## 2. Amazon: name the skill only after certification

- **sourced.** Name a skill "[skill name] skill for Amazon Alexa", not "[skill name] Alexa skill" ([Alexa trademark guidelines](https://developer.amazon.com/en-US/alexa/branding/alexa-guidelines/communication-guidelines/trademark-guidelines), [Policy requirements](https://developer.amazon.com/en-US/docs/alexa/custom-skills/policy-requirements-for-an-alexa-skill.html)).
- **sourced.** The rules forbid ™ or ® symbols, forbid shortening, verbing, plurals, and possessives of the marks, and forbid translating Amazon marks. Every marketing piece carries the attribution "Amazon, Alexa, and all related marks are trademarks of Amazon.com, Inc. or its affiliates." unless space is short. The attribution may be translated ([trademark guidelines](https://developer.amazon.com/en-US/alexa/branding/alexa-guidelines/communication-guidelines/trademark-guidelines)).
- **sourced.** Write "With the [name] skill for Alexa, you can do X", not "Alexa does X". Show the launch utterance in marketing creative ([How to describe Alexa](https://developer.amazon.com/en-US/alexa/branding/alexa-guidelines/communication-guidelines/how-describe-amazon-echo-and-alexa)).
- **sourced.** "Works with Alexa" is a certification program for devices. It is not for skills (same page).
- **sourced.** The one badge for skill developers is "Just Ask Alexa". Skills built with the Alexa Skills Kit qualify. The page does not say whether the skill must be live ([Alexa badges](https://developer.amazon.com/en-US/alexa/branding/alexa-guidelines/brand-guidelines/alexa-badges)). The guidelines apply only to members of the Amazon Developer Program. Amazon reviews submitted marketing in 12 or more business days ([Alexa guidelines](https://developer.amazon.com/en-US/alexa/branding/alexa-guidelines)).
- **sourced.** None of these pages addresses beta or uncertified skills, or app store screenshots.

**Answer, inferred.** No Amazon rule names certification as the condition. The store rules decide instead. A user who reads "Alexa" in a screenshot cannot enable an invite-only skill. That fails Apple 2.3 ("does not actually offer") and Play's rule that screenshots "reflect your app's actual experience". So do not name Alexa in a screenshot until the skill is certified and live in the de-DE Skill Store (en-US once that locale ships). After that, the form is "Snacklist-Skill für Amazon Alexa" or "Snacklist skill for Amazon Alexa", with the attribution in the store description. Our ban on "sie" for Alexa matches Apple's no-pronoun rule for Siri. Amazon's pages I read give no pronoun rule.

## 3. Google Play: no logos; name only what the Android app offers

- **sourced.** Metadata covers screenshots and must not contain "deceptive claims". Do not use "a brand's logo without permission" ([Metadata policy](https://support.google.com/googleplay/android-developer/answer/9898842)). Using another party's trademark "in a way that is likely to cause confusion" can lead to suspension ([Intellectual property](https://support.google.com/googleplay/android-developer/answer/9888072)).
- **sourced.** Screenshot guidance (marked "highly recommended", not mandatory) says to avoid third-party logos without permission, keep taglines at or below 20% of the image, and leave out price, promotion, and words like "New" or "Best" ([Preview assets](https://support.google.com/googleplay/android-developer/answer/9866151)).
- **sourced.** The Subscriptions policy requires transparent offer terms inside the app. It does not address store listings ([Subscriptions](https://support.google.com/googleplay/android-developer/answer/9900533)). I found no Play rule like Apple's 2.3.2 for screenshots. Play shows its own in-app-purchase label, but I could not open a current Google page that explains it.

**Answer, inferred.** Siri does not work on Android, so the Play screenshot must not name Siri. Play captions use the neutral voice form, or Alexa once the skill is live. For the MCP caption, follow Apple's stricter 2.3.2 practice on both stores so the two listings say the same thing.

## 4. MCP: a registered mark, nominative use is allowed

- **sourced.** MCP is "Model Context Protocol a Series of LF Projects, LLC". Its trademark rules are the LF Projects policies ([MCP governance](https://modelcontextprotocol.io/community/governance)).
- **sourced.** The LF Projects trademark policy lists "Model Context Protocol®" as registered and "MCP™" as pending or in use. Fair use "to make true factual statements" is allowed, for example "<your product name> compatible with <mark>". The use must not imply sponsorship or endorsement, and the mark must not be part of the product name ([LF Projects trademark policy](https://lfprojects.org/policies/trademark-policy/)).

**Answer, inferred.** "über MCP" or "via MCP" in a caption is a true factual statement and is allowed. No symbol, no MCP logo, no "Snacklist MCP" as a product name. Most shoppers will not know the acronym, so the caption should name the benefit first and MCP second.

## 5. Real listings that name Siri or Alexa

All five are App Store listings. I could read their descriptions and the "Supports" section. I could not read screenshot captions, because the captions are text baked into images. WebFetch saw no alt text, and the Play pages came back truncated. Which wording appears inside screenshots stays **open**.

| App | Listing | Exact wording found |
| --- | --- | --- |
| AnyList | [App Store US](https://apps.apple.com/us/app/anylist-grocery-shopping-list/id522167641) | Description: "add items with your voice using Siri and Alexa". Version 5.28 notes: "the AnyList skill for Amazon Alexa". Version 8.0: "add items to your lists with Siri AI". |
| Our Groceries | [App Store US](https://apps.apple.com/us/app/id325851015) | "Add items with your voice using Siri on your iPhone, Watch, or HomePod." and "Supports other popular voice assistants too." |
| Todoist | [App Store US](https://apps.apple.com/us/app/todoist-to-do-list-planner/id572688855) | Description: "Add tasks via Siri". |
| Bring! | [App Store DE](https://apps.apple.com/de/app/bring-einkaufsliste/id580669177), [App Store US](https://apps.apple.com/us/app/bring-grocery-shopping-list/id580669177) | No Siri or Alexa in the description or subtitle. Siri appears only in Apple's own "Supports" line ("Benutze diese App mit Siri, um effizienter zu sein."). |
| Microsoft To Do | [App Store US](https://apps.apple.com/us/app/microsoft-to-do/id1212616790) | Mentions Cortana, not Siri or Alexa. |

Observations, **inferred**:

- The common form is a verb phrase with "with your voice using Siri". No listing I read says "Hey Siri".
- AnyList uses Amazon's exact form "skill for Amazon Alexa".
- Our Groceries names Alexa on its own help pages but writes "other popular voice assistants" in the App Store listing. That is the neutral form proposed below.
- Apple fills in the "Supports" line with Siri by itself, so a listing gets a Siri mention without writing one.

## 6. Recommendation

German first, then English. Captions are headlines, so they carry no ™ or ® (Apple's marketing guidelines, sourced). Siri and Alexa stay in English (sourced for both).

### Caption A: voice assistants

| Variant | de-DE | en-US | When | Label |
| --- | --- | --- | --- | --- |
| Named, Siri only (App Store) | Funktioniert mit Siri: Artikel per Sprache auf die Liste. | Works with Siri: add items by voice. | Now. The description says that the user sets up a Shortcut. | inferred from Apple's "works with" rule |
| Named, Siri and Alexa (App Store) | Funktioniert mit Siri und dem Snacklist-Skill für Amazon Alexa. | Works with Siri and the Snacklist skill for Amazon Alexa. | Only after Amazon certifies the skill and it is live in the store's locale. Add Amazon's attribution to the description. | inferred, open for Legal |
| Named, Alexa only (Play) | Mit dem Snacklist-Skill für Amazon Alexa auf die Liste sprechen. | Add items with the Snacklist skill for Amazon Alexa. | Same Alexa condition. Never Siri on Play. | inferred, open for Legal |
| Neutral (both stores) | Per Sprachassistent auf die Liste. | Add items with your voice assistant. | Any time, including now on Play. | inferred from Our Groceries' wording |

Do not write "Hey Siri", "Sag einfach ...", "Alexa, ..." utterances that suggest no setup, a Siri or Alexa logo, or a pronoun for either assistant. Amazon wants the launch utterance shown, so a future Alexa screenshot could show "Alexa, öffne Snacklist" once the invocation name is final (open).

### Caption B: MCP and the API

| Variant | de-DE | en-US | When | Label |
| --- | --- | --- | --- | --- |
| Named, MCP only | Verbinde deinen KI-Assistenten über MCP. | Connect your AI assistant via MCP. | Now, while MCP is free. | inferred from the LF fair-use rule |
| Named, MCP and API | Offen für KI-Assistenten (MCP) und Automationen (API). | Open to AI assistants (MCP) and automations (API). | Only after `public-api` is on for everyone and the API is announced. | inferred |
| Neutral | Snacklist mit KI-Assistenten und Automationen verbinden. | Connect Snacklist to AI assistants and automations. | Now only if "automations" means something users can do today (MCP clients). Otherwise drop "Automationen". | inferred, open |

Never name a specific AI assistant (Legal N-80..N-86).

### Conditions before upload

1. **Alexa.** Name Alexa only after Amazon certifies the skill and it is live in the store's locale. Until then, use the neutral form. (inferred from Apple 2.3 and the Play metadata policy)
2. **API.** Leave "API" out of every caption until `public-api` is on and the API is announced. (Snacklist fact, sourced from the brief)
3. **Premium.** When MCP moves into Premium, Apple 2.3.2 requires the screenshot to show that the feature needs a purchase. 2.3.7 forbids prices in screenshots. A short note such as "Mit Snacklist Premium" or "Requires subscription" meets both rules but shows Premium, which this screenshot set excludes. Options: replace Caption B with a version that has the disclosure, or drop it before the MCP paywall goes live. Make this choice before launch, not after. (sourced rules, open choice for Peter and Legal)
4. **Siri Shortcut.** As long as Siri needs a user-made Shortcut, the description says so and the caption avoids "einfach" or "ohne Einrichtung". When the App Intents version ships, "Funktioniert mit Siri" stays correct. (inferred)
5. **Credit lines.** Put Apple's credit line for Siri and Amazon's attribution for Alexa in the store description, not in the screenshot. (Amazon sourced. Apple inferred from its credit-line rule.)
6. **Legal.** Legal checks every final caption, in both languages, before upload. (process)

## Sources

All accessed 2026-11-14.

- Apple, App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple, Guidelines for Using Apple Trademarks and Copyrights: https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html
- Apple, Trademark List: https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html
- Apple, App Store Marketing Resources and Identity Guidelines: https://developer.apple.com/app-store/marketing/guidelines/
- Apple, Human Interface Guidelines, Siri: https://developer.apple.com/design/human-interface-guidelines/siri.md
- Amazon, Alexa guidelines (scope, review): https://developer.amazon.com/en-US/alexa/branding/alexa-guidelines
- Amazon, Alexa trademark guidelines: https://developer.amazon.com/en-US/alexa/branding/alexa-guidelines/communication-guidelines/trademark-guidelines
- Amazon, How to describe Alexa: https://developer.amazon.com/en-US/alexa/branding/alexa-guidelines/communication-guidelines/how-describe-amazon-echo-and-alexa
- Amazon, Alexa badges: https://developer.amazon.com/en-US/alexa/branding/alexa-guidelines/brand-guidelines/alexa-badges
- Amazon, Policy requirements for an Alexa skill: https://developer.amazon.com/en-US/docs/alexa/custom-skills/policy-requirements-for-an-alexa-skill.html
- Google Play, Metadata policy: https://support.google.com/googleplay/android-developer/answer/9898842
- Google Play, Intellectual property policy: https://support.google.com/googleplay/android-developer/answer/9888072
- Google Play, Preview assets guidance: https://support.google.com/googleplay/android-developer/answer/9866151
- Google Play, Subscriptions policy: https://support.google.com/googleplay/android-developer/answer/9900533
- MCP, Governance and stewardship: https://modelcontextprotocol.io/community/governance
- LF Projects, Trademark policy: https://lfprojects.org/policies/trademark-policy/
- App Store listings: AnyList https://apps.apple.com/us/app/anylist-grocery-shopping-list/id522167641, Our Groceries https://apps.apple.com/us/app/id325851015, Todoist https://apps.apple.com/us/app/todoist-to-do-list-planner/id572688855, Bring! https://apps.apple.com/de/app/bring-einkaufsliste/id580669177 and https://apps.apple.com/us/app/bring-grocery-shopping-list/id580669177, Microsoft To Do https://apps.apple.com/us/app/microsoft-to-do/id1212616790
