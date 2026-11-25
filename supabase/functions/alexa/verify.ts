// Checks that a request really comes from Alexa for our skill, as Amazon requires of a skill
// hosted outside AWS Lambda (docs/ALEXA.md, "Request verification"):
//   1. SignatureCertChainUrl: https, host s3.amazonaws.com, path under /echo.api/, port 443;
//   2. the certificate chain at that URL: the leaf is valid now, names echo-api.amazon.com, and
//      chains to a pinned root (anchors.ts) through certificates that are valid now;
//   3. Signature-256: the leaf's RSA SHA-256 signature over the raw body;
//   4. request.timestamp at most 150 s away from now (an hour for skill events, see below);
//   5. the applicationId is our skill's.
// A failure answers 400 before anything is read from or written to the database.
import * as x509 from '@peculiar/x509';

x509.cryptoProvider.set(crypto);

export type Rejection =
  | 'missing_signature'
  | 'bad_cert_url'
  | 'cert_unavailable'
  | 'cert_expired'
  | 'cert_wrong_host'
  | 'cert_untrusted'
  | 'bad_signature'
  | 'bad_body'
  | 'stale_timestamp'
  | 'wrong_skill';

export class VerificationError extends Error {
  constructor(readonly reason: Rejection) {
    super(`alexa request refused: ${reason}`);
  }
}

export interface VerifyDeps {
  /** Roots a chain must end in. */
  anchors: readonly x509.X509Certificate[];
  /** The PEM chain behind a SignatureCertChainUrl that passed the URL rules. */
  fetchChain(url: URL): Promise<string>;
  /** Our skill ids; empty refuses every request. */
  skillIds: readonly string[];
  now(): Date;
}

/** The certificate Alexa signs with names this host (SAN). */
export const signerHost = 'echo-api.amazon.com';

/** Amazon: a request's timestamp may be at most 150 s off. */
export const maxSkewMs = 150_000;

/**
 * Skill events (AlexaSkillEvent.*) are delivered asynchronously and may be retried; the ASK SDK's
 * verifier allows them an hour.
 */
export const maxEventSkewMs = 3_600_000;

/** The Alexa request envelope, as far as this function reads it. */
export interface Envelope {
  version: string;
  session?: {
    new?: boolean;
    sessionId?: string;
    application?: { applicationId?: string };
    attributes?: Record<string, unknown>;
    user?: { userId?: string; accessToken?: string };
  };
  context?: {
    System?: {
      application?: { applicationId?: string };
      user?: { userId?: string; accessToken?: string };
    };
  };
  request: {
    type: string;
    requestId?: string;
    timestamp: string;
    locale?: string;
    intent?: {
      name: string;
      confirmationStatus?: string;
      slots?: Record<string, { name: string; value?: string }>;
    };
    dialogState?: string;
    reason?: string;
    /** SessionEndedRequest with reason ERROR: why Alexa gave up on the skill's answer. */
    error?: { type?: string; message?: string };
    body?: Record<string, unknown>;
  };
}

/** Rule 1. Normalized by URL first, so "/echo.api/../echo.api/x.pem" passes and "/x/../y" not. */
export function certUrlAllowed(raw: string): URL | null {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  const ok = url.protocol === 'https:' &&
    url.hostname === 's3.amazonaws.com' &&
    (url.port === '' || url.port === '443') &&
    url.username === '' && url.password === '' &&
    url.pathname.startsWith('/echo.api/');
  return ok ? url : null;
}

const validAt = (cert: x509.X509Certificate, at: Date) =>
  cert.notBefore.getTime() <= at.getTime() && at.getTime() <= cert.notAfter.getTime();

const signedBy = (cert: x509.X509Certificate, issuer: x509.X509Certificate) =>
  cert.issuer === issuer.subject &&
  cert.verify({ publicKey: issuer.publicKey, signatureOnly: true }).catch(() => false);

const isCa = (cert: x509.X509Certificate) =>
  cert.getExtension(x509.BasicConstraintsExtension)?.ca === true;

/** A chain that passed rule 2: its leaf and when every certificate the check needed is valid. */
interface Passed {
  leaf: x509.X509Certificate;
  /** The latest notBefore and the earliest notAfter of the leaf and the CAs walked through. */
  from: number;
  until: number;
}

/** Rule 2. Returns the leaf (the signer) of a chain that passes. */
export async function checkChain(
  pem: string,
  anchors: readonly x509.X509Certificate[],
  at: Date,
): Promise<x509.X509Certificate> {
  return (await walkChain(pem, anchors, at)).leaf;
}

async function walkChain(
  pem: string,
  anchors: readonly x509.X509Certificate[],
  at: Date,
): Promise<Passed> {
  let chain: x509.X509Certificate[];
  try {
    chain = x509.PemConverter.decode(pem).map((der) => new x509.X509Certificate(der));
  } catch {
    throw new VerificationError('cert_unavailable');
  }
  const leaf = chain[0];
  if (!leaf) throw new VerificationError('cert_unavailable');
  if (!validAt(leaf, at)) throw new VerificationError('cert_expired');
  const names = leaf.getExtension(x509.SubjectAlternativeNameExtension)?.names.items ?? [];
  if (!names.some((n) => n.type === 'dns' && n.value.toLowerCase() === signerHost)) {
    throw new VerificationError('cert_wrong_host');
  }
  let from = leaf.notBefore.getTime();
  let until = leaf.notAfter.getTime();
  // Walk up: each certificate is signed by a pinned root, or by the next one in the chain,
  // which must be a CA valid now. The chain may go on past a pinned root (a cross-signature).
  for (let i = 0; i < chain.length && i < 6; i++) {
    const cert = chain[i];
    for (const anchor of anchors) {
      if (await signedBy(cert, anchor)) return { leaf, from, until };
    }
    const next = chain[i + 1];
    if (!next || !isCa(next) || !validAt(next, at) || !await signedBy(cert, next)) break;
    from = Math.max(from, next.notBefore.getTime());
    until = Math.min(until, next.notAfter.getTime());
  }
  throw new VerificationError('cert_untrusted');
}

interface Signer {
  key: CryptoKey;
  from: number;
  until: number;
}

/** Real chains are a handful; the cap bounds what one worker keeps. */
const MAX_PASSED_CHAINS = 16;

/** Chains that passed rule 2, per set of anchors, by their PEM text. */
const passed = new WeakMap<readonly x509.X509Certificate[], Map<string, Signer>>();

/**
 * Rule 2 and the key for rule 3. A chain that passed against these anchors is not parsed and
 * walked again while every certificate the walk needed is still valid: the outcome depends only on
 * the PEM text, the anchors and the time. Outside that window it is checked from scratch, so an
 * expired leaf or intermediate is refused as before. Only passes are kept.
 */
async function signerKey(
  pem: string,
  anchors: readonly x509.X509Certificate[],
  at: Date,
): Promise<CryptoKey> {
  let kept = passed.get(anchors);
  const hit = kept?.get(pem);
  if (hit && hit.from <= at.getTime() && at.getTime() <= hit.until) return hit.key;
  const { leaf, from, until } = await walkChain(pem, anchors, at);
  const key = await publicKeyOf(leaf);
  if (!key) throw new VerificationError('bad_signature');
  if (!kept) passed.set(anchors, kept = new Map());
  kept.delete(pem);
  if (kept.size >= MAX_PASSED_CHAINS) {
    const oldest = kept.keys().next().value;
    if (oldest !== undefined) kept.delete(oldest);
  }
  kept.set(pem, { key, from, until });
  return key;
}

function base64Bytes(text: string): Uint8Array<ArrayBuffer> | null {
  try {
    return Uint8Array.from(atob(text.trim()), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}

const publicKeyOf = (leaf: x509.X509Certificate): Promise<CryptoKey | null> =>
  leaf.publicKey.export({ name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, ['verify'])
    .catch(() => null);

/** Rule 3. */
export async function signatureMatches(
  leaf: x509.X509Certificate,
  signature: string,
  body: Uint8Array<ArrayBuffer>,
): Promise<boolean> {
  const key = await publicKeyOf(leaf);
  return key !== null && await signedWith(key, signature, body);
}

async function signedWith(
  key: CryptoKey,
  signature: string,
  body: Uint8Array<ArrayBuffer>,
): Promise<boolean> {
  const bytes = base64Bytes(signature);
  if (!bytes || bytes.length === 0) return false;
  try {
    return await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, bytes, body);
  } catch {
    return false;
  }
}

/** The skill id a request is for (context first; older requests only had it in the session). */
export const applicationIdOf = (envelope: Envelope) =>
  envelope.context?.System?.application?.applicationId ??
    envelope.session?.application?.applicationId;

/** Rules 4 and 5, on the parsed body. */
export function checkEnvelope(envelope: Envelope, deps: Pick<VerifyDeps, 'skillIds' | 'now'>) {
  const at = Date.parse(envelope.request.timestamp);
  const skew = envelope.request.type.startsWith('AlexaSkillEvent.') ? maxEventSkewMs : maxSkewMs;
  if (!Number.isFinite(at) || Math.abs(deps.now().getTime() - at) > skew) {
    throw new VerificationError('stale_timestamp');
  }
  const id = applicationIdOf(envelope);
  if (!id || !deps.skillIds.includes(id)) throw new VerificationError('wrong_skill');
}

function parseEnvelope(body: Uint8Array<ArrayBuffer>): Envelope {
  try {
    const parsed = JSON.parse(new TextDecoder().decode(body)) as Envelope;
    if (
      typeof parsed?.request?.type !== 'string' || typeof parsed.request.timestamp !== 'string'
    ) {
      throw new Error('not an Alexa request');
    }
    return parsed;
  } catch {
    throw new VerificationError('bad_body');
  }
}

/** All five rules on a request; returns the parsed envelope or throws a VerificationError. */
export async function verifyRequest(
  headers: Headers,
  body: Uint8Array<ArrayBuffer>,
  deps: VerifyDeps,
): Promise<Envelope> {
  const certUrl = headers.get('signaturecertchainurl');
  const signature = headers.get('signature-256');
  if (!certUrl || !signature) throw new VerificationError('missing_signature');
  const url = certUrlAllowed(certUrl);
  if (!url) throw new VerificationError('bad_cert_url');
  let pem: string;
  try {
    pem = await deps.fetchChain(url);
  } catch {
    throw new VerificationError('cert_unavailable');
  }
  const key = await signerKey(pem, deps.anchors, deps.now());
  if (!await signedWith(key, signature, body)) {
    throw new VerificationError('bad_signature');
  }
  const envelope = parseEnvelope(body);
  checkEnvelope(envelope, deps);
  return envelope;
}

/** Real chains are a handful; the cap bounds what paths under /echo.api/ can make the worker keep. */
const MAX_CACHED_CHAINS = 16;

/**
 * Fetches a chain over https, at most 64 KiB, within 3 s, and keeps it for this worker's life
 * (Amazon rotates the URL, not the content behind it). A failed fetch is not kept. A chain is the
 * object at host and path: the caller chooses the URL before any signature is checked, so a query
 * string neither reaches S3 nor makes a second entry, and only a fetched chain takes a place: the
 * oldest goes when there are 16.
 */
export function cachingFetcher(fetchImpl: typeof fetch = fetch): (url: URL) => Promise<string> {
  const kept = new Map<string, string>();
  const fetching = new Map<string, Promise<string>>();
  return (url) => {
    const key = url.origin + url.pathname;
    const chain = kept.get(key);
    if (chain !== undefined) return Promise.resolve(chain);
    let pending = fetching.get(key);
    if (!pending) {
      pending = (async () => {
        const res = await fetchImpl(key, { signal: AbortSignal.timeout(3_000) });
        if (!res.ok) throw new Error(`certificate chain: ${res.status}`);
        const text = await res.text();
        if (text.length > 65_536) throw new Error('certificate chain too large');
        if (kept.size >= MAX_CACHED_CHAINS) {
          const oldest = kept.keys().next().value;
          if (oldest !== undefined) kept.delete(oldest);
        }
        kept.set(key, text);
        return text;
      })();
      fetching.set(key, pending);
      const done = () => fetching.delete(key);
      pending.then(done, done);
    }
    return pending;
  };
}

export const parseCertificates = (pem: string) =>
  x509.PemConverter.decode(pem).map((der) => new x509.X509Certificate(der));
