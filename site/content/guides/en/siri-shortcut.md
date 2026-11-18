---
title: "Snacklist with Siri (German only for now)"
description: "The Snacklist Siri Shortcut works in German only for now. Here's what that means and where to find the German setup guide."
slug: siri-shortcut
locale: en
translation_key: siri-shortcut
updated: 2026-10-27
---

# Snacklist with Siri (German only for now)

You can add items to Snacklist with Siri using a Shortcut you set up yourself in the Shortcuts app. Right now this only works in German: the setup guide is in German, and Snacklist can only split spoken German sentences into separate items.

If you're comfortable with German, you can follow the German guide: [Snacklist per Siri: Kurzbefehl einrichten](/de/anleitungen/siri-kurzbefehl)

We'll update this page if that changes.

## Siri without setup {#without-setup since=1.0.0 once=native-siri}

> Draft for Snacklist PM: please review the text and phrases before launch.

With the current app you don't need a Shortcut. Once you're signed in to Snacklist and belong to a household, Siri knows Snacklist by itself, in English and in German. There's nothing to set up and no token to copy.

> **You:** Hey Siri, add to Snacklist.
> **Siri:** What should I add?
> **You:** Milk, eggs and bread.
> **Siri:** Added milk, eggs and bread to Snacklist.

Siri understands these phrases:

| You say | What happens |
| --- | --- |
| Add to Snacklist | Siri asks what to add. |
| Add something to my Snacklist | Siri asks what to add. |
| Add milk to Snacklist | Milk goes straight on the list if milk has been on your list before. Otherwise Siri asks. |
| What's on my Snacklist? | Siri reads the first ten open items. |

Siri says "Added" only after Snacklist has saved the items. Without internet or when something goes wrong, Siri says that nothing was added. Then just try again.

You'll also find all phrases in the app under **More** → **Access** → **Show Siri phrases**. There you'll also see "Siri (this iPhone)": that's the sign-in Siri uses for you. It ends when you sign out of Snacklist.

If you set up the old German Shortcut, it keeps working. You can delete it and revoke its token under **More** → **Access**.
