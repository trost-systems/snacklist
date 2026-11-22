# emails

The Snacklist mails in React Email: components, two layouts, every mail, and the build that
writes Supabase's auth templates. System, rules and template inventory: [`docs/EMAIL.md`](../docs/EMAIL.md).

```sh
npm ci
npm run build        # supabase/templates/ and the template block in supabase/config.toml
npm test             # type checks + unit tests (CI: scripts/gates/emails.sh)
npm run production   # fails while a draft or the demo unsubscribe link is in a mail
flock /tmp/fg-e2e.lock npm run preview -- --out /tmp/fg-55-previews [<id> ...]
```

Pinned versions, `package-lock.json` committed. No React Email CLI (no dev server, no telemetry):
`tsx` runs the TSX directly.

## A mail in full

```tsx
import { Greeting, Paragraph, PrimaryButton, Signature, Steps, TipBox, type UnsubscribeUrl } from '../components/index.ts';
import { OnboardingLayout } from '../layouts.tsx';

export function TipDe({ name, unsubscribeUrl }: { name: string; unsubscribeUrl: UnsubscribeUrl }) {
  return (
    <OnboardingLayout lang="de" title="Ein Tipp" preview="Ein Tipp für deinen Einkauf." unsubscribeUrl={unsubscribeUrl}>
      <Greeting>Hi {name},</Greeting>
      <Steps steps={[
        { title: 'Öffnen', children: <Paragraph>Öffne die Liste.</Paragraph> },
        { title: 'Ziehen', children: <Paragraph>Zieh die Kategorien in deine Reihenfolge.</Paragraph> },
      ]} />
      <TipBox title="Gut zu wissen"><Paragraph>Das merkt sich Snacklist für alle im Haushalt.</Paragraph></TipBox>
      <PrimaryButton href="https://app.snacklist.app" fallbackLabel="Falls der Knopf nicht geht, öffne diesen Link:">Liste öffnen</PrimaryButton>
      <Signature />
    </OnboardingLayout>
  );
}
```

Then add it to `EMAILS` in `src/registry.tsx` and run `npm test` and the preview.

## Layouts

| Layout | Props | Use |
| --- | --- | --- |
| `AuthLayout` | `lang: 'de' \| 'en'`, `title` (the HTML title), `reason: { confirmed: string } \| { draft: string }`, `children` | Transactional: sign-in, account, a member joined. `TransactionalFooter`, no preheader, nothing promotional. |
| `OnboardingLayout` | `lang`, `title`, `preview` (inbox preheader), `unsubscribeUrl: UnsubscribeUrl`, `footerNote?` (e.g. where feedback goes), `children` | Tips and onboarding. `OnboardingFooter` with the one-click unsubscribe link. |

Both draw the page, the header (logo + wordmark), one white card with the navy contour, and the
footer below the card.

## Components

| Component | Props | Notes |
| --- | --- | --- |
| `Header` | none | The app icon (`https://snacklist.app/email/snacklist-icon-96.png`, 48 px at 2x) and "Snacklist" as live text. The layouts add it. |
| `Heading` | `children` | The one headline. 36 px Bricolage, 22 px on phones. |
| `Greeting` | `children` | The opening line: `<Greeting>Hi {name},</Greeting>`. |
| `Paragraph` | `children` | Body text, 17 px Inter. Lead-ins in `<strong>`. |
| `TextLink` | `href`, `children` | A link inside a sentence. Plain text prints its URL after the paragraph. |
| `Steps` | `steps: StepList` (2 to 4 of `{ title, children }`) | Numbered yellow badges. 1 or 5 steps do not compile. Plain text: `1. Title`. |
| `TipBox` | `title?`, `children` | Yellow left border on the yellow tint. |
| `CodeBox` | `children: string` | A one-time code, large and spaced. |
| `PrimaryButton` | `href`, `children: string` (label), `fallbackLabel?` | The one call to action: 48 px, yellow with the navy contour, VML for Outlook, the raw link under it (after `fallbackLabel` if given). A second one in a mail throws. |
| `PhoneScreenshot` | `src: \`https://snacklist.app/${string}.png\``, `alt` (required, non-empty), `width = 240`, `height` | A phone screen in the navy frame. PNG at 2x, demo data only. Alt text shows when images are blocked. |
| `Signature` | `children = 'Peter'` | The sign-off. |
| `Draft` | `children: string` | Body text not written yet. Shows `[DRAFT]`; a production render refuses it. |
| `TransactionalFooter` | `lang`, `reason` | Legal N-15 a. `AuthLayout` adds it. |
| `OnboardingFooter` | `lang`, `unsubscribeUrl`, `note?` | Legal N-15 b. `OnboardingLayout` adds it. Throws without a real unsubscribe URL. |

Helpers: `onboardingHeaders(token)` returns the `List-Unsubscribe` and `List-Unsubscribe-Post`
headers for an onboarding send; `renderEmail(element, { production })` (`src/render.ts`) returns
`{ html, text }`.

## Scripts

| Script | What |
| --- | --- |
| `scripts/build.tsx` | Writes `supabase/templates/` (each auth mail's German and English render in one Go template, AL4's pick) and config.toml's template block; `--check`, `--production`. |
| `scripts/preview.tsx` | Renders every mail, German and English, to PNG (600 and 375 px, dark for magic link and welcome, images blocked, both footers) plus a contact sheet and `index.html`, one review page with each mail's subject, PNGs, HTML and plain text. |
| `scripts/demo-screen.tsx` | Writes `site/public/email/demo-list-de.png` from the homepage's add-tick scene, for the catalog's `PhoneScreenshot`. |
