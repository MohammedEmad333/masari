import { readFileSync } from 'node:fs';
import pg from 'pg';
import { createOracleSessions, SESSION_SCHEMA } from './oracle_sessions.mjs';
import { createOraclePairing, PAIRING_SCHEMA } from './oracle_pairing.mjs';

// Run only in an authenticated interactive SSH session on the Oracle host.
// This command is not exposed over HTTP and never prints DB credentials.
export async function provisionPairing({
  pool, output = process.stdout, input = process.stdin,
} = {}) {
  if (!input.isTTY || !output.isTTY) {
    throw new Error('Interactive SSH terminal required; redirection and CI prohibited');
  }
  await pool.query(SESSION_SCHEMA);
  await pool.query(PAIRING_SCHEMA);
  const sessions = createOracleSessions({ pool });
  const pairing = createOraclePairing({ pool });
  const accountId = await sessions.createAccount();
  const result = await pairing.generateCode(accountId);
  output.write('Oracle AI account: ' + accountId + '\n');
  output.write('ONE-TIME PAIRING CODE (10 minutes): ' + result.code + '\n');
  output.write('Do not paste this code into chat or save it in shell history.\n');
  return { accountId };
}

if (process.argv[1] && import.meta.url === new URL('file://' + process.argv[1]).href) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    process.stderr.write('Interactive SSH terminal required\n');
    process.exitCode = 1;
  } else {
    const passwordFile = process.env.MASARI_POSTGRES_PASSWORD_FILE;
    if (!passwordFile) {
      process.stderr.write('MASARI_POSTGRES_PASSWORD_FILE required\n');
      process.exitCode = 1;
    } else {
      const password = readFileSync(passwordFile, 'utf8').trim();
      const pool = new pg.Pool({
        host: process.env.MASARI_POSTGRES_HOST || 'masari-ai-postgres',
        user: 'masari_ai',
        database: 'masari_ai',
        password,
        max: 2,
      });
      try {
        await provisionPairing({ pool });
      } catch {
        process.stderr.write('Account provisioning failed\n');
        process.exitCode = 1;
      } finally {
        await pool.end();
      }
    }
  }
}
