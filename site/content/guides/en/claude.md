---
title: "Connect Snacklist to Claude"
description: "Connect Claude to your Snacklist in under five minutes. Then Claude adds items, ticks them off and tells you what's still missing."
slug: claude
locale: en
translation_key: claude
updated: 2026-11-04
---

# Connect Snacklist to Claude

Claude can read your Snacklist, add items, change them, tick them off, put them back, delete them and move them to another store or list. Just tell Claude what you need:

> **You:** Put milk, two cucumbers and toilet paper on the Snacklist.
> **Claude:** I've added milk, 2 cucumbers and toilet paper to your Snacklist.

The items show up right away on every device in your household, in the right spot on the list. Setting it up takes less than five minutes. You don't copy any key: Claude signs in with your Snacklist account.

## What you need

- a Claude account at [claude.ai](https://claude.ai). On Claude Free you can add only one custom connector. In a Claude organization (Team or Enterprise), an admin may have to add the connector.
- the Snacklist app, signed in and part of a household
- a browser, ideally on a computer. Afterwards the connector is also available in the Claude apps on your phone and desktop.

::: once integration-lock
AI assistant access needs Snacklist Premium for your household.
:::

## Step 1: Add the connector

Menu names in Claude may differ slightly between Claude versions.

1. Open [claude.ai](https://claude.ai) and sign in.
2. Open **Customize**, then **Connectors**.
3. Click **+ Add**, then **Add custom connector**.
4. Enter `Snacklist` as the name and this URL:

   ```text
   https://mcp.snacklist.app
   ```

   Leave the advanced settings (OAuth Client ID and Secret) empty.
5. Click **Add**.

## Step 2: Connect and allow

1. In the list of connectors, click **Connect** next to **Snacklist**. A new window opens Snacklist.
2. Sign in if Snacklist asks, the same way you do in the app.
3. Snacklist asks "Allow access?" and shows what Claude may do: read, add, change, tick off and remove items on your shopping list. Check that it shows your household, then click **Allow**.
4. Claude then needs a few seconds to finish connecting. Meanwhile the window shows "Done, you can return to Claude." or stays blank for up to ten seconds. Wait until it closes or Claude shows the connector as connected.

## Step 3: Try it

1. Start a new chat in Claude.
2. In the tools and connectors menu below the message field, check that **Snacklist** is turned on.
3. Write, for example, "What's on the Snacklist?".
4. The first time, Claude asks whether it may use Snacklist. Allow it once or always.

| You write | What happens |
| --- | --- |
| Put milk, 2 cucumbers and Pampers diapers size 3 on the Snacklist. | Three items, each in its spot. The diapers keep "Pampers" as the brand. |
| What's on the Snacklist? | Claude lists the open items in your list's order and tells you how many there are. |
| What do I need at dm? | Everything for dm and everything without a store, in dm's order. |
| Tick off milk and cucumbers. | Both leave the list and show up in the app under "Recently used". |
| Move the oat milk to Getränke. | Snacklist remembers this for your household. Next time oat milk goes straight there. |
| Make it 3 cucumbers. | The cucumbers' quantity is now 3. |
| We still need the milk after all. | The milk you just ticked off is back on the list. |
| Delete the sparkling wine. | The sparkling wine is gone. What Snacklist learned about it (for example the store) stays. |
| What else do we often buy? | What you buy often that is not on the list now, like the suggestions in the app. |
| What did we buy last? | What was ticked off last, like "Recently used" in the app. |

Anything already on the list isn't added twice. Claude tells you it's already there. Snacklist was made for German shopping lists: its built-in word list is German, so it sorts German item names best. It knows common English words too, and Claude can write items in German for you if you ask.

> **What Claude sees**
>
> - Claude sees only your shopping list: items and stores. Claude never gets your password.
> - What you write to Claude and what Snacklist answers is processed by Anthropic under its own privacy policy.
> - Read more in the [privacy policy](/en/privacy) under "Siri, Alexa and AI assistants".

## If it doesn't work

| What happens | Why | What helps |
| --- | --- | --- |
| After **Allow** the window stays blank for a few seconds. | Claude is finishing the connection on its side. | Wait up to ten seconds. If Claude still doesn't show the connector as connected, click **Connect** again. |
| "This request is invalid or has expired. Start the connection again in your app." | Claude's request is a few minutes old or was used already. | Click **Connect** in Claude again. |
| Claude says it can't access Snacklist. | Snacklist is turned off in this chat. | Turn on **Snacklist** in the tools and connectors menu. |
| Claude can't find an item. | The name matches several items or none. | Write the name the way the app shows it. Claude gets the matching names to choose from. |
| An item is in the wrong store. | Snacklist put the item in a different store. | Tell Claude, for example, "Move feta to the farmers market". Snacklist remembers this for your household. |

## Disconnect Claude

Either way ends the connection right away:

- **In Snacklist:** Tap **More**, then **Access**. Under **Connected apps**, tap the disconnect icon next to **Claude** and confirm with **Disconnect**.
- **In Claude:** Open **Customize** → **Connectors** and click **Remove** next to **Snacklist**, or Remove in its three-dot menu.

## For power users: Claude Code and Codex

**Claude Code** connects with one command. Then run `/mcp` in Claude Code and choose **Authenticate**. The same "Allow access?" page opens.

```bash
claude mcp add --transport http snacklist https://mcp.snacklist.app
```

**Codex** (the CLI and the IDE extension share `~/.codex/config.toml`) works the same way, but isn't an officially supported path:

```toml
[mcp_servers.snacklist]
url = "https://mcp.snacklist.app"
```

```bash
codex mcp login snacklist
```

::: until unified-keys-guides
For scripts and programs that can't sign in, create an access token in the app under **More** → **Access** → **Create token**. It's shown only once. Send it as `Authorization: Bearer fgp_…`.
:::

::: once unified-keys-guides
For scripts and programs that can't sign in, create an access key in the app under **More** → **Access** → **Create key**. Choose **Read and write** if the program should change your list. It's shown only once. Send it as `Authorization: Bearer fgp_…`. The same key also works for the Snacklist API.
:::

Questions or problems? Write to me in the app under **More** → **Send feedback**.
