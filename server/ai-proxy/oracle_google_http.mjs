// Exchange a verified Google/Firebase identity for an Oracle-only AI session.
// This endpoint is default-off and requires Firebase App Check as anti-abuse.
export function createGoogleSessionHandler({
  verifyIdToken, verifyAppCheck, findOrCreate, issueSession,
} = {}) {
  for (const dependency of [verifyIdToken, verifyAppCheck, findOrCreate, issueSession]) {
    if (typeof dependency !== 'function') throw new TypeError('Google session dependencies required');
  }
  function reply(res, status, body) {
    res.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    res.end(JSON.stringify(body));
  }
  return async function handle(req, res) {
    if (req.url !== '/v1/assistant/google-session') return false;
    if (req.method !== 'POST') {
      reply(res, 405, { error: 'method_not_allowed' });
      return true;
    }
    if (Number(req.headers['content-length'] || 0) > 0 ||
        req.headers['transfer-encoding']) {
      reply(res, 400, { error: 'unexpected_body' });
      return true;
    }
    const authorization = req.headers.authorization;
    const appCheck = req.headers['x-firebase-appcheck'];
    if (typeof authorization !== 'string' ||
        !/^Bearer [^ ]{1,4096}$/.test(authorization) ||
        typeof appCheck !== 'string' || !appCheck ||
        appCheck.length > 4096) {
      reply(res, 401, { error: 'authentication_required' });
      return true;
    }
    let identity;
    try {
      identity = await verifyIdToken(authorization.slice(7));
      await verifyAppCheck(appCheck);
    } catch {
      reply(res, 401, { error: 'authentication_failed' });
      return true;
    }
    // Only a Firebase token with a Google sign-in provider may create a
    // Google-only Oracle account. Firebase email/password is not sufficient.
    if (typeof identity?.uid !== 'string' ||
        identity.firebase?.sign_in_provider !== 'google.com') {
      reply(res, 403, { error: 'google_sign_in_required' });
      return true;
    }
    try {
      const accountId = await findOrCreate(identity.uid);
      const session = await issueSession(accountId);
      reply(res, 200, { token: session.token, expiresAt: session.expiresAt });
    } catch {
      reply(res, 503, { error: 'account_service_unavailable' });
    }
    return true;
  };
}
