import { test } from 'node:test';
import assert from 'node:assert/strict';
import { provisionPairing } from '../oracle_provision.mjs';
test('rejects noninteractive operation before any database access', async () => {
  let queries = 0;
  const pool = { query: async () => { queries++; } };
  await assert.rejects(provisionPairing({
    pool, input: { isTTY: false }, output: { isTTY: false },
  }), /Interactive SSH terminal required/);
  assert.equal(queries, 0);
});
test('refuses non-interactive output even when stdin is interactive', async () => {
  await assert.rejects(provisionPairing({
    pool: { query: async () => { throw Error('unexpected database query'); } },
    input: { isTTY: true }, output: { isTTY: false },
  }), /Interactive SSH terminal required/);
});
