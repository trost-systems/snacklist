---
title: Data processing agreement for clubs
description: "Draft: data processing agreement under Art. 28 GDPR for clubs that use a Snacklist household."
locale: en
path: /en/dpa
translation_key: dpa
updated: 2026-11-08
draft: true
---

# Data processing agreement under Art. 28 GDPR

ENTWURF / DRAFT, not published, not linked. This text is waiting for review by Legal (open questions in `docs/legal/169b-privacy-draft.md`).

This is a translation. The [German version](/avv) is authoritative.
Last updated: 8 November 2026

## 1. Parties

The controller is the club that uses a Snacklist household for its members (the "club"). A person authorised to represent the club concludes this agreement on its behalf.

The processor is Peter Trost, Yalovastr. 5, 72108 Rottenburg am Neckar, Germany, e-mail [support@snacklist.app](mailto:support@snacklist.app), the provider of Snacklist ("Snacklist").

## 2. Subject matter

The club uses a household in Snacklist to keep shared shopping lists with its members, for example for a club party. Snacklist stores and processes this household's data for the club. This agreement covers data protection only.

This agreement does not cover the data that Snacklist processes as a controller in its own right, as described in the [privacy policy](/en/privacy): each person's account (e-mail address, password, sign-in with Google or Apple, display name in the profile), their other households, usage data and error reports, support requests, feedback, purchases and the connections a person sets up themselves (Siri, Alexa, AI assistants). Each member has their own account and their own terms of use with Snacklist.

## 3. Term

This agreement applies as long as the club uses the household. It ends when the household is deleted or when the club terminates the agreement in text form (for example e-mail). Section 13 applies to the time after that.

## 4. Nature and purpose of the processing

Snacklist stores the household's data, shows it to its members in the app, syncs it between their devices, assigns items to categories and stores, and backs it up. The sole purpose is to let the club's members keep shared lists.

## 5. Types of data

- Name and kind of the household, whether joins must be approved
- Memberships: who is a member, with the display name the other members see, the role (owner, admin, member) and when the person joined
- Lists: name, order, who created them and when
- Items: item name, quantity, brand, properties, category, store, who added and ticked them off, timestamps, and names of people if members write them into an item
- History of changes to items
- "I'll bring it" claims: which member brings which item, with an optional quantity
- Invites: who created them, kind, expiry, number of joins and of views of the join page; who joined through which invite and when
- Join requests: who wants to join, through which invite, when, the decision, and when and by whom it was made
- Removals: who was removed from the household and when, for 30 days
- What Snacklist learns for the household (categories, stores, brands and their order)

Special categories of personal data (Art. 9 GDPR) are not intended. Snacklist has no fields for them. The club tells its members not to write such details into items.

## 6. Categories of data subjects

- Members of the club and other people who join the household, for example helpers
- People who want to join a household (join requests)
- People whose names members write into items

## 7. Instructions

Snacklist processes the data only on documented instructions from the club, including for transfers to third countries, unless the law of the Union or Germany requires processing; in that case Snacklist informs the club before processing, as far as that law allows (Art. 28(3)(a) GDPR). The instructions are this agreement and the settings and actions the club's owner and admins carry out in the app (for example removing members, approving joins, deleting lists). The club gives further instructions in text form (for example e-mail) to [support@snacklist.app](mailto:support@snacklist.app).

If Snacklist considers an instruction unlawful, Snacklist informs the club without undue delay (Art. 28(3), second subparagraph, GDPR).

## 8. Confidentiality

Peter Trost runs Snacklist alone. Only he and the automated processes he has set up for operation and backups have access to the household's data outside the app. Peter Trost is bound to confidentiality. If Snacklist engages further people, Snacklist binds them to confidentiality beforehand (Art. 28(3)(b) GDPR).

## 9. Technical and organisational measures

Snacklist takes the measures under Art. 32 GDPR. At the time of this agreement, they are:

- The database is hosted by Supabase in a data centre in Frankfurt am Main.
- Every connection to the app, the web app and the server is encrypted with TLS.
- Database access rules (Row Level Security) protect every table with household data. Only a household's members read its data; join requests are visible only to the person asking and to the owner and admins. Automated tests check these rules for every table.
- Snacklist stores passwords only as hashes. Snacklist stores access tokens only as hashes (SHA-256); only the person who creates a token sees the token itself.
- A backup of the database is made every night. It is encrypted (age) before it is stored, cannot be read without the private key, and is deleted after 90 days.
- The database provider's logs are deleted after at most 1 day.
- Changes to the database and the server go live only after automated checks.

Snacklist may develop the measures further as long as the level of protection does not drop.

## 10. Sub-processors

The club permits Snacklist to engage these sub-processors:

- Supabase Pte. Ltd., Singapore: database, sign-in, server functions. The database is in Frankfurt am Main; server functions run at the location nearest the request, including outside the EU. Basis for transfers: Standard Contractual Clauses in Supabase's data processing agreement.
- Vercel Inc., USA: delivery of the web app and the join page, forwarding of mcp.snacklist.app. Basis: EU-US Data Privacy Framework and Standard Contractual Clauses.
- GitHub Inc., USA: storage of the encrypted backups. Basis: EU-US Data Privacy Framework.

Snacklist binds each sub-processor by contract to obligations that correspond to this agreement (Art. 28(4) GDPR). If Snacklist wants to add or replace a sub-processor, Snacklist informs the club beforehand in text form (for example e-mail). The club can object within 30 days. If it objects, it can terminate this agreement.

## 11. Rights of data subjects

Members can exercise many rights themselves in the app: change and delete items, take back claims, leave the household, export their data and delete their account. The owner and admins can remove members and decide on join requests. Beyond that, Snacklist supports the club with requests under Art. 15 to 22 GDPR. If Snacklist receives a request that concerns the household's data, Snacklist forwards it to the club without undue delay.

## 12. Further support, personal data breaches

Snacklist supports the club in meeting its obligations under Art. 32 to 36 GDPR with the information available to Snacklist. If Snacklist becomes aware of a breach of the security of the household's data, Snacklist reports it to the club without undue delay, with the details under Art. 33(3) GDPR as far as they are known.

## 13. Deletion and return

When this agreement ends, Snacklist deletes the household's data. If the last member leaves the household, Snacklist deletes the data immediately. The data disappears from the backups after at most 90 days. Before deletion, Snacklist provides the club, on request in text form (for example e-mail), with the household's data as a JSON file. Any obligation to store the data under the law of the Union or Germany remains unaffected.

## 14. Evidence and audits

On request, Snacklist provides the club with the information it needs to demonstrate compliance with this agreement, and allows audits by the club or by an auditor it appoints who is bound to confidentiality (Art. 28(3)(h) GDPR). The club announces an on-site audit at least 14 days in advance.

## 15. Liability

Liability is governed by the statutory provisions, in particular Art. 82 GDPR.

## 16. Final provisions

Changes to this agreement must be made in text form (for example e-mail). German law applies.
