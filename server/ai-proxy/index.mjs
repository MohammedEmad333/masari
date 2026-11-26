import http from 'node:http';
import { readFileSync } from 'node:fs';
import pg from 'pg';
import { createPostgresQuota, QUOTA_SCHEMA } from './postgres_quota.mjs';
import { createRequestHandler } from './core.mjs';
import { createOracleSessions, SESSION_SCHEMA } from './oracle_sessions.mjs';
import { createOraclePairing, PAIRING_SCHEMA } from './oracle_pairing.mjs';
import { createPairingRateLimiter, PAIRING_RATE_SCHEMA } from './oracle_pairing_rate.mjs';
import { createPairingHandler } from './oracle_pairing_http.mjs';

const apiKeyFile = process.env.TOKENROUTER_API_KEY_FILE;
const apiKey = apiKeyFile
  ? readFileSync(apiKeyFile, 'utf8').trim()
  : process.env.TOKENROUTER_API_KEY;
if (!apiKey || apiKey.length < 10) {
  throw new Error('A TokenRouter API key is required');
}

const passwordFile = process.env.MASARI_POSTGRES_PASSWORD_FILE;
const connectionString = process.env.MASARI_POSTGRES_URL;
if (!passwordFile && !connectionString) {
  throw new Error('PostgreSQL credentials are required');
}
const pgOptions = passwordFile ? {
  host: process.env.MASARI_POSTGRES_HOST || 'masari-ai-postgres',
  port: 5432,
  user: 'masari_ai',
  database: 'masari_ai',
  password: readFileSync(passwordFile, 'utf8').trim(),
} : { connectionString };
const pool = new pg.Pool({ ...pgOptions, max: 4, connectionTimeoutMillis: 5000 });

await pool.query(SESSION_SCHEMA);
await pool.query(PAIRING_SCHEMA);
await pool.query(PAIRING_RATE_SCHEMA);
await pool.query(QUOTA_SCHEMA);

const sessions = createOracleSessions({ pool });
const reserveQuota = createPostgresQuota({ pool, perDay: 20 });
const reservePairingIdentity = createPairingRateLimiter({
  pool,
  maxAttempts: 5,
  windowSeconds: 60,
});
const pairing = createOraclePairing({ pool });
const pairingHandler = createPairingHandler({
  enabled: true,
  redeemCode: pairing.redeemCode,
  reserveAttempt: identity => reservePairingIdentity('masari-ai-pairing:' + identity),
});

const authenticate = async token => {
  if (typeof token !== 'string' || !/^msr_[0-9a-f]{64}$/.test(token)) {
    throw new Error('Oracle session required');
  }
  const session = await sessions.authenticate(token);
  if (!session) throw new Error('Invalid Oracle session');
  return { uid: 'oracle:' + session.uid, authMethod: 'oracle' };
};

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

const handler = createRequestHandler({
  authenticate,
  complete,
  reserveQuota,
});
const port = Number(process.env.PORT || 8096);
const host = process.env.HOST || '127.0.0.1';
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('Invalid PORT');
}
const server = http.createServer(async (req, res) => {
  if (await pairingHandler(req, res)) return;
  await handler(req, res);
});
server.listen(port, host, () => {
  process.stdout.write('Masari Oracle-only AI proxy listening on ' + host + ':' + port + '\n');
});

async function shutdown() {
  server.close();
  await pool.end();
}
process.once('SIGTERM', () => { void shutdown(); });
process.once('SIGINT', () => { void shutdown(); });
