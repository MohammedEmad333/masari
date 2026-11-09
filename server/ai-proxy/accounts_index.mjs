// Standalone Oracle accounts service: NO Firebase SDK, Firestore or App Check.
import http from 'node:http';
import { readFileSync } from 'node:fs';
import pg from 'pg';
import { createGoogleOidcVerifier } from './google_oidc.mjs';
import { createOracleSessions, SESSION_SCHEMA } from './oracle_sessions.mjs';
import { PAIRING_SCHEMA } from './oracle_pairing.mjs';
import { GOOGLE_ACCOUNT_SCHEMA } from './oracle_google_accounts.mjs';
import { createGoogleOidcAccounts, GOOGLE_OIDC_ACCOUNT_SCHEMA } from './oracle_google_oidc_accounts.mjs';
import { createPairingRateLimiter, PAIRING_RATE_SCHEMA } from './oracle_pairing_rate.mjs';
import { createOracleAccountStore, ACCOUNT_DATA_SCHEMA } from './oracle_account_store.mjs';
import { createOracleAccountHandler } from './oracle_account_api.mjs';

const passwordFile = process.env.MASARI_POSTGRES_PASSWORD_FILE;
const connectionString = process.env.MASARI_POSTGRES_URL;
if (!passwordFile && !connectionString) throw new Error('PostgreSQL credentials required');
const options = passwordFile ? {
  host: process.env.MASARI_POSTGRES_HOST || 'masari-ai-postgres',
  port: 5432,
  user: 'masari_ai',
  database: 'masari_ai',
  password: readFileSync(passwordFile, 'utf8').trim(),
} : { connectionString };
const pool = new pg.Pool({ ...options, max: 5, connectionTimeoutMillis: 5000 });
const audience = process.env.MASARI_GOOGLE_OAUTH_CLIENT_ID;
const verifyGoogle = createGoogleOidcVerifier({ audience });
try {
  await pool.query(SESSION_SCHEMA);
  await pool.query(PAIRING_SCHEMA);
  await pool.query(GOOGLE_ACCOUNT_SCHEMA);
  await pool.query(GOOGLE_OIDC_ACCOUNT_SCHEMA);
  await pool.query(PAIRING_RATE_SCHEMA);
  await pool.query(ACCOUNT_DATA_SCHEMA);
} catch (error) {
  await pool.end();
  throw error;
}
const sessions = createOracleSessions({ pool });
const exchangeGoogleOidc = createGoogleOidcAccounts({
  pool,
  issueSession: sessions.issueSession,
});
const exchangeGoogle = (sub, { allowEnrollment = false } = {}) =>
  exchangeGoogleOidc(sub, { createIfMissing: allowEnrollment });
const reserveGlobal = createPairingRateLimiter({
  pool, maxAttempts: 100, windowSeconds: 60,
});
const reserveIdentity = createPairingRateLimiter({
  pool, maxAttempts: 5, windowSeconds: 60,
});
const handler = createOracleAccountHandler({
  authenticate: sessions.authenticate,
  revokeSession: sessions.revoke,
  verifyGoogle,
  exchangeGoogle,
  reserveGlobal: () => reserveGlobal('masari-accounts-google-global'),
  reserveIdentity: sub => reserveIdentity('masari-accounts-google:' + sub),
  store: createOracleAccountStore({ pool }),
});
const host = process.env.HOST || '127.0.0.1';
const port = Number(process.env.PORT || 8098);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
http.createServer((req, res) => {
  Promise.resolve(handler(req, res)).catch(() => {
    if (!res.headersSent) {
      res.writeHead(503, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ error: 'service_unavailable' }));
    } else {
      res.destroy();
    }
  });
}).listen(port, host, () => {
  process.stdout.write('Masari Oracle accounts listening on ' + host + ':' + port + '\n');
});
