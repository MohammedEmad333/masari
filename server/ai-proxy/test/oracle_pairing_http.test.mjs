import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createPairingHandler } from '../oracle_pairing_http.mjs';
const code = 'pair_' + 'a'.repeat(64);
async function fixture({ enabled = false, redeemCode = async () => null, perWindow = 5 } = {}) {
  const handler = createPairingHandler({ enabled, redeemCode, perWindow });
  const server = http.createServer(async (req, res) => {
    if (!(await handler(req, res))) {
      res.writeHead(404);
      res.end();
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return {
    base: 'http://127.0.0.1:' + server.address().port,
    close: () => new Promise(resolve => server.close(resolve)),
  };
}
async function post(fx, json = JSON.stringify({ code }), headers = {}) {
  return fetch(fx.base + '/v1/assistant/pair', {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: json,
  });
}
test('disabled by default even for a valid code', async () => {
  const fx = await fixture({ redeemCode: async () => { throw Error('must not redeem'); } });
  try {
    const result = await post(fx);
    assert.equal(result.status, 404);
  } finally { await fx.close(); }
});
test('valid pairing returns the session but no credentials in error responses', async () => {
  const fx = await fixture({ enabled: true, redeemCode: async v =>
    v === code ? { token: 'msr_' + 'b'.repeat(64), expiresAt: '2026-10-28T12:00:00Z' } : null });
  try {
    const r = await post(fx);
    assert.equal(r.status, 200);
    assert.equal((await r.json()).token.length, 68);
    const invalid = await post(fx, JSON.stringify({ code: 'pair_' + 'c'.repeat(64) }));
    assert.equal(invalid.status, 401);
    assert(!((await invalid.text()).includes('msr_')));
  } finally { await fx.close(); }
});
test('strict body, method and one-use entry shape checks', async () => {
  const fx = await fixture({ enabled: true });
  try {
    assert.equal((await post(fx, '{oops')).status, 400);
    assert.equal((await post(fx, JSON.stringify({ code, uid: 'forged' }))).status, 400);
    assert.equal((await post(fx, JSON.stringify({ code }), { 'Content-Type': 'text/plain' })).status, 415);
    assert.equal((await fetch(fx.base + '/v1/assistant/pair')).status, 405);
  } finally { await fx.close(); }
});
test('throttles repeated invalid attempts before lookup', async () => {
  let calls = 0;
  const fx = await fixture({ enabled: true, perWindow: 2, redeemCode: async () => { calls++; return null; } });
  try {
    assert.equal((await post(fx)).status, 401);
    assert.equal((await post(fx)).status, 401);
    assert.equal((await post(fx)).status, 429);
    assert.equal(calls, 2);
  } finally { await fx.close(); }
});
test('database failure fails closed', async () => {
  const fx = await fixture({ enabled: true, redeemCode: async () => { throw Error('db secret'); } });
  try {
    const r = await post(fx);
    assert.equal(r.status, 503);
    assert(!((await r.text()).includes('db secret')));
  } finally { await fx.close(); }
});
