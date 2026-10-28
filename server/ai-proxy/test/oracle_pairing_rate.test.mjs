import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createPairingRateLimiter, PairingRateExceeded, PAIRING_RATE_SCHEMA } from '../oracle_pairing_rate.mjs';

function fakePool() {
  const calls = [];
  let count = 0;
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql.includes('INSERT INTO ai_pairing_rate_limits')) {
        return { rows: [{ attempts: ++count }] };
      }
      return { rows: [] };
    },
    release() { calls.push({ sql: 'RELEASE', params: [] }); },
  };
  return { calls, pool: { connect: async () => client } };
}
test('database enforces a keyed window and expiry index', () => {
  assert.match(PAIRING_RATE_SCHEMA, /PRIMARY KEY \(identity_hash, window_id\)/);
  assert.match(PAIRING_RATE_SCHEMA, /expires_at/);
});
test('increments durable counter and rejects over-limit requests', async () => {
  const f = fakePool();
  const reserve = createPairingRateLimiter({
    pool: f.pool, maxAttempts: 2, now: () => 120000,
  });
  assert.equal(await reserve('trusted-ip:127.0.0.1'), 1);
  assert.equal(await reserve('trusted-ip:127.0.0.1'), 2);
  await assert.rejects(reserve('trusted-ip:127.0.0.1'), PairingRateExceeded);
  const inserts = f.calls.filter(c => c.sql.includes('INSERT INTO ai_pairing_rate_limits'));
  assert.equal(inserts.length, 3);
  assert.equal(inserts[0].params[0].length, 64);
  assert.equal(inserts[0].params[1], 2);
  assert(!JSON.stringify(inserts).includes('127.0.0.1'));
  assert.equal(f.calls.filter(c => c.sql === 'COMMIT').length, 3);
});
test('rejects bad identities and settings before allocating connections', async () => {
  const f = fakePool();
  assert.throws(() => createPairingRateLimiter({ pool: f.pool, maxAttempts: 0 }));
  assert.throws(() => createPairingRateLimiter({ pool: f.pool, windowSeconds: 0 }));
  const reserve = createPairingRateLimiter({ pool: f.pool });
  await assert.rejects(reserve(''));
  await assert.rejects(reserve('x'.repeat(257)));
  assert.equal(f.calls.length, 0);
});
test('database errors deny requests and roll back transaction', async () => {
  let rolledBack = false;
  let released = false;
  const reserve = createPairingRateLimiter({
    pool: { connect: async () => ({
      query: async sql => {
        if (sql.includes('INSERT INTO')) throw Error('db unavailable');
        if (sql === 'ROLLBACK') rolledBack = true;
        return { rows: [] };
      },
      release: () => { released = true; },
    }) },
  });
  await assert.rejects(reserve('device:test'), /db unavailable/);
  assert.equal(rolledBack, true);
  assert.equal(released, true);
});
