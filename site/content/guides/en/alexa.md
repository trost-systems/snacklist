---
title: "Snacklist with Alexa: set up the skill"
description: "With the Snacklist skill for Alexa you can add things to your Snacklist by voice: \"Alexa, ask Snacklist to add milk and eggs\". Here's how to set it up in a few minutes."
slug: alexa
locale: en
translation_key: alexa
updated: 2026-11-22
---

# Snacklist with Alexa: set up the skill

With the Snacklist skill for Alexa you can add things to your Snacklist by voice, without opening the app. You find the skill in the [Alexa Skill Store](alexa-skill:en). You enable it and link your account, then it works like this:

> **You:** Alexa, ask Snacklist to add milk and eggs.
> **The skill:** I put milk and eggs on Snacklist.

The skill sends your sentence to Snacklist. Snacklist splits it into separate items, puts each in the right spot on the list, and the items show up on every device in your household right away. The skill understands English and German, depending on the language your Alexa device is set to. If your device is set to German, follow the German guide: [Snacklist per Alexa: Skill einrichten](/de/anleitungen/alexa)

## What you need

- an Amazon account, the Alexa app on your phone and an Alexa device set to English (or German)
- the Snacklist app, signed in, in a household
- about five minutes

## Step 1: enable the skill and link your account

The skill signs in with your Snacklist account, not with a token. There's nothing to copy.

1. Open the Alexa app, search the skill store for **Snacklist** and open the skill's page.
2. Tap **Enable to use**. The Snacklist sign-in opens right after.
3. Sign in when Snacklist asks, the same way as in the app.
4. Snacklist asks "Allow access?" and shows what "Amazon Alexa" may do: read, add, change, tick off and remove items on your shopping list. Tap **Allow**.
5. The Alexa app shows that your account is linked.

## Step 2: try it

1. Say to your Alexa device: "Alexa, ask Snacklist to add milk and eggs".
2. The skill answers "I put milk and eggs on Snacklist.", and the items are in the app.

## How your sentence reaches the Snacklist skill {#reach-snacklist}

The Alexa app has shopping lists of its own. For your sentence to reach Snacklist and not those, it has to contain "ask Snacklist", "tell Snacklist" or "open Snacklist":

- "Alexa, ask Snacklist to add milk."
- "Alexa, tell Snacklist we need milk."
- "Alexa, ask Snacklist to put milk on the list."
- "Alexa, ask Snacklist what's on the list."
- "Alexa, open Snacklist." Then say what should go on the list.

Without "ask Snacklist", "tell Snacklist" or "open Snacklist" the sentence doesn't reach the Snacklist skill; it goes to the lists in the Alexa app.

The name is recognized best when you say it clearly as two syllables: "Snack-list". If the answer comes from the Alexa shopping list or the name isn't recognized, say "Alexa, open Snacklist" first and then what should go on the list.

## How to talk to it

Say several things in one sentence with "and" between them. A pause alone doesn't separate them.

| You say | On the list |
| --- | --- |
| Alexa, ask Snacklist to add milk and eggs | milk · eggs |
| Alexa, ask Snacklist to add two liters of milk | 2 l milk |
| Alexa, tell Snacklist we need bread, butter and cheese | bread · butter · cheese |

Quantities like "two liters of milk" become one item with a quantity. The skill tells you afterwards what went on the list. Things already on the list aren't added twice: the skill says "Already on Snacklist: milk."

Ask "Alexa, ask Snacklist what's on the list" and the skill reads at most 10 open items, in the order of your list, then for example "… and 4 more."

> **What happens to your voice**
>
> - Snacklist doesn't store voice recordings. Only the recognized text reaches us, for example "milk and eggs".
> - Amazon records your voice and turns it into text, under Amazon's Alexa terms and privacy notice. How long Amazon keeps recordings and how to delete them is set in the Alexa app.
> - More in the [privacy policy](/en/privacy).

## If it doesn't work

| What happens | Why | What helps |
| --- | --- | --- |
| The skill doesn't start, although you enabled it. | Your Alexa device is set to a language the skill doesn't support. It supports German (Germany) and English (US, UK, Australia, Canada, India). | Set the device language to one of these: Alexa app → **More** → **Settings** → **Device Settings** → your device → gear icon at the top right → under **General**, tap **Language**. |
| The answer says no list called Snacklist was found, or the item lands on the Alexa shopping list. | The sentence didn't contain "ask Snacklist". It went to the lists in the Alexa app. | Say "Alexa, ask Snacklist to add milk" or first "Alexa, open Snacklist" (see [How your sentence reaches the Snacklist skill](#reach-snacklist)). |
| The name isn't recognized, or another name is understood. | "Snacklist" wasn't recognized. | Say the name clearly as two syllables, "Snack-list", or start with "Alexa, open Snacklist". |
| "Please link your Snacklist account in the Alexa app first." | The skill isn't, or is no longer, linked to your Snacklist account. | On the skill's page in the Alexa app tap **Link account** and continue as in step 1. |
| "You're not in a household yet …" | Your Snacklist account isn't in a household. | Create a household in the app or join one. |

## Turn the skill off again

- **In the Alexa app:** find the skill **Snacklist** and tap **Disable skill** on its page.
- **In Snacklist:** tap **More**, then **Access**, and disconnect **Amazon Alexa** under connected apps. The skill loses access to your list right away.

Questions or problems? Write to us in the app under **More** → **Feedback & ideas**.
