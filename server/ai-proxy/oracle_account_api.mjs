// Firebase-free HTTP account boundary. Authentication comes from Google OIDC
// at sign-in, then short-lived, SHA-256-hashed Oracle session tokens.
const reply = (res, status, body) => {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(JSON.stringify(body));
};
const object = value => value !== null && typeof value === 'object' &&
  !Array.isArray(value);
const isBase64 = value => typeof value === 'string' && value.length >= 4 &&
  value.length <= 100000 && /^[A-Za-z0-9+/]*={0,2}$/.test(value);
const validPayload = (kind, value) => {
  if (!object(value)) return false;
  const keys = Object.keys(value);
  if (kind === 'personal') {
    return keys.length === 3 && keys.every(k => ['schema', 'manualTasks', 'plans'].includes(k)) &&
      value.schema === 1 && Array.isArray(value.manualTasks) &&
      Array.isArray(value.plans) && value.manualTasks.length <= 1000 &&
      value.plans.length <= 1000;
  }
  return kind === 'calendar' && keys.length === 5 &&
    keys.every(k => ['version','salt','nonce','ciphertext','mac'].includes(k)) &&
    value.version === 1 && isBase64(value.salt) && isBase64(value.nonce) &&
    isBase64(value.ciphertext) && isBase64(value.mac);
};

async function readJson(req, limit) {
  if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] || '')) {
    return { error: 'content_type', status: 415 };
  }
  const length = Number(req.headers['content-length'] || 0);
  if (!Number.isFinite(length) || length > limit) return { error: 'request_too_large', status: 413 };
  let size = 0;
  const chunks = [];
  try {
    for await (const chunk of req) {
      size += chunk.length;
      if (size > limit) return { error: 'request_too_large', status: 413 };
      chunks.push(chunk);
    }
    const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!object(value)) return { error: 'invalid_body', status: 400 };
    return { value };
  } catch {
    return { error: 'invalid_body', status: 400 };
  }
}

export function createOracleAccountHandler({
  authenticate, verifyGoogle, exchangeGoogle,
  reserveGlobal, reserveIdentity, store, revokeSession,
} = {}) {
  if ([authenticate, verifyGoogle, exchangeGoogle, reserveGlobal, reserveIdentity,
    revokeSession].some(f => typeof f !== 'function') ||
    !store || typeof store.getDocument !== 'function') {
    throw new TypeError('Oracle account handler dependencies required');
  }
  return async function handle(req, res) {
    const path = req.url;
    if (req.method === 'GET' && path === '/health') {
      return reply(res, 200, { status: 'ok' });
    }
    const authorized = new Set([
      '/v1/auth/logout', '/v1/account/me',
      '/v1/backups/personal', '/v1/backups/calendar',
    ]);
    const exchange = path === '/v1/auth/google-oidc';
    if (!exchange && !authorized.has(path)) return reply(res, 404, { error: 'not_found' });

    const header = req.headers.authorization;
    if (typeof header !== 'string' || !header.startsWith('Bearer ') ||
        header.length > 8200) return reply(res, 401, { error: 'sign_in_required' });
    const bearer = header.slice(7);

    if (exchange) {
      if (req.method !== 'POST') return reply(res, 405, { error: 'method_not_allowed' });
      try { await reserveGlobal(); } catch (e) {
        return reply(res, e?.code === 'pairing_rate_exceeded' ? 429 : 503,
          { error: e?.code === 'pairing_rate_exceeded' ? 'rate_limited' : 'service_unavailable' });
      }
      const body = await readJson(req, 32);
      if (body.error) return reply(res, body.status, { error: body.error });
      if (Object.keys(body.value).length !== 0) {
        return reply(res, 400, { error: 'invalid_body' });
      }
      let identity;
      try { identity = await verifyGoogle(bearer); } catch {
        return reply(res, 401, { error: 'invalid_authentication' });
      }
      try {
        await reserveIdentity(identity.sub);
        const session = await exchangeGoogle(identity.sub);
        return reply(res, 200, session);
      } catch (e) {
        return reply(res, e?.code === 'pairing_rate_exceeded' ? 429 : 503,
          { error: e?.code === 'pairing_rate_exceeded' ? 'rate_limited' : 'service_unavailable' });
      }
    }

    if (!/^msr_[0-9a-f]{64}$/.test(bearer)) {
      return reply(res, 401, { error: 'invalid_authentication' });
    }
    let account;
    try { account = await authenticate(bearer); } catch {
      return reply(res, 401, { error: 'invalid_authentication' });
    }
    if (!account || typeof account.uid !== 'string') {
      return reply(res, 401, { error: 'invalid_authentication' });
    }
    const id = account.uid;
    try {
      if (path === '/v1/auth/logout') {
        if (req.method !== 'POST') return reply(res, 405, { error: 'method_not_allowed' });
        await revokeSession(bearer);
        return reply(res, 200, { status: 'signed_out' });
      }
      if (path === '/v1/account/me') {
        if (req.method === 'GET') return reply(res, 200, await store.getProfile(id));
        if (req.method === 'PATCH') {
          const body = await readJson(req, 2048);
          if (body.error) return reply(res, body.status, { error: body.error });
          if (Object.keys(body.value).length !== 1 ||
              typeof body.value.displayName !== 'string' ||
              !body.value.displayName.trim() ||
              [...body.value.displayName.trim()].length > 80) {
            return reply(res, 400, { error: 'invalid_profile' });
          }
          return reply(res, 200, await store.updateProfile(id, body.value.displayName));
        }
        if (req.method === 'DELETE') {
          if (req.headers['x-confirm-account-deletion'] !== 'delete-my-account') {
            return reply(res, 400, { error: 'confirmation_required' });
          }
          await store.deleteAccount(id);
          return reply(res, 200, { status: 'account_deleted' });
        }
        return reply(res, 405, { error: 'method_not_allowed' });
      }
      const kind = path.slice('/v1/backups/'.length);
      if (req.method === 'GET') {
        const found = await store.getDocument(id, kind);
        return found === null ? reply(res, 404, { error: 'backup_not_found' }) :
          reply(res, 200, { data: found });
      }
      if (req.method === 'PUT') {
        const body = await readJson(req, 128 * 1024);
        if (body.error) return reply(res, body.status, { error: body.error });
        if (Object.keys(body.value).length !== 1 ||
            !validPayload(kind, body.value.data)) {
          return reply(res, 400, { error: 'invalid_backup' });
        }
        await store.putDocument(id, kind, body.value.data);
        return reply(res, 200, { status: 'saved' });
      }
      if (req.method === 'DELETE') {
        await store.deleteDocument(id, kind);
        return reply(res, 200, { status: 'deleted' });
      }
      return reply(res, 405, { error: 'method_not_allowed' });
    } catch {
      // Never leak PostgreSQL, tokens or private backup data in errors.
      return reply(res, 503, { error: 'service_unavailable' });
    }
  };
}
