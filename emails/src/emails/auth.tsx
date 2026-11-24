// Every mail Supabase Auth can send, in German and English, restyled. The six the app's flows send
// keep AL4's wording word for word (docs/AUTH.md "Mail language"); the seven security notices,
// off on every project, keep Supabase's English and get a German draft. Keep the Go template
// variables exactly as they are: Supabase fills them when it sends. Build: npm run build (writes
// supabase/templates/ and the template block in supabase/config.toml).
import type { ReactElement } from 'react';
import { CodeBox, Heading, Paragraph, PrimaryButton, type Reason } from '../components/index.ts';
import { AuthLayout } from '../layouts.tsx';
import type { Lang } from '../lang.ts';

export type AuthTemplate =
  | 'confirmation' | 'magic_link' | 'recovery' | 'email_change' | 'invite' | 'reauthentication'
  | 'password_changed_notification' | 'email_changed_notification' | 'phone_changed_notification'
  | 'mfa_factor_enrolled_notification' | 'mfa_factor_unenrolled_notification'
  | 'identity_linked_notification' | 'identity_unlinked_notification';

type Block = { p: string } | { button: string } | { code: true };
type Copy = { subject: string; heading: string; body: Block[]; reason: Reason };
type AuthMail = { template: AuthTemplate; copy: Record<Lang, Copy>; note?: string };

const URL = '{{ .ConfirmationURL }}';
const contact = {
  de: { p: 'Wenn du diese Änderung nicht vorgenommen hast, wende dich sofort an den Support.' },
  en: { p: "If you didn't make this change, contact support immediately." },
};
const security: Record<Lang, Reason> = {
  de: { draft: 'Du bekommst diese E-Mail, weil sich eine Sicherheitseinstellung deines Snacklist-Kontos geändert hat.' },
  en: { draft: "You're getting this e-mail because a security setting of your Snacklist account changed." },
};

export const AUTH_MAILS: AuthMail[] = [
  {
    template: 'confirmation',
    copy: {
      de: {
        subject: 'Bestätige deine E-Mail-Adresse für Snacklist', heading: 'Bestätige deine E-Mail-Adresse',
        body: [
          { p: 'Öffne den Link unten, um diese E-Mail-Adresse zu bestätigen und dein Snacklist-Konto fertig einzurichten.' },
          { button: 'E-Mail-Adresse bestätigen' },
          { p: 'Wenn du dich nicht bei Snacklist registriert hast, kannst du diese E-Mail einfach ignorieren.' },
        ],
        reason: { confirmed: 'Du bekommst diese E-Mail, weil sich jemand mit dieser Adresse bei Snacklist registriert hat. Warst du das nicht, ignoriere sie einfach.' },
      },
      en: {
        subject: 'Confirm your email address for Snacklist', heading: 'Confirm your email address',
        body: [
          { p: 'Follow the link below to confirm this email address and finish setting up your Snacklist account.' },
          { button: 'Confirm email address' },
          { p: "If you didn't sign up for Snacklist, you can safely ignore this email." },
        ],
        reason: { confirmed: "You're getting this e-mail because someone signed up for Snacklist with this address. If that wasn't you, just ignore it." },
      },
    },
  },
  {
    template: 'magic_link',
    copy: {
      de: {
        subject: 'Dein Anmeldelink für Snacklist', heading: 'Dein Anmeldelink',
        body: [
          { p: 'Öffne den Link unten, um dich bei Snacklist anzumelden. Er ist nur kurz gültig und funktioniert nur einmal.' },
          { button: 'Anmelden' },
          { p: 'Wenn du keinen Anmeldelink angefordert hast, kannst du diese E-Mail einfach ignorieren.' },
        ],
        reason: { confirmed: 'Du bekommst diese E-Mail, weil mit dieser Adresse ein Anmeldelink für Snacklist angefordert wurde. Warst du das nicht, ignoriere sie einfach.' },
      },
      en: {
        subject: 'Your Snacklist sign-in link', heading: 'Your sign-in link',
        body: [
          { p: 'Follow the link below to sign in to Snacklist. This link expires shortly and can only be used once.' },
          { button: 'Sign in' },
          { p: "If you didn't ask for a sign-in link, you can safely ignore this email." },
        ],
        reason: { confirmed: "You're getting this e-mail because a Snacklist sign-in link was requested for this address. If that wasn't you, just ignore it." },
      },
    },
  },
  {
    template: 'recovery',
    copy: {
      de: {
        subject: 'Setze dein Snacklist-Passwort zurück', heading: 'Passwort zurücksetzen',
        body: [
          { p: 'Jemand möchte das Passwort für dein Snacklist-Konto zurücksetzen. Öffne den Link unten, um ein neues zu wählen.' },
          { button: 'Passwort zurücksetzen' },
          { p: 'Wenn du das nicht warst, kannst du diese E-Mail einfach ignorieren. Dein Passwort bleibt dann unverändert.' },
        ],
        reason: { confirmed: 'Du bekommst diese E-Mail, weil für das Snacklist-Konto mit dieser Adresse ein neues Passwort angefordert wurde.' },
      },
      en: {
        subject: 'Reset your Snacklist password', heading: 'Reset your password',
        body: [
          { p: 'We received a request to reset the password for your Snacklist account. Follow the link below to choose a new one.' },
          { button: 'Reset password' },
          { p: "If you didn't request this, you can safely ignore this email. Your password stays the same." },
        ],
        reason: { confirmed: "You're getting this e-mail because a password reset was requested for the Snacklist account with this address." },
      },
    },
  },
  {
    template: 'email_change',
    copy: {
      de: {
        subject: 'Bestätige deine neue E-Mail-Adresse für Snacklist', heading: 'Bestätige deine neue E-Mail-Adresse',
        body: [
          { p: 'Öffne den Link unten, um {{ .NewEmail }} als neue E-Mail-Adresse für dein Snacklist-Konto zu bestätigen.' },
          { button: 'Neue E-Mail-Adresse bestätigen' },
          { p: 'Wenn du diese Änderung nicht angefordert hast, kannst du diese E-Mail einfach ignorieren.' },
        ],
        reason: { confirmed: 'Du bekommst diese E-Mail, weil die E-Mail-Adresse deines Snacklist-Kontos geändert werden soll.' },
      },
      en: {
        subject: 'Confirm your new email address for Snacklist', heading: 'Confirm your new email address',
        body: [
          { p: 'Follow the link below to confirm {{ .NewEmail }} as the new email address for your Snacklist account.' },
          { button: 'Confirm new email address' },
          { p: "If you didn't request this change, you can safely ignore this email." },
        ],
        reason: { confirmed: "You're getting this e-mail because a change of your Snacklist account's e-mail address was requested." },
      },
    },
  },
  {
    template: 'invite',
    note: 'Unused: the app never calls inviteUserByEmail. Must not be used for household invites (Legal N-18).',
    copy: {
      de: {
        subject: 'Du wurdest zu Snacklist eingeladen', heading: 'Du wurdest zu Snacklist eingeladen',
        body: [
          { p: 'Öffne den Link unten, um die Einladung anzunehmen und dein Snacklist-Konto anzulegen.' },
          { button: 'Einladung annehmen' },
        ],
        reason: { confirmed: 'Du bekommst diese E-Mail, weil du eingeladen wurdest, ein Snacklist-Konto anzulegen.' },
      },
      en: {
        subject: "You've been invited to Snacklist", heading: "You've been invited to Snacklist",
        body: [
          { p: 'Follow the link below to accept the invitation and create your Snacklist account.' },
          { button: 'Accept invitation' },
        ],
        reason: { confirmed: "You're getting this e-mail because you were invited to create a Snacklist account." },
      },
    },
  },
  {
    template: 'reauthentication',
    copy: {
      de: {
        subject: '{{ .Token }} ist dein Snacklist-Bestätigungscode', heading: 'Dein Bestätigungscode',
        body: [{ p: 'Gib diesen Code in Snacklist ein, um zu bestätigen, dass du es bist. Er ist nur kurz gültig.' }, { code: true }],
        reason: { confirmed: 'Du bekommst diese E-Mail, weil für dein Snacklist-Konto ein Bestätigungscode angefordert wurde.' },
      },
      en: {
        subject: '{{ .Token }} is your Snacklist verification code', heading: 'Your verification code',
        body: [{ p: "Enter this code in Snacklist to confirm it's you. It expires shortly." }, { code: true }],
        reason: { confirmed: "You're getting this e-mail because a verification code was requested for your Snacklist account." },
      },
    },
  },
  {
    template: 'password_changed_notification',
    copy: {
      de: {
        subject: 'Dein Passwort wurde geändert', heading: 'Dein Passwort wurde geändert',
        body: [
          { p: 'Das Passwort für dein Konto wurde gerade geändert.' },
          contact.de,
        ],
        reason: security.de,
      },
      en: {
        subject: 'Your password was changed', heading: 'Your password was changed',
        body: [
          { p: 'The password for your account was recently changed.' },
          contact.en,
        ],
        reason: security.en,
      },
    },
  },
  {
    template: 'email_changed_notification',
    copy: {
      de: {
        subject: 'Deine E-Mail-Adresse wurde geändert', heading: 'Deine E-Mail-Adresse wurde geändert',
        body: [{ p: 'Die E-Mail-Adresse für dein Konto wurde von {{ .OldEmail }} in {{ .Email }} geändert.' }, contact.de],
        reason: security.de,
      },
      en: {
        subject: 'Your email address was changed', heading: 'Your email address was changed',
        body: [{ p: 'The email address for your account was changed from {{ .OldEmail }} to {{ .Email }}.' }, contact.en],
        reason: security.en,
      },
    },
  },
  {
    template: 'phone_changed_notification',
    copy: {
      de: {
        subject: 'Deine Telefonnummer wurde geändert', heading: 'Deine Telefonnummer wurde geändert',
        body: [{ p: 'Die Telefonnummer für dein Konto wurde von {{ .OldPhone }} in {{ .Phone }} geändert.' }, contact.de],
        reason: security.de,
      },
      en: {
        subject: 'Your phone number was changed', heading: 'Your phone number was changed',
        body: [{ p: 'The phone number for your account was changed from {{ .OldPhone }} to {{ .Phone }}.' }, contact.en],
        reason: security.en,
      },
    },
  },
  {
    template: 'mfa_factor_enrolled_notification',
    copy: {
      de: {
        subject: 'Deinem Konto wurde eine neue Bestätigungsmethode hinzugefügt', heading: 'Neue Bestätigungsmethode hinzugefügt',
        body: [{ p: 'Die Bestätigungsmethode {{ .FactorType }} für die Anmeldung wurde deinem Konto hinzugefügt.' }, contact.de],
        reason: security.de,
      },
      en: {
        subject: 'A new verification method was added to your account', heading: 'A new verification method was added',
        body: [{ p: 'Sign-in verification method {{ .FactorType }} was added to your account.' }, contact.en],
        reason: security.en,
      },
    },
  },
  {
    template: 'mfa_factor_unenrolled_notification',
    copy: {
      de: {
        subject: 'Eine Bestätigungsmethode wurde von deinem Konto entfernt', heading: 'Bestätigungsmethode entfernt',
        body: [{ p: 'Die Bestätigungsmethode {{ .FactorType }} für die Anmeldung wurde von deinem Konto entfernt.' }, contact.de],
        reason: security.de,
      },
      en: {
        subject: 'A verification method was removed from your account', heading: 'A verification method was removed',
        body: [{ p: 'Sign-in verification method {{ .FactorType }} was removed from your account.' }, contact.en],
        reason: security.en,
      },
    },
  },
  {
    template: 'identity_linked_notification',
    copy: {
      de: {
        subject: 'Eine neue Anmeldemethode wurde mit deinem Konto verknüpft', heading: 'Neue Anmeldemethode verknüpft',
        body: [{ p: 'Dein {{ .Provider }}-Konto wurde als neue Anmeldemethode für {{ .Email }} verknüpft.' }, contact.de],
        reason: security.de,
      },
      en: {
        subject: 'A new sign-in method was linked to your account', heading: 'A new sign-in method was linked',
        body: [{ p: 'Your {{ .Provider }} account was linked as a new sign-in method for {{ .Email }}.' }, contact.en],
        reason: security.en,
      },
    },
  },
  {
    template: 'identity_unlinked_notification',
    copy: {
      de: {
        subject: 'Eine Anmeldemethode wurde von deinem Konto entfernt', heading: 'Anmeldemethode entfernt',
        body: [{ p: 'Dein {{ .Provider }}-Konto wurde als Anmeldemethode für {{ .Email }} entfernt.' }, contact.de],
        reason: security.de,
      },
      en: {
        subject: 'A sign-in method was removed from your account', heading: 'A sign-in method was removed',
        body: [{ p: 'Your {{ .Provider }} account was removed as a sign-in method for {{ .Email }}.' }, contact.en],
        reason: security.en,
      },
    },
  },
];

export function AuthEmail({ mail, lang }: { mail: AuthMail; lang: Lang }): ReactElement {
  const copy = mail.copy[lang];
  return (
    <AuthLayout lang={lang} title={copy.heading} reason={copy.reason}>
      <Heading>{copy.heading}</Heading>
      {copy.body.map((block, i) =>
        'p' in block ? <Paragraph key={i}>{block.p}</Paragraph>
          : 'button' in block ? <PrimaryButton key={i} href={URL}>{block.button}</PrimaryButton>
            : <CodeBox key={i}>{'{{ .Token }}'}</CodeBox>,
      )}
    </AuthLayout>
  );
}

// AL4's language pick (docs/AUTH.md "Mail language"): German when the account saved
// user_metadata.mail_locale "de", English otherwise, also with no metadata at all.
const PICK = '{{ $de := false }}{{ with .Data }}{{ $de = eq (printf "%v" .mail_locale) "de" }}{{ end }}';

/** One subject line for both languages, as GoTrue renders subjects as Go templates too. */
export const subjectTemplate = ({ de, en }: Record<Lang, string>): string => `${PICK}{{ if $de }}${de}{{ else }}${en}{{ end }}`;

/** One template file holding both rendered mails; GoTrue picks the branch per reader. */
export const bodyTemplate = ({ de, en }: Record<Lang, string>): string => [
  '{{- /* Generated from emails/ (cd emails && npm run build), do not edit. German when the account saved mail_locale "de" (the app sets user_metadata.mail_locale), else English. See docs/AUTH.md. */ -}}',
  '{{- $de := false }}{{ with .Data }}{{ $de = eq (printf "%v" .mail_locale) "de" }}{{ end -}}',
  '{{ if $de -}}',
  de.trimEnd(),
  '{{- else -}}',
  en.trimEnd(),
  '{{- end }}',
  '',
].join('\n');
