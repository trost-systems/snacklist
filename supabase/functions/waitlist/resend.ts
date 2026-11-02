// Single sends through Resend's API (POST /emails): no batch, audiences, tags or metadata. An
// error says only the HTTP status, never the answer, which may echo the address.
import type { Mail } from './mail.ts';

export interface Mailer {
  /** Sends [mail] to [to]; Resend sends a repeated [idempotencyKey] only once (24 h). */
  send(to: string, mail: Mail, idempotencyKey: string): Promise<void>;
}

export class MailError extends Error {
  constructor(readonly status: number) {
    super(`resend answered ${status}`);
    this.name = 'MailError';
  }
}

export const RESEND_API_URL = 'https://api.resend.com';

export function resendMailer(
  apiKey: string,
  apiUrl: string = RESEND_API_URL,
  fetchFn: typeof fetch = fetch,
): Mailer {
  return {
    async send(to, mail, idempotencyKey) {
      const res = await fetchFn(`${apiUrl.replace(/\/+$/, '')}/emails`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${apiKey}`,
          'content-type': 'application/json',
          'idempotency-key': idempotencyKey,
        },
        body: JSON.stringify({
          from: mail.from,
          to: [to],
          reply_to: mail.replyTo,
          subject: mail.subject,
          html: mail.html,
          text: mail.text,
          ...(Object.keys(mail.headers).length ? { headers: mail.headers } : {}),
        }),
      });
      await res.body?.cancel();
      if (!res.ok) throw new MailError(res.status);
    },
  };
}
