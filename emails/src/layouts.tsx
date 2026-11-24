import { Body, Head, Html, Preview } from '@react-email/components';
import type { ReactElement, ReactNode } from 'react';
import { Header, OnboardingFooter, TransactionalFooter, type Reason, type UnsubscribeUrl } from './components/index.ts';
import type { Lang } from './lang.ts';
import { Raw, mso } from './raw.tsx';
import { CONTAINER, css, msoHead, ui } from './theme.ts';

type ShellProps = { lang: Lang; title: string; preview?: string; footer: ReactNode; children: ReactNode };

/**
 * The frame every Snacklist mail shares: surface page, header, one raised card with the navy
 * contour, footer. Fluid up to 600 px; Outlook gets a fixed 600 px ghost table.
 */
function Shell({ lang, title, preview, footer, children }: ShellProps) {
  return (
    <Html lang={lang} dir="ltr">
      <Head>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <meta name="supported-color-schemes" content="light dark" />
        <meta name="format-detection" content="telephone=no, date=no, address=no, email=no, url=no" />
        <title>{title}</title>
        <style dangerouslySetInnerHTML={{ __html: css }} />
        <Raw html={msoHead} />
      </Head>
      <Body className="hl-page" style={{ margin: 0, padding: 0, backgroundColor: ui.light.surface }}>
        {preview ? <Preview>{preview}</Preview> : null}
        <table role="presentation" width="100%" cellPadding={0} cellSpacing={0} border={0} bgcolor={ui.light.surface} className="hl-page" style={{ backgroundColor: ui.light.surface }}>
          <tbody>
            <tr>
              <td align="center" className="hl-gutter" style={{ padding: `${ui.space[5]}px ${ui.space[4]}px ${ui.space[6]}px ${ui.space[4]}px` }}>
                <Raw html={mso(`<table role="presentation" width="${CONTAINER}" cellpadding="0" cellspacing="0" border="0"><tr><td>`)} />
                <div style={{ maxWidth: CONTAINER, margin: '0 auto', textAlign: 'left' }}>
                  <Header />
                  <table role="presentation" width="100%" cellPadding={0} cellSpacing={0} border={0} className="hl-card" bgcolor={ui.light['surface-raised']}
                    style={{ backgroundColor: ui.light['surface-raised'], border: `${ui.border.width}px solid ${ui.light.border}`, borderRadius: ui.radius.lg }}>
                    <tbody>
                      <tr>
                        <td className="hl-card-pad" style={{ padding: `${ui.space[6]}px ${ui.space[6]}px ${ui.space[2]}px ${ui.space[6]}px` }}>{children}</td>
                      </tr>
                    </tbody>
                  </table>
                  {footer}
                </div>
                <Raw html={mso('</td></tr></table>')} />
              </td>
            </tr>
          </tbody>
        </table>
      </Body>
    </Html>
  );
}

/**
 * Transactional mails (sign-in, confirmation, password, account deletion, service notices): no
 * preheader, the TransactionalFooter with the one line saying why the reader gets it.
 */
export function AuthLayout({ lang, title, reason, children }: { lang: Lang; title: string; reason: Reason; children: ReactNode }): ReactElement {
  return <Shell lang={lang} title={title} footer={<TransactionalFooter lang={lang} reason={reason} />}>{children}</Shell>;
}

/**
 * Onboarding and tips mails: a preheader and the OnboardingFooter with the reader's one-click
 * unsubscribe link; `footerNote` goes above it (e.g. where feedback goes).
 */
export function OnboardingLayout({ lang, title, preview, unsubscribeUrl, footerNote, children }: {
  lang: Lang; title: string; preview: string; unsubscribeUrl: UnsubscribeUrl; footerNote?: ReactNode; children: ReactNode;
}): ReactElement {
  return (
    <Shell lang={lang} title={title} preview={preview} footer={<OnboardingFooter lang={lang} unsubscribeUrl={unsubscribeUrl} note={footerNote} />}>
      {children}
    </Shell>
  );
}
