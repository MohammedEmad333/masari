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
import { createGoogleAccounts, GOOGLE_ACCOUNT_SCHEMA } from './oracle_google_accounts.mjs';

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
  reserveQuota = createPostgresQuota({ pool, perDay: 20 });
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
let googleExchange;
let reserveGoogleGlobal;
let reserveGoogleUser;
if (oracleEnabled) {
  await pool.query(SESSION_SCHEMA);
  await pool.query(PAIRING_SCHEMA);
  await pool.query(PAIRING_RATE_SCHEMA);
  oracleSessions = createOracleSessions({ pool });
  await pool.query(GOOGLE_ACCOUNT_SCHEMA);
  googleExchange = createGoogleAccounts({ pool, createAccount: oracleSessions.createAccount, issueSession: oracleSessions.issueSession });
  // Durable limits cover concurrent workers and restart; caller IP headers are
  // intentionally not trusted. Count both accepted and rejected requests.
  const globalGoogleLimit = createPairingRateLimiter({ pool, maxAttempts: 100, windowSeconds: 60 });
  const accountGoogleLimit = createPairingRateLimiter({ pool, maxAttempts: 5, windowSeconds: 60 });
  reserveGoogleGlobal = () => globalGoogleLimit('masari-google-exchange-global');
  reserveGoogleUser = uid => accountGoogleLimit('masari-google-exchange-uid:' + uid);
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
  if (oracleEnabled && req.url === '/v1/auth/google') {
    const reply = (status, body) => {
      res.writeHead(status, {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
      });
      res.end(JSON.stringify(body));
    };
    if (req.method !== 'POST') return reply(405, { error: 'method_not_allowed' });
    try {
      await reserveGoogleGlobal();
    } catch (error) {
      return reply(error?.code === 'pairing_rate_exceeded' ? 429 : 503, {
        error: error?.code === 'pairing_rate_exceeded' ? 'quota_exceeded' : 'quota_service_unavailable',
      });
    }
    if (!String(req.headers['content-type' || '').toLowerCase().startsWith('application/json')) {
      return reply(415, { error: 'content_type' });
    }
    const authorization = req.headers.authorization || '';
    if (!authorization.startsWith('Bearer ') || authorization.length > 4103) {
      return reply(401, { error: 'sign_in_required' });
    }
    const appCheck = req.headers['x-firebase-appcheck'];
    if (typeof appCheck !== 'string' || !appCheck || appCheck.length > 4096) {
      return reply(403, { error: 'app_check_required' });
    }
    try {
      await verifyAppCheck(appCheck);
    } catch {
      return reply(403, { error: 'app_check_failed' });
    }
    let user;
    try {
      user = await verifyToken(authorization.slice(7));
      if (user.firebase?.sign_in_provider !== 'google.com') {
        return reply(403, { error: 'google_required' });
      }
    } catch {
      return reply(401, { error: 'invalid_authentication' });
    }
    try {
      await reserveGoogleUser(user.uid);
    } catch (error) {
      return reply(error?.code === 'pairing_rate_exceeded' ? 429 : 503, {
        error: error?.code === 'pairing_rate_exceeded' ? 'quota_exceeded' : 'quota_service_unavailable',
      });
    }
    // A bounded, empty JSON object prevents accidental token or profile
    // submission; no identity is trusted from the request body.
    let bytes = 0;
    const chunks = [];
    try {
      for await (const chunk of req) {
        bytes += chunk.length;
        if (bytes > 32) return reply(413, { error: 'request_too_large' });
        chunks.push(chunk);
      }
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (!body || Array.isArray(body) || Object.keys(body).length !== 0) {
        return reply(400, { error: 'invalid_body' });
      }
    } catch {
      return reply(400, { error: 'invalid_body' });
    }
    try {
      const session = await googleExchange(user);
      return reply(200, session);
    } catch {
      return reply(503, { error: 'account_unavailable' });
    }
  }
  if (pairingHandler && await pairingHandler(req, res)) return;
  await handler(req, res);
}).listen(port, host, () => {
  process.stdout.write('Masari AI proxy listening on ' + host + ':' + port + '\n');
});
