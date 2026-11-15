// Stores a feedback screenshot for the signed-in user (docs/FEEDBACK.md, "Screenshots"). Clients
// have no Storage policy on the bucket: this is the only way in. In one transaction of the service
// connection, public.feedback_screenshot_admit takes the bucket's lock and checks the quotas; the
// Storage API stores the image with the secret key while the lock is held; then the transaction
// commits. So parallel uploads run one after the other and see each other's objects.
import type { Sql } from '../_shared/db.ts';
import { BUCKET, pgCode } from '../_shared/feedback_screenshots.ts';

/** The bucket's own limit (20261115160000_feedback_screenshots.sql). */
export const MAX_BYTES = 2 * 1024 * 1024;

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

const LOWERCASE_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** How long the Storage API may take to store one image while the lock is held. */
export const PUT_MS = 10_000;

/** How long an upload waits for the lock: a little over one other upload's worst case. */
const LOCK_WAIT = '12s';

/** Request bytes, owning their buffer (fetch takes no shared one). */
export type Bytes = Uint8Array<ArrayBuffer>;

export type Stored = 'stored' | 'exists' | 'quota';

export type UploadFailure = 'db_error' | 'storage_failed';

export class UploadError extends Error {
  constructor(readonly code: UploadFailure, readonly detail: string) {
    super(`feedback-screenshots: upload ${code} ${detail}`);
  }
}

/** Stores `png` as `<userId>/<id>.png` unless a quota says no; throws UploadError. */
export type StoreScreenshot = (userId: string, id: string, png: Bytes) => Promise<Stored>;

/** Puts one object; 'exists' for the Storage API's Duplicate. Throws UploadError. */
export type PutObject = (name: string, png: Bytes) => Promise<'stored' | 'exists'>;

export function isNoteId(id: string): boolean {
  return LOWERCASE_UUID.test(id);
}

export function isPng(bytes: Uint8Array): boolean {
  return PNG_SIGNATURE.every((b, i) => bytes[i] === b);
}

/**
 * The request body, read up to MAX_BYTES: 'too_large' as soon as more arrives (the rest is
 * cancelled, not read).
 */
export async function readCapped(req: Request): Promise<Bytes | 'too_large'> {
  const declared = Number(req.headers.get('content-length') ?? '0');
  if (declared > MAX_BYTES) {
    await req.body?.cancel();
    return 'too_large';
  }
  if (!req.body) return new Uint8Array();
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BYTES) {
      await reader.cancel();
      return 'too_large';
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let at = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, at);
    at += chunk.byteLength;
  }
  return bytes;
}

export function sqlScreenshotStore(db: () => Sql, put: PutObject): StoreScreenshot {
  return async (userId, id, png) => {
    try {
      return await db().begin(async (tx): Promise<Stored> => {
        await tx`select set_config('lock_timeout', ${LOCK_WAIT}, true)`;
        const [row] = await tx<{ verdict: 'new' | 'exists' | 'quota' }[]>`
          select public.feedback_screenshot_admit(${userId}::uuid, ${id}::uuid) as verdict`;
        if (row === undefined) throw new UploadError('db_error', 'no_row');
        if (row.verdict !== 'new') return row.verdict;
        return await put(`${userId}/${id}.png`, png);
      });
    } catch (e) {
      if (e instanceof UploadError) throw e;
      throw new UploadError('db_error', pgCode(e));
    }
  };
}

/** Puts through the Storage API with the project's secret key, never overwriting. */
export function storagePutter(
  supabaseUrl: string,
  secretKey: string,
  doFetch: typeof fetch = fetch,
): PutObject {
  return async (name, png) => {
    let res: Response;
    try {
      res = await doFetch(`${supabaseUrl}/storage/v1/object/${BUCKET}/${name}`, {
        method: 'POST',
        headers: {
          apikey: secretKey,
          authorization: `Bearer ${secretKey}`,
          'content-type': 'image/png',
          'x-upsert': 'false',
        },
        body: png,
        signal: AbortSignal.timeout(PUT_MS),
      });
    } catch {
      throw new UploadError('storage_failed', 'fetch');
    }
    const body: unknown = await res.json().catch(() => null);
    if (res.ok) return 'stored';
    // The Storage API answers a duplicate as HTTP 409 or as 400 with statusCode "409" in the body.
    const { statusCode } = (body ?? {}) as { statusCode?: unknown };
    if (res.status === 409 || statusCode === '409') return 'exists';
    throw new UploadError('storage_failed', String(res.status));
  };
}
