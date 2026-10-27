import http from 'node:http';
import { readFileSync } from 'node:fs';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { createFirestoreQuota } from './firestore_quota.mjs';
import { createRequestHandler } from './core.mjs';

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
const reserveQuota = createFirestoreQuota({ db: getFirestore() });
const handler = createRequestHandler({ authenticate: verifyToken, complete, reserveQuota });
const port = Number(process.env.PORT || 8096);
const host = process.env.HOST || '127.0.0.1';
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
http.createServer(handler).listen(port, host, () => {
  process.stdout.write('Masari AI proxy listening on ' + host + ':' + port + '\n');
});
