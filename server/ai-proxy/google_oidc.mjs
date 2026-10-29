import { createPublicKey, verify as verifySignature } from 'node:crypto';

const ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);
const JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const MAX_TOKEN_LENGTH = 8192;

// Signature validation uses Google's published RSA keys, never client-supplied URLs.
export function createGoogleOidcVerifier({
  audience,
  fetchKeys = fetch,
  now = () => Math.floor(Date.now() / 1000),
} = {}) {
  if (typeof audience !== 'string' || !/^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$/.test(audience)) {
    throw new TypeError('Google OAuth web client ID required');
  }
  let cachedKeys = null;
  let validUntil = 0;
  async function keys() {
    if (cachedKeys && now() < validUntil) return cachedKeys;
    const response = await fetchKeys(JWKS_URL, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new Error('google_keys_unavailable');
    const body = await response.json();
    if (!Array.isArray(body.keys)) throw new Error('google_keys_invalid');
    const cacheControl = response.headers.get('cache-control') || '';
    const maxAge = Number(/(?:^|,)\s*max-age=(\d+)/i.exec(cacheControl)?.[1] || 300);
    cachedKeys = body.keys.filter(k => k.kty === 'RSA' && k.use === 'sig' && k.alg === 'RS256');
    validUntil = now() + Math.min(Math.max(maxAge, 60), 3600);
    return cachedKeys;
  }
  return async function verifyGoogleIdToken(token) {
    if (typeof token !== 'string' || token.length > MAX_TOKEN_LENGTH) throw new Error('invalid_google_token');
    const parts = token.split('.');
    if (parts.length !== 3 || parts.some(p => !/^[A-Za-z0-9_-]+$/.test(p))) throw new Error('invalid_google_token');
    let header, claims;
    try {
      header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
      claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    } catch { throw new Error('invalid_google_token'); }
    if (header?.alg !== 'RS256' || typeof header.kid !== 'string' || !ISSUERS.has(claims?.iss) ||
        claims.aud !== audience || typeof claims.sub !== 'string' ||
        !/^[0-9]{1,128}$/.test(claims.sub) ||
        !Number.isInteger(claims.exp) || claims.exp <= now() ||
        !Number.isInteger(claims.iat) || claims.iat > now() + 60 ||
        claims.iat > claims.exp) throw new Error('invalid_google_token');
    const key = (await keys()).find(k => k.kid === header.kid);
    if (!key) throw new Error('invalid_google_token');
    let valid = false;
    try {
      valid = verifySignature('RSA-SHA256', Buffer.from(parts[0] + '.' + parts[1]),
        createPublicKey({ key, format: 'jwk' }), Buffer.from(parts[2], 'base64url'));
    } catch { throw new Error('invalid_google_token'); }
    if (!valid) throw new Error('invalid_google_token');
    return { sub: claims.sub };
  };
}
