import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { createOracleAccountHandler } from '../oracle_account_api.mjs';
import { ACCOUNT_DATA_SCHEMA, createOracleAccountStore } from '../oracle_account_store.mjs';

const a = 'b60cfadd-a659-48d3-a238-8b8ccf796632';
const b = 'a7251b22-dced-4227-b3b7-cd39924de0ce';
const tokenA = 'msr_' + 'a'.repeat(64);
const tokenB = 'msr_' + 'b'.repeat(64);
const personal = { schema: 1, manualTasks: [], plans: [] };
const calendar = {
  version: 1, salt: 'YWJj', nonce: 'YWJj', ciphertext: 'YWJj', mac: 'YWJj',
};

function fixture() {
  const documents = new Map();
  const revisions = new Map();
  const profiles = new Map();
  const revoked = new Set();
  let accountDeleted = false;
  let globalCount = 0;
  const handler = createOracleAccountHandler({
    authenticate: async token => revoked.has(token) ? null :
      token === tokenA ? { uid: a } : token === tokenB ? { uid: b } : null,
    verifyGoogle: async token => {
      if (token !== 'valid-google-id-token') throw new Error('bad google identity');
      return { sub: '1234567890' };
    },
    exchangeGoogle: async sub => {
      assert.equal(sub, '1234567890');
      return { token: tokenA, expiresAt: '2026-11-10T00:00:00Z' };
    },
    reserveGlobal: async () => { globalCount++; },
    reserveIdentity: async sub => { assert.equal(sub, '1234567890'); },
    revokeSession: async token => { revoked.add(token); },
    store: {
      getProfile: async id => ({ accountId: id, displayName: profiles.get(id) ?? null }),
      updateProfile: async (id, name) => {
        profiles.set(id, name.trim());
        return { accountId: id, displayName: name.trim() };
      },
      getDocument: async (id, kind) => documents.get(id + ':' + kind) ?? null,
      getDocumentWithRevision: async (id, kind) => {
        const key = id + ':' + kind;
        return documents.has(key) ? { data: documents.get(key), revision: revisions.get(key) } : null;
      },
      putDocument: async (id, kind, value, expected = null) => {
        const key = id + ':' + kind;
        const current = revisions.get(key) ?? 0;
        if (expected !== null && expected !== current) {
          const error = new Error('conflict');
          error.code = 'backup_conflict';
          throw error;
        }
        documents.set(key, value);
        revisions.set(key, current + 1);
        return current + 1;
      },
      deleteDocument: async (id, kind) => {
        documents.delete(id + ':' + kind);
        revisions.delete(id + ':' + kind);
      },
      deleteAccount: async id => {
        assert.equal(id, a);
        accountDeleted = true;
        documents.delete(id + ':personal');
        documents.delete(id + ':calendar');
        revoked.add(tokenA);
      },
    },
  });
  async function request(method, path, token = tokenA, body, headers = {}) {
    const value = body === undefined ? '' : JSON.stringify(body);
    const input = Readable.from(value ? [Buffer.from(value)] : []);
    input.method = method;
    input.url = path;
    input.headers = {
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      ...(token ? { authorization: 'Bearer ' + token } : {}),
      ...headers,
    };
    const output = {
      statusCode: null,
      writeHead(code) { this.statusCode = code; },
      end(value) { this.data = JSON.parse(value); },
    };
    await handler(input, output);
    return { status: output.statusCode, body: output.data };
  }
  return { request, revoked, documents, profiles, get deleted() { return accountDeleted; }, get globalCount() { return globalCount; } };
}

test('Google OIDC exchange requires a verified token and an empty body', async () => {
  const f = fixture();
  assert.equal((await f.request('POST', '/v1/auth/google-oidc', 'valid-google-id-token', {})).status, 200);
  assert.equal((await f.request('POST', '/v1/auth/google-oidc', 'invalid', {})).status, 401);
  assert.equal((await f.request('POST', '/v1/auth/google-oidc', 'valid-google-id-token', { uid: b })).status, 413);
  assert.equal((await f.request('POST', '/v1/auth/google-oidc', 'valid-google-id-token', { x: 1 })).status, 400);
  assert.equal(f.globalCount, 4);
});

test('profile and backup access use only the authenticated account', async () => {
  const f = fixture();
  assert.equal((await f.request('GET', '/v1/account/me', tokenA)).body.accountId, a);
  assert.equal((await f.request('PATCH', '/v1/account/me', tokenA, { displayName: 'Alice' })).status, 200);
  assert.equal((await f.request('GET', '/v1/account/me', tokenB)).body.displayName, null);
  assert.equal((await f.request('PUT', '/v1/backups/personal', tokenA, { data: personal, accountId: b })).status, 400);
  assert.equal((await f.request('PUT', '/v1/backups/personal', tokenA, { data: personal })).status, 200);
  assert.deepEqual((await f.request('GET', '/v1/backups/personal', tokenA)).body.data, personal);
  assert.equal((await f.request('GET', '/v1/backups/personal', tokenB)).status, 404);
  assert.equal((await f.request('DELETE', '/v1/backups/personal', tokenB)).status, 200);
  assert.deepEqual((await f.request('GET', '/v1/backups/personal', tokenA)).body.data, personal);
});

test('concurrent device revisions prevent lost task/plan updates', async () => {
  const f = fixture();
  const initial = await f.request('GET', '/v1/backups/personal', tokenA);
  assert.equal(initial.status, 404);
  const first = await f.request('PUT', '/v1/backups/personal', tokenA,
    { data: personal }, { 'x-backup-revision': '0' });
  assert.equal(first.status, 200);
  assert.equal(first.body.revision, 1);
  const staleNew = await f.request('PUT', '/v1/backups/personal', tokenA,
    { data: personal }, { 'x-backup-revision': '0' });
  assert.equal(staleNew.status, 409);
  const snapshot = await f.request('GET', '/v1/backups/personal', tokenA);
  assert.equal(snapshot.body.revision, 1);
  const second = await f.request('PUT', '/v1/backups/personal', tokenA,
    { data: { ...personal, manualTasks: [{ uid: 'one' }] } },
    { 'x-backup-revision': '1' });
  assert.equal(second.status, 200);
  assert.equal(second.body.revision, 2);
  const stale = await f.request('PUT', '/v1/backups/personal', tokenA,
    { data: personal }, { 'x-backup-revision': '1' });
  assert.equal(stale.status, 409);
  assert.equal((await f.request('GET', '/v1/backups/personal', tokenA)).body.data.manualTasks.length, 1);
  assert.equal((await f.request('PUT', '/v1/backups/personal', tokenA,
    { data: personal }, { 'x-backup-revision': 'wat' })).status, 400);
  assert.equal((await f.request('GET', '/v1/backups/personal', tokenB)).status, 404);
});

test('calendar backups only accept encrypted envelope; unsafe bodies rejected', async () => {
  const f = fixture();
  assert.equal((await f.request('PUT', '/v1/backups/calendar', tokenA, { data: calendar })).status, 200);
  assert.deepEqual((await f.request('GET', '/v1/backups/calendar', tokenA)).body.data, calendar);
  assert.equal((await f.request('PUT', '/v1/backups/calendar', tokenA,
    { data: { ...calendar, plainUrl: 'https://secret.example/' } })).status, 400);
  assert.equal((await f.request('PUT', '/v1/backups/personal', tokenA,
    { data: { schema: 1, manualTasks: {}, plans: [] } })).status, 400);
  assert.equal((await f.request('POST', '/v1/backups/calendar', tokenA)).status, 405);
});

test('personal backups reject unexpected credential fields and suspicious values', async () => {
  const f = fixture();
  for (const unsafe of [
    { ...personal, manualTasks: [{ uid: 't-1', title: 'Read', due: '2026-11-12T00:00:00Z', priority: 1, password: 'private' }] },
    { ...personal, manualTasks: [{ uid: 't-1', title: 'https://example.test/?authtoken=secret', due: '2026-11-12T00:00:00Z', priority: 1 }] },
    { ...personal, plans: [{ deadlineId: 'p-1', steps: [{ id: 's-1', title: 'Read', scheduledFor: '2026-11-12T00:00:00Z', status: 'notStarted', oauthToken: 'private' }] }] },
    { ...personal, plans: [{ deadlineId: 'p-1', steps: 'not-an-array' }] },
  ]) {
    assert.equal((await f.request('PUT', '/v1/backups/personal', tokenA,
      { data: unsafe })).status, 400);
  }
  const good = {
    ...personal,
    manualTasks: [{ uid: 't-1', title: 'Read', due: '2026-11-12T00:00:00Z', priority: 1, description: 'Lecture 4', course: 'Math' }],
    plans: [{ deadlineId: 't-1', steps: [{ id: 'step-1', title: 'Exercise', scheduledFor: '2026-11-12T00:00:00Z', status: 'notStarted' }] }],
  };
  assert.equal((await f.request('PUT', '/v1/backups/personal', tokenA,
    { data: good })).status, 200);
});

test('Oracle session required; logout invalidates token', async () => {
  const f = fixture();
  assert.equal((await f.request('GET', '/v1/account/me', null)).status, 401);
  assert.equal((await f.request('GET', '/v1/account/me', 'forged')).status, 401);
  assert.equal((await f.request('POST', '/v1/auth/logout', tokenA)).status, 200);
  assert.equal((await f.request('GET', '/v1/account/me', tokenA)).status, 401);
});

test('account deletion requires explicit header and uses authenticated identity', async () => {
  const f = fixture();
  assert.equal((await f.request('DELETE', '/v1/account/me', tokenA)).status, 400);
  assert.equal(f.deleted, false);
  assert.equal((await f.request('DELETE', '/v1/account/me', tokenA, undefined,
    { 'x-confirm-account-deletion': 'delete-my-account' })).status, 200);
  assert.equal(f.deleted, true);
  assert.equal((await f.request('GET', '/v1/account/me', tokenA)).status, 401);
});

test('account store always scopes reads and writes by authenticated UUID', async () => {
  const calls = [];
  const pool = {
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql.startsWith('SELECT display_name')) return { rows: [] };
      if (sql.startsWith('SELECT document_json')) return { rows: [] };
      return { rowCount: 1, rows: [{ display_name: 'Alice', revision: 1 }] };
    },
    async connect() {
      return { query: pool.query, release() {} };
    },
  };
  const store = createOracleAccountStore({ pool });
  await store.getProfile(a);
  await store.updateProfile(a, ' Alice ');
  await store.putDocument(a, 'personal', personal);
  await store.getDocument(b, 'personal');
  await store.deleteDocument(b, 'calendar');
  assert.deepEqual(calls.map(c => c.params[0]), [a, a, a, b, b]);
  assert.match(ACCOUNT_DATA_SCHEMA, /PRIMARY KEY \(account_id, document_kind\)/);
  assert.match(ACCOUNT_DATA_SCHEMA, /REFERENCES ai_accounts/);
  assert.match(ACCOUNT_DATA_SCHEMA, /ADD COLUMN IF NOT EXISTS revision/);
  assert.match(calls.find(c => c.sql.includes('ON CONFLICT (account_id,document_kind)')).sql,
    /revision=masari_account_documents.revision\+1/);
  await assert.rejects(store.putDocument('bad-account', 'personal', personal), /Invalid account/);
  await assert.rejects(store.getDocument(a, 'random'), /Invalid document/);
});
