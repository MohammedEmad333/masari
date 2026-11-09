'use strict';

const { before, after, test } = require('node:test');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

let env;
const secretPath = 'users/alice/calendarSecrets/v1';
const payload = {
  version: 1,
  salt: 'salt',
  nonce: 'nonce',
  ciphertext: 'encrypted',
  mac: 'mac',
  updatedAt: '2026-11-09T00:00:00Z',
};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-masari-rules',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: readFileSync(join(__dirname, 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  if (env) await env.cleanup();
});

test('owners can create then delete their own v1 encrypted secret', async () => {
  const ref = env.authenticatedContext('alice').firestore().doc(secretPath);
  await assertSucceeds(ref.set(payload));
  await assertSucceeds(ref.delete());
});

test('another user cannot delete a private secret', async () => {
  const ref = env.authenticatedContext('bob').firestore().doc(secretPath);
  await assertFails(ref.delete());
});

test('unauthenticated clients cannot delete private secrets', async () => {
  const ref = env.unauthenticatedContext().firestore().doc(secretPath);
  await assertFails(ref.delete());
});

test('owner cannot delete other secret IDs', async () => {
  const ref = env.authenticatedContext('alice').firestore()
    .doc('users/alice/calendarSecrets/v2');
  await assertFails(ref.delete());
});

test('other users cannot create a private secret', async () => {
  const ref = env.authenticatedContext('bob').firestore().doc(secretPath);
  await assertFails(ref.set(payload));
});

test('invalid secret documents remain blocked', async () => {
  const ref = env.authenticatedContext('alice').firestore().doc(secretPath);
  await assertFails(ref.set({ version: 1 }));
});
