// Tests only: a throwaway CA standing in for Amazon's, made fresh in memory for every run (no key
// is ever written down). It issues a signing certificate like echo-api.amazon.com's and signs
// request bodies like Alexa does (RSA SHA-256, base64, header Signature-256).
import * as x509 from '@peculiar/x509';

x509.cryptoProvider.set(crypto);

const rsa = {
  name: 'RSASSA-PKCS1-v1_5',
  hash: 'SHA-256',
  publicExponent: new Uint8Array([1, 0, 1]),
  modulusLength: 2048,
};

const day = 86_400_000;

export interface TestCa {
  root: x509.X509Certificate;
  /** Leaf, intermediate and root, as Amazon publishes them. */
  chainPem: string;
  sign(body: string): Promise<string>;
}

export interface LeafOptions {
  host?: string;
  notBefore?: Date;
  notAfter?: Date;
  /** The intermediate is not a CA (basicConstraints false). */
  intermediateNotCa?: boolean;
  /** When the intermediate expires (30 days by default). */
  intermediateNotAfter?: Date;
}

const keys = () => crypto.subtle.generateKey(rsa, true, ['sign', 'verify']);

export async function makeTestCa(options: LeafOptions = {}): Promise<TestCa> {
  const now = Date.now();
  const rootKeys = await keys();
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: '01',
    name: 'CN=Snacklist Test Root',
    notBefore: new Date(now - day),
    notAfter: new Date(now + 30 * day),
    signingAlgorithm: rsa,
    keys: rootKeys,
    extensions: [new x509.BasicConstraintsExtension(true, 2, true)],
  });
  const midKeys = await keys();
  const intermediate = await x509.X509CertificateGenerator.create({
    serialNumber: '02',
    subject: 'CN=Snacklist Test Intermediate',
    issuer: root.subject,
    notBefore: new Date(now - day),
    notAfter: options.intermediateNotAfter ?? new Date(now + 30 * day),
    signingAlgorithm: rsa,
    publicKey: midKeys.publicKey,
    signingKey: rootKeys.privateKey,
    extensions: [new x509.BasicConstraintsExtension(!options.intermediateNotCa, 0, true)],
  });
  const leafKeys = await keys();
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: '03',
    subject: `CN=${options.host ?? 'echo-api.amazon.com'}`,
    issuer: intermediate.subject,
    notBefore: options.notBefore ?? new Date(now - day),
    notAfter: options.notAfter ?? new Date(now + 7 * day),
    signingAlgorithm: rsa,
    publicKey: leafKeys.publicKey,
    signingKey: midKeys.privateKey,
    extensions: [
      new x509.SubjectAlternativeNameExtension([
        { type: 'dns', value: options.host ?? 'echo-api.amazon.com' },
      ]),
    ],
  });
  return {
    root,
    chainPem: [leaf, intermediate, root].map((c) => c.toString('pem')).join('\n'),
    async sign(body: string) {
      const signature = await crypto.subtle.sign(
        'RSASSA-PKCS1-v1_5',
        leafKeys.privateKey,
        new TextEncoder().encode(body),
      );
      return btoa(String.fromCharCode(...new Uint8Array(signature)));
    },
  };
}

export const testSkillId = 'amzn1.ask.skill.00000000-0000-4000-8000-00000000e2e0';
export const testCertUrl = 'https://s3.amazonaws.com/echo.api/echo-api-cert-test.pem';
