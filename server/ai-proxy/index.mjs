import http from 'node:http';
import { readFileSync } from 'node:fs';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getAppCheck } from 'firebase-admin/app-check';
import { getFirestore } from 'firebase-admin/firestore';
import { createFirestoreQuota } from './firestore_quota.mjs';
import { createPostgresQuota, QUOTA_SCHEMA } from './postgres_quota.mjs';
import pg from 'pg';
import { createRequestHandler } from './core.mjs';
import { createOracleSessions, SESSION_SCHEMA } from './oracle_sessions.mjs';
import { createOraclePairing, PAIRING_SCHEMA } from './oracle_pairing.mjs';
import { createPairingRateLimiter, PAIRING_RATE_SCHEMA } from './oracle_pairing_rate.mjs';
import { createPairingHandler } from './oracle_pairing_http.mjs';
import { createGoogleAccounts, GOOGLE_IDENTITY_SCHEMA } from './oracle_google_accounts.mjs';
import { createGoogleSessionHandler } from './oracle_google_http.mjs';

const projectId = process.env.FIREBASE_PROJECT_ID;
const apiKeyFile = process.env.TOKENROUTER_API_KEY_FILE;
const apiKey = apiKeyFile
  ? readFileSync(apiKeyFile, 'utf8').trim()
  : process.env.TOKENROUTER_API_KEY;
if (!projectId || !apiKey || apiKey.length < 10) {
  throw new Error('FIREBASE_PROJECT_ID and a TokenRouter API key are required');
}

initializeApp({ credential: applicationDefault(), projectId });
const verifyToken = async token => getAuth().verifyIdToken(token, true);
const verifyAppCheck = async token => getAppCheck().verifyToken(token);

const complete = async ({ message, language }) => {
  const response = await fetch('https://api.tokenrouter.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + apiKey,
      'Content-Type': 'application/json',
    },
    signal: AbortSignal.timeout(25000),
    body: JSON.stringify({
      model: 'openai/gpt-oss-120b',
      max_tokens: 768,
      stream: false,
      messages: [
        {
          role: 'system',
          content: language === 'ar'
            ? 'أنت مساعد دراسي. أجب بالعربية بإيجاز. لا تدّعِ وصولك إلى تقويم أو مهام المستخدم. لا تزعم تنفيذ تنبيه أو تعديل.'
            : 'You are a study assistant. Reply concisely in English. Never claim access to the user calendar or tasks, or claim to schedule or edit anything.',
        },
        { role: 'user', content: message },
      ],
    }),
  });
  if (!response.ok) throw new Error('upstream_unavailable');
  const payload = await response.json();
  const answer = payload?.choices?.[0]?.message?.content;
  if (typeof answer !== 'string') throw new Error('invalid_upstream_response');
  return answer;
};

// All verified Firebase users can use the pilot. Durable Firestore caps
// prevent one account or the aggregate app from exhausting requests.
// Provider-side spend limits and App Check are separate launch requirements.
const quotaBackend = process.env.MASARI_QUOTA_BACKEND || 'firestore';
let reserveQuota;
let pool;
if (quotaBackend === 'postgres') {
  const passwordFile = process.env.MASARI_POSTGRES_PASSWORD_FILE;
  const connectionString = process.env.MASARI_POSTGRES_URL;
  if (!connectionString && !passwordFile) {
    throw new Error('PostgreSQL credentials are required');
  }
  const pgOptions = passwordFile ? {
    host: process.env.MASARI_POSTGRES_HOST || 'masari-ai-postgres',
    port: 5432,
    user: 'masari_ai',
    database: 'masari_ai',
    password: readFileSync(passwordFile, 'utf8').trim(),
  } : { connectionString };
  pool = new pg.Pool({ ...pgOptions, max: 4, connectionTimeoutMillis: 5000 });
  // Startup must fail closed when quota schema cannot be used.
  await pool.query(QUOTA_SCHEMA);
  reserveQuota = createPostgresQuota({ pool });
} else if (quotaBackend === 'firestore') {
  reserveQuota = createFirestoreQuota({ db: getFirestore() });
} else {
  throw new Error('Invalid MASARI_QUOTA_BACKEND');
}
// Default-off until pairing/recovery and client secure-storage rollout are ready.
const oracleEnabled = process.env.MASARI_ORACLE_AUTH_ENABLED === 'true';
if (oracleEnabled && !pool) throw new Error('Oracle auth requires PostgreSQL');
let oracleSessions;
let pairingHandler;
let googleSessionHandler;
if (oracleEnabled) {
  await pool.query(SESSION_SCHEMA);
  await pool.query(PAIRING_SCHEMA);
  await pool.query(PAIRING_RATE_SCHEMA);
  oracleSessions = createOracleSessions({ pool });
  if (process.env.MASARI_GOOGLE_ACCOUNT_EXCHANGE_ENABLED === 'true') {
    await pool.query(GOOGLE_IDENTITY_SCHEMA);
    googleSessionHandler = createGoogleSessionHandler({
      verifyIdToken: verifyToken,
      verifyAppCheck,
      findOrCreate: createGoogleAccounts({ pool }),
      issueSession: oracleSessions.issueSession,
    });
  }
  const pairing = createOraclePairing({ pool });
  // This fixed shared bucket limits all requests via the Caddy proxy regardless
  // of untrusted client forwarding headers. Edge-level limits also required.
  const sharedLimit = createPairingRateLimiter({ pool, maxAttempts: 10, windowSeconds: 60 });
  pairingHandler = createPairingHandler({
    enabled: true,
    redeemCode: pairing.redeemCode,
    reserveAttempt: () => sharedLimit('masari-public-pairing'),
  });
}
const authenticate = async token => {
  if (token.startsWith('msr_')) {
    if (!oracleEnabled) throw new Error('Oracle sessions disabled');
    const session = await oracleSessions.authenticate(token);
    if (!session) throw new Error('Invalid Oracle session');
    return { uid: 'oracle:' + session.uid, authMethod: 'oracle' };
  }
  return verifyToken(token);
};
const handler = createRequestHandler({
  authenticate,
  verifyAppCheck,
  complete,
  reserveQuota,
});
const port = Number(process.env.PORT || 8096);
const host = process.env.HOST || '127.0.0.1';
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
http.createServer(async (req, res) => {
  if (googleSessionHandler && await googleSessionHandler(req, res)) return;
  if (pairingHandler && await pairingHandler(req, res)) return;
  await handler(req, res);
}).listen(port, host, () => {
  process.stdout.write('Masari AI proxy listening on ' + host + ':' + port + '\n');
});
