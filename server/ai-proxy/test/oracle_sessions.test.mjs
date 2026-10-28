import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createOracleSessions, SESSION_SCHEMA } from '../oracle_sessions.mjs';

const ID = 'b60cfadd-a659-48d3-a238-8b8ccf796632';
const now = new Date('2026-10-28T12:00:00.000Z');
function fakePool() {
  const calls = [];
  const pool = {
    calls,
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql.startsWith('INSERT INTO ai_accounts')) return { rowCount: 1, rows: [] };
      if (sql.includes('INSERT INTO ai_sessions')) return { rowCount: 1, rows: [{ account_id: ID }] };
      if (sql.includes('SELECT s.account_id')) return { rowCount: 1, rows: [{ account_id: ID }] };
      if (sql.startsWith('UPDATE ai_sessions')) return { rowCount: 1, rows: [] };
      throw new Error('unexpected SQL');
    },
  };
  return pool;
}
test('schema constrains tokens to hashes and sessions to accounts', () => {
  assert.match(SESSION_SCHEMA, /token_hash char\(64\) PRIMARY KEY/);
  assert.match(SESSION_SCHEMA, /REFERENCES ai_accounts/);
  assert.match(SESSION_SCHEMA, /revoked_at/);
  assert.doesNotMatch(SESSION_SCHEMA, /password|raw_token/i);
});
test('creates session with random bearer; only hash is sent to database', async () => {
  const pool = fakePool();
  const store = createOracleSessions({ pool, now: () => now });
  const first = await store.issueSession(ID);
  const second = await store.issueSession(ID);
  assert.match(first.token, /^msr_[a-f0-9]{64}$/);
  assert.notEqual(first.token, second.token);
  assert.equal(first.expiresAt, '2026-10-28T13:00:00.000Z');
  for (const call of pool.calls) {
    assert.equal(call.params[0].length, 64);
    assert.equal(call.params.includes(first.token), false);
    assert.equal(call.params.includes(second.token), false);
  }
});
test('authentication hashes token, checks expiry, revocation and disabled account', async () => {
  const pool = fakePool();
  const store = createOracleSessions({ pool, now: () => now });
  const token = (await store.issueSession(ID)).token;
  assert.deepEqual(await store.authenticate(token), { uid: ID });
  const query = pool.calls.at(-1);
  assert.match(query.sql, /revoked_at IS NULL/);
  assert.match(query.sql, /expires_at > \$2/);
  assert.match(query.sql, /disabled_at IS NULL/);
  assert.equal(query.params[1], now);
  assert.equal(query.params[0].length, 64);
  assert.equal(await store.authenticate('invalid-token'), null);
});
test('revocation uses token hash, and account-wide revocation is supported', async () => {
  const pool = fakePool();
  const store = createOracleSessions({ pool, now: () => now });
  const token = (await store.issueSession(ID)).token;
  assert.equal(await store.revoke(token), true);
  assert.equal(pool.calls.at(-1).params[0].length, 64);
  assert.equal(await store.revokeAll(ID), 1);
});
test('refuses invalid sessions and TTLs before querying database', async () => {
  const pool = fakePool();
  const store = createOracleSessions({ pool, now: () => now });
  await assert.rejects(store.issueSession(ID, { ttlSeconds: 0 }));
  await assert.rejects(store.issueSession(ID, { ttlSeconds: 86401 }));
  await assert.rejects(store.issueSession('bad-id'));
  assert.equal(pool.calls.length, 0);
});
