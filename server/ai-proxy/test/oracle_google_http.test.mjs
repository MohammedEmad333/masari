import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createGoogleSessionHandler } from '../oracle_google_http.mjs';

async function fixture({ verified = true, appCheck = true, provider = 'google.com' } = {}) {
  const calls = [];
  const handler = createGoogleSessionHandler({
    verifyIdToken: async token => {
      if (!verified || token !== 'valid') throw new Error('denied');
      return { uid: 'google-uid', firebase: { sign_in_provider: provider } };
    },
    verifyAppCheck: async token => {
      if (!appCheck || token !== 'genuine') throw new Error('denied');
    },
    findOrCreate: async uid => { calls.push(uid); return 'account-1'; },
    issueSession: async accountId => ({
      token: 'msr_test',
      expiresAt: '2026-11-01T00:00:00Z',
      accountId,
    }),
  });
  const server = http.createServer((req, res) => {
    handler(req, res).then(handled => {
      if (!handled) { res.writeHead(404); res.end(); }
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return {
    url: 'http://127.0.0.1:' + server.address().port,
    calls,
    close: () => new Promise(resolve => server.close(resolve)),
  };
}
function exchange(url, { bearer = 'valid', check = 'genuine', body } = {}) {
  return fetch(url + '/v1/assistant/google-session', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + bearer,
      'X-Firebase-AppCheck': check,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body } : {}),
  });
}
test('only valid Google sign-in and App Check can issue Oracle session', async () => {
  const fx = await fixture();
  try {
    const response = await exchange(fx.url);
    assert.equal(response.status, 200);
    assert.deepEqual(fx.calls, ['google-uid']);
    assert.deepEqual(await response.json(), {
      token: 'msr_test', expiresAt: '2026-11-01T00:00:00Z',
    });
  } finally { await fx.close(); }
});
test('rejects forged Firebase tokens, unverified devices and other providers', async () => {
  for (const options of [{ verified: false }, { appCheck: false }, { provider: 'password' }]) {
    const fx = await fixture(options);
    try {
      const response = await exchange(fx.url);
      assert.equal(response.status, options.provider === 'password' ? 403 : 401);
      assert.equal(fx.calls.length, 0);
    } finally { await fx.close(); }
  }
});
test('refuses any request body and non-POST requests', async () => {
  const fx = await fixture();
  try {
    assert.equal((await exchange(fx.url, { body: '{}' })).status, 400);
    assert.equal((await fetch(fx.url + '/v1/assistant/google-session')).status, 405);
    assert.equal(fx.calls.length, 0);
  } finally { await fx.close(); }
});
