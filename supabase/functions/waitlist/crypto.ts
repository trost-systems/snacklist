// Hashes for the waitlist: the address's proof value, the confirm token, the unsubscribe
// signature. Web Crypto only, so scripts/waitlist/invite.ts imports this file as it is.
const encode = (s: string) => new TextEncoder().encode(s);
const hex = (bytes: ArrayBuffer | Uint8Array) =>
  Array.from(new Uint8Array(bytes), (b) => b.toString(16).padStart(2, '0')).join('');

export async function sha256Hex(data: string): Promise<string> {
  return hex(await crypto.subtle.digest('SHA-256', encode(data)));
}

export async function hmacHex(key: string, data: string): Promise<string> {
  const k = await crypto.subtle.importKey(
    'raw',
    encode(key),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return hex(await crypto.subtle.sign('HMAC', k, encode(data)));
}

/** Constant-time comparison: hashed first, so neither content nor length leaks. */
export async function sameSecret(a: string, b: string): Promise<boolean> {
  const [x, y] = await Promise.all([a, b].map(async (s) => encode(await sha256Hex(s))));
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

/** The proof record's value for an address: no one can read the address back from it. */
export const emailHmac = (secret: string, email: string) => hmacHex(secret, email.toLowerCase());

/** The signature in every unsubscribe link; it never expires, so old mails keep working. */
export const unsubscribeSig = (secret: string, id: string) => hmacHex(secret, `unsubscribe:${id}`);

/** 32 random bytes, base64url without padding: 43 characters. */
export function confirmToken(random: Uint8Array): string {
  return btoa(String.fromCharCode(...random)).replaceAll('+', '-').replaceAll('/', '_')
    .replace(/=+$/, '');
}
