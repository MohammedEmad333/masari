import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { createGoogleOidcVerifier } from './google_oidc.mjs';

const audience = '657266784006-ai622s0cibo6t9kpld590pruvgccib48.apps.googleusercontent.com';
const now = 1800000000;
const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'test-key', alg: 'RS256', use: 'sig' };
const fetchKeys = async () => ({ ok: true, json: async () => ({ keys: [jwk] }), headers: { get: () => 'max-age=300' } });
const verifier = createGoogleOidcVerifier({ audience, fetchKeys, now: () => now });
function token(claims = {}, header = {}) {
  const h = Buffer.from(JSON.stringify({ alg: 'RS256', kid: 'test-key', ...header })).toString('base64url');
  const p = Buffer.from(JSON.stringify({ iss: 'https://accounts.google.com', aud: audience, sub: '123456789', iat: now - 10, exp: now + 100, ...claims })).toString('base64url');
  return h + '.' + p + '.' + sign('RSA-SHA256', Buffer.from(h + '.' + p), privateKey).toString('base64url');
}
test('valid signed Google OIDC ID token returns immutable subject', async () => {
  assert.deepEqual(await verifier(token()), { sub: '123456789' });
});
for (const [name, claims] of [
  ['wrong audience', { aud: 'attacker.apps.googleusercontent.com' }],
  ['wrong issuer', { iss: 'https://attacker.example' }],
  ['expired', { exp: now - 1 }],
  ['future issued', { iat: now + 120 }],
  ['missing subject', { sub: '' }],
]) {
  test('rejects ' + name, async () => {
    await assert.rejects(verifier(token(claims)), /invalid_google_token/);
  });
}
test('rejects modified signature', async () => {
  const signed = token();
  const parts = signed.split('.');
  parts[1] = Buffer.from(JSON.stringify({ iss: 'https://accounts.google.com', aud: audience, sub: '987', iat: now - 10, exp: now + 100 })).toString('base64url');
  await assert.rejects(verifier(parts.join('.')), /invalid_google_token/);
});
test('rejects unsigned alg none', async () => {
  await assert.rejects(verifier(token({}, { alg: 'none' })), /invalid_google_token/);
});
