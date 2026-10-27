import http from 'node:http';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { createRequestHandler, createAllowedUserValidator } from './core.mjs';

const projectId = process.env.FIREBASE_PROJECT_ID;
const apiKey = process.env.TOKENROUTER_API_KEY;
if (!projectId || !apiKey) {
  throw new Error('FIREBASE_PROJECT_ID and TOKENROUTER_API_KEY are required');
}

const allowUser = createAllowedUserValidator(process.env.AI_ALLOWED_UIDS);
initializeApp({ credential: applicationDefault(), projectId });
const verifyToken = async token => allowUser(await getAuth().verifyIdToken(token, true));

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

const handler = createRequestHandler({ authenticate: verifyToken, complete });
const port = Number(process.env.PORT || 8096);
const host = process.env.HOST || '127.0.0.1';
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
http.createServer(handler).listen(port, host, () => {
  process.stdout.write('Masari AI proxy listening on ' + host + ':' + port + '\n');
});
