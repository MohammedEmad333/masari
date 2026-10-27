import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createRequestHandler, createAllowedUserValidator } from '../core.mjs';

async function fixture(options = {}) {
  const calls = [];
  const server = http.createServer(createRequestHandler({
    authenticate: async token => {
      if (token !== 'valid') throw new Error('denied');
      return { uid: 'student-1' };
    },
    complete: async request => {
      calls.push(request);
      return 'OK';
    },
    ...options,
  }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = 'http://127.0.0.1:' + server.address().port;
  return {
    calls,
    url,
    close: () => new Promise((resolve, reject) => server.close(err => err ? reject(err) : resolve())),
  };
}
const body = (message = 'Help me study', fields = {}) =>
  JSON.stringify({ message, language: 'en', consent: true, ...fields });
async function ask(fx, data, token = 'valid') {
  return fetch(fx.url + '/v1/assistant/ask', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
    body: data,
  });
}
test('accepts explicitly consented authenticated text only', async () => {
  const fx = await fixture();
  try {
    const response = await ask(fx, body('Study schedule'));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { answer: 'OK' });
    assert.deepEqual(fx.calls, [{ message: 'Study schedule', language: 'en' }]);
  } finally { await fx.close(); }
});
test('rejects unauthenticated and no-consent requests', async () => {
  const fx = await fixture();
  try {
    assert.equal((await ask(fx, body(), 'invalid')).status, 401);
    assert.equal((await ask(fx, body('Test', { consent: false }))).status, 400);
    assert.equal(fx.calls.length, 0);
  } finally { await fx.close(); }
});
test('rejects calendar tokens, URLs and embedded task objects', async () => {
  const fx = await fixture();
  try {
    assert.equal((await ask(fx, body('authtoken=SECRET'))).status, 400);
    assert.equal((await ask(fx, body('https://private.example/'))).status, 400);
    assert.equal((await ask(fx, body('Hello', { tasks: [{ uid: 'x' }] }))).status, 400);
    assert.equal(fx.calls.length, 0);
  } finally { await fx.close(); }
});
test('limits quota by verified UID, not caller-supplied values', async () => {
  const fx = await fixture({ maxPerMinute: 1 });
  try {
    assert.equal((await ask(fx, body('First'))).status, 200);
    assert.equal((await ask(fx, body('Second'))).status, 429);
  } finally { await fx.close(); }
});
test('does not expose upstream errors or credentials', async () => {
  const fx = await fixture({
    complete: async () => { throw new Error('TOKENROUTER_API_KEY=SECRET'); },
  });
  try {
    const response = await ask(fx, body('Help'));
    assert.equal(response.status, 502);
    assert.equal((await response.text()).includes('SECRET'), false);
  } finally { await fx.close(); }
});
test('returns health without revealing configuration', async () => {
  const fx = await fixture();
  try {
    const response = await fetch(fx.url + '/health');
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: 'ok' });
  } finally { await fx.close(); }
});

test('private pilot rejects missing and malformed UID allowlists', () => {
  assert.throws(() => createAllowedUserValidator(undefined));
  assert.throws(() => createAllowedUserValidator('  '));
  assert.throws(() => createAllowedUserValidator('student-1, bad user'));
  assert.throws(() => createAllowedUserValidator('student-1,'));
});
test('private pilot only accepts allowlisted verified Firebase users', () => {
  const allow = createAllowedUserValidator(' student-1 , student-2 ');
  assert.equal(allow({ uid: 'student-1' }).uid, 'student-1');
  assert.equal(allow({ uid: 'student-2' }).uid, 'student-2');
  assert.throws(() => allow({ uid: 'student-3' }));
  assert.throws(() => allow({ uid: '' }));
  assert.throws(() => allow(null));
});
test('valid Firebase token for non-allowlisted user receives 401', async () => {
  const allow = createAllowedUserValidator('student-2');
  const fx = await fixture({
    authenticate: async token => allow(token === 'valid' ? { uid: 'student-1' } : null),
  });
  try {
    assert.equal((await ask(fx, body('Hello'))).status, 401);
    assert.equal(fx.calls.length, 0);
  } finally { await fx.close(); }
});
