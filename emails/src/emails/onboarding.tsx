// The tester mails from "Snacklist Launch Copy", section 2, word for word (drafts in
// docs/EMAIL.md, "Onboarding"). Snacklist PM edits the words here; the layout stays in the components.
import type { ReactElement } from 'react';
import { Greeting, Paragraph, PrimaryButton, Signature, Steps, TipBox, type UnsubscribeUrl } from '../components/index.ts';
import { OnboardingLayout } from '../layouts.tsx';

export type WelcomeProps = { name: string; googleEmail: string; joinUrl: string; unsubscribeUrl: UnsubscribeUrl };
export type NudgeProps = { name: string; unsubscribeUrl: UnsubscribeUrl };

const FEEDBACK = {
  de: 'Feedback gern als Antwort auf diese Mail oder in der App unter Mehr > „Feedback senden“.',
  en: 'Feedback is welcome as a reply to this email or in the app under More > “Send feedback”.',
};

export function WelcomeAndroidDe({ name, googleEmail, joinUrl, unsubscribeUrl }: WelcomeProps): ReactElement {
  return (
    <OnboardingLayout lang="de" title="Willkommen bei Snacklist: so geht's los" preview="So geht's los: Installieren, Anmelden, Haushalt."
      unsubscribeUrl={unsubscribeUrl} footerNote={FEEDBACK.de}>
      <Greeting>Hi {name}, schön, dass ihr dabei seid! So geht's los:</Greeting>
      <Steps steps={[
        {
          title: 'Installieren',
          children: (
            <>
              <Paragraph>Öffne diesen Link auf deinem Handy:</Paragraph>
              <PrimaryButton href={joinUrl} fallbackLabel="Falls der Knopf nicht geht, öffne diesen Link:">Jetzt mitmachen</PrimaryButton>
              <Paragraph><strong>Wichtig:</strong> Der Play Store muss mit {googleEmail} angemeldet sein (oben rechts aufs Profilbild tippen, um das Konto zu wechseln).</Paragraph>
              <Paragraph>Tipp auf „Tester werden“ und installier die App dann ganz normal aus dem Play Store. Nicht wundern: Sie heißt dort evtl. noch „com.snacklist.app“, und der Installieren-Knopf kann ein paar Minuten brauchen. Updates kommen danach automatisch.</Paragraph>
            </>
          ),
        },
        { title: 'Anmelden', children: <Paragraph>Mit Google, E-Mail und Passwort oder per Anmelde-Link. Ob die App anonyme Nutzungsdaten sammeln darf, entscheidest du; eure Liste wird dafür nie übertragen.</Paragraph> },
        { title: 'Haushalt', children: <Paragraph>Einer von euch erstellt einen Haushalt und lädt den anderen per Link oder Code ein. Die Einladung gilt 7 Tage und funktioniert einmal.</Paragraph> },
      ]} />
      <TipBox>
        <Paragraph><strong>Eure Aufgabe:</strong> Packt euren nächsten Einkauf drauf und nehmt die Liste mit in den Laden.</Paragraph>
        <Paragraph><strong>Meine Frage:</strong> Was hat euch beim ersten Einkauf gestört?</Paragraph>
      </TipBox>
      <Paragraph>Wenn's beim Installieren hakt, machen wir's kurz zusammen.</Paragraph>
      <Signature />
    </OnboardingLayout>
  );
}

export function WelcomeAndroidEn({ name, googleEmail, joinUrl, unsubscribeUrl }: WelcomeProps): ReactElement {
  return (
    <OnboardingLayout lang="en" title="Welcome to Snacklist: here's how to get started" preview="Here's how to get started: install, sign in, household."
      unsubscribeUrl={unsubscribeUrl} footerNote={FEEDBACK.en}>
      <Greeting>Hi {name}, glad you're in! Here's how to get started:</Greeting>
      <Steps steps={[
        {
          title: 'Install',
          children: (
            <>
              <Paragraph>Open this link on your phone:</Paragraph>
              <PrimaryButton href={joinUrl} fallbackLabel="If the button doesn't work, open this link:">Join the beta</PrimaryButton>
              <Paragraph><strong>Important:</strong> The Play Store needs to be signed in with {googleEmail} (tap your profile picture in the top right to switch accounts).</Paragraph>
              <Paragraph>Tap “Become a tester”, then install the app from the Play Store like any other app. Don't be surprised: it may still be listed as “com.snacklist.app”, and the Install button can take a few minutes to show up. Updates come automatically after that.</Paragraph>
            </>
          ),
        },
        { title: 'Sign in', children: <Paragraph>With Google, email and password, or a sign-in link. Whether the app may collect anonymous usage data is your call; your list is never sent for it.</Paragraph> },
        { title: 'Household', children: <Paragraph>One of you creates a household and invites the other by link or code. The invite is good for 7 days and works once.</Paragraph> },
      ]} />
      <TipBox>
        <Paragraph><strong>Your task:</strong> Put your next grocery run on the list and take it to the store.</Paragraph>
        <Paragraph><strong>My question:</strong> What bugged you on that first trip?</Paragraph>
      </TipBox>
      <Paragraph>If installing gets stuck, we'll set it up together.</Paragraph>
      <Signature />
    </OnboardingLayout>
  );
}

export function NudgeDe({ name, unsubscribeUrl }: NudgeProps): ReactElement {
  return (
    <OnboardingLayout lang="de" title="Ein Tipp für deinen nächsten Einkauf" preview="Ein Tipp für deinen nächsten Einkauf." unsubscribeUrl={unsubscribeUrl} footerNote={FEEDBACK.de}>
      <Greeting>Hi {name},</Greeting>
      <TipBox title="Ein Tipp für deinen nächsten Einkauf">
        <Paragraph>Schieb die Kategorien einmal in die Reihenfolge, in der du durch deinen Laden läufst. Dann gehst du die Liste im Laden einfach von oben nach unten durch.</Paragraph>
      </TipBox>
      <Paragraph><strong>Und:</strong> Wie lief's bisher? Ein kurzer Satz als Antwort reicht völlig.</Paragraph>
      <Signature />
    </OnboardingLayout>
  );
}

export function NudgeEn({ name, unsubscribeUrl }: NudgeProps): ReactElement {
  return (
    <OnboardingLayout lang="en" title="One tip for your next grocery run" preview="One tip for your next grocery run." unsubscribeUrl={unsubscribeUrl} footerNote={FEEDBACK.en}>
      <Greeting>Hi {name},</Greeting>
      <TipBox title="One tip for your next grocery run">
        <Paragraph>Drag the categories into the order you walk through your store, just once. Then you simply go down the list from top to bottom.</Paragraph>
      </TipBox>
      <Paragraph><strong>And:</strong> How's it going so far? A quick sentence in reply is plenty.</Paragraph>
      <Signature />
    </OnboardingLayout>
  );
}
