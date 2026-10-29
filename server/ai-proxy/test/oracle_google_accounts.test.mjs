import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGoogleAccounts, GOOGLE_ACCOUNT_SCHEMA } from '../oracle_google_accounts.mjs';

const accountId = 'b60cfadd-a659-48d3-a238-8b8ccf796632';
const verified = { uid: 'firebase-uid_123', firebase: { sign_in_provider: 'google.com' } };

function fixture() {
  const calls = [];
  const mapping = new Map();
  let created = 0;
  let issued = 0;
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' ||
          sql.startsWith('SELECT pg_advisory_xact_lock')) return { rows: [] };
      if (sql.startsWith('SELECT account_id FROM ai_google_accounts')) {
        const found = mapping.get(params[0]);
        return { rows: found ? [{ account_id: found }] : [] };
      }
      if (sql.startsWith('INSERT INTO ai_accounts')) {
        created++;
        return { rows: [] };
      }
      if (sql.startsWith('INSERT INTO ai_google_accounts')) {
        mapping.set(params[0], params[1]);
        return { rows: [] };
      }
      throw new Error('Unexpected SQL: ' + sql);
    },
    release() { calls.push({ sql: 'RELEASE' }); },
  };
  const pool = { async connect() { return client; } };
  const exchange = createGoogleAccounts({
    pool,
    createAccount: async () => accountId,
    issueSession: async (id, options) => {
      assert.equal(typeof id, 'string');
      assert.deepEqual(options, { ttlSeconds: 3600 });
      issued++;
      return { token: 'redacted', expiresAt: '2026-10-29T01:00:00Z' };
    },
  });
  return { exchange, calls, mapping, stats: () => ({ created, issued }) };
}

test('Google schema maps unique Firebase UID to an Oracle account', () => {
  assert.match(GOOGLE_ACCOUNT_SCHEMA, /firebase_uid text PRIMARY KEY/);
  assert.match(GOOGLE_ACCOUNT_SCHEMA, /account_id uuid NOT NULL UNIQUE/);
  assert.doesNotMatch(GOOGLE_ACCOUNT_SCHEMA, /email/i);
});

test('same verified Google UID reuses account, not a second registration', async () => {
  const f = fixture();
  await f.exchange(verified);
  const first = f.mapping.get(verified.uid);
  await f.exchange(verified);
  assert.equal(f.mapping.get(verified.uid), first);
  assert.equal(f.stats().created, 1);
  assert.equal(f.stats().issued, 2);
  assert.equal(f.calls.filter(c => c.sql === 'COMMIT').length, 2);
  assert.equal(f.calls.filter(c => c.sql === 'RELEASE').length, 2);
});

test('rejects unknown, unverified, non-Google and invalid user identities', async () => {
  const f = fixture();
  for (const identity of [
    undefined,
    { uid: 'alice' },
    { uid: 'alice', firebase: { sign_in_provider: 'password' } },
    { uid: 'alice', firebase: { sign_in_provider: 'anonymous' } },
    { uid: 'bad uid', firebase: { sign_in_provider: 'google.com' } },
    { uid: 'a'.repeat(129), firebase: { sign_in_provider: 'google.com' } },
  ]) {
    await assert.rejects(f.exchange(identity), /Google sign-in required/);
  }
  assert.equal(f.calls.length, 0);
});

test('database failure rolls back and releases connection without issuing a session', async () => {
  let released = false;
  let rolledBack = false;
  let issued = false;
  const pool = { async connect() {
    return {
      async query(sql) {
        if (sql === 'ROLLBACK') { rolledBack = true; return; }
        if (sql.startsWith('SELECT pg_advisory_xact_lock')) throw new Error('database error');
      },
      release() { released = true; },
    };
  } };
  const exchange = createGoogleAccounts({
    pool,
    createAccount: async () => accountId,
    issueSession: async () => { issued = true; },
  });
  await assert.rejects(exchange(verified), /database error/);
  assert.equal(rolledBack, true);
  assert.equal(released, true);
  assert.equal(issued, false);
});
