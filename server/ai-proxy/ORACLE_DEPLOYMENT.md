# Masari TokenRouter proxy — Oracle ARM deployment

This runbook deploys the **small HTTP proxy only**. TokenRouter hosts GPT-OSS-120B.
Do not modify the existing EduBridge, Jabalia, or Souq Qareeb deployments.
The deployment stays **localhost-only** until the owner explicitly configures
HTTPS and completes the public-release security checklist.

## 0. Preconditions and security holds

- Oracle VM already has Docker Compose and enough free resources. ARM64 is
  supported by the Node 22 Alpine multi-arch image.
- `main` contains the tested public Firestore quota backend.
- Firebase Authentication, Cloud Firestore and a Firebase Admin SDK service
  identity for the **masari-bb658** project exist; the identity has minimal
  necessary permissions. A Firebase *client API key is not a server credential*.
- The TokenRouter key belongs to an account explicitly permitted to fund usage.
- **Before opening the public assistant:** enforce Firebase App Check on the
  backend, configure verified Android Play Integrity, configure provider-side
  spending caps/alerts, and review third-party data handling. These are *not*
  implemented by this deployment runbook.
- Never include TokenRouter keys, Firebase Admin private keys, Moodle ICS URLs,
  or tokens in chat, APK, Flutter `--dart-define`, GitHub or CI logs.

## 1. Server inventory (safe/read-only)

```bash
docker --version
docker compose version
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker network ls --format 'table {{.Name}}\t{{.Driver}}'
sudo ss -lntp | grep -E ':80 |:443 |:8096 |:8097 ' || true
# Caddy is a container; check whether it uses host or Docker bridge networking.
docker inspect caddy --format 'NetworkMode={{.HostConfig.NetworkMode}}'
docker inspect caddy --format '{{range $name,$_ := .NetworkSettings.Networks}}{{println $name}}{{end}}'
df -h /
```

**Observed server inventory (2026-10-27):** host port **8096 is used by
`souq-qareeb-staging-wordpress-1`**. The new Masari default is **host 8097 →
container 8096**, bound only to 127.0.0.1. Confirm 8097 is unused with
`sudo ss -lntp | grep ':8097 ' || true` before starting. If 8097 is occupied,
set `MASARI_AI_HOST_PORT` to another unused host port. **Never stop or rebind
Souq staging**. Container port stays 8096.

## 2. Deploy a separate checkout (no changes to existing stacks)

```bash
cd ~
git clone https://github.com/MohammedEmad333/masari.git masari-ai-source
cd ~/masari-ai-source/server/ai-proxy
mkdir -p private
chmod 700 private
```

If the repository already exists, use `git -C ~/masari-ai-source pull --ff-only`
instead of recloning. Never blindly overwrite an existing directory.

Create `private/tokenrouter_api_key` locally through a hidden terminal prompt.
The following command doesn't print the key or put its value in shell history:

```bash
(umask 077; read -r -s -p 'TokenRouter API key: ' MASARI_KEY; printf '\n'; printf '%s' "$MASARI_KEY" > private/tokenrouter_api_key; unset MASARI_KEY)
chmod 600 private/tokenrouter_api_key
```

Create a Firebase Admin service-account JSON file through a secure direct
transfer (SFTP/scp), not through chat or Git. Its destination is
`~/masari-ai-source/server/ai-proxy/private/firebase-admin.json`.
Set `chmod 600 private/firebase-admin.json`, owned by the account invoking
Docker Compose. Do **not** use `firebase_options.dart` or `google-services.json`
for this purpose.

## 3. Start localhost-only

```bash
cd ~/masari-ai-source/server/ai-proxy
export MASARI_UID="$(id -u)"
export MASARI_GID="$(id -g)"
docker compose -f compose.oracle.yaml config --quiet
docker compose -f compose.oracle.yaml up -d --build
docker compose -f compose.oracle.yaml ps
curl -fsS http://127.0.0.1:8097/health
```

Expected health response: `{"status":"ok"}`. This confirms the local process,
not Firebase or TokenRouter connectivity. Check sanitized logs with
`docker logs --tail 40 masari-ai-proxy`; logs should never contain prompts
or credentials.

The port is restricted to host loopback; **do not** open 8097 in Oracle VCN
or UFW. The container is capped at 512MB RAM and one CPU.

## 4. HTTPS through the EXISTING Dockerized Caddy

The server inventory shows that `caddy` is a container with no ports
published in `docker ps`. **This does not reveal its network mode.** Check:

```bash
docker inspect caddy --format 'NetworkMode={{.HostConfig.NetworkMode}}'
docker inspect caddy --format '{{range $name,$_ := .NetworkSettings.Networks}}{{println $name}}{{end}}'
docker inspect caddy --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
```

Choose the connection mode **based on the output**, not an assumption:

**If `NetworkMode=host`:** Caddy shares Oracle's network namespace; use
`reverse_proxy 127.0.0.1:8097`. No Docker network override needed.

**If Caddy uses a Docker bridge network:** choose its actual bridge network
and attach only the Masari container to it:

```bash
export CADDY_NETWORK='ACTUAL_EXISTING_CADDY_BRIDGE_NETWORK'
docker compose -f compose.oracle.yaml \
  -f compose.oracle-caddy-network.yaml up -d
```

Then use `reverse_proxy masari-ai-proxy:8096` in Caddy. Port 8097 remains
bound on the host's loopback only, and 8096 remains private within Docker.
Do **not** choose an isolated unrelated Docker network, and never guess
`edubridge-net` without inspecting Caddy.

Only when the service works locally, a chosen hostname (for example
`ai.edubridge.win`) is confirmed under your control, its DNS resolves to
Oracle, and public release security gates are satisfied, add one isolated
site block to the existing Caddyfile:

```caddyfile
ai.edubridge.win {
    reverse_proxy 127.0.0.1:8097
}
```

The above target is for Caddy **host-network** mode only. For Caddy
**bridge-network** mode, use `masari-ai-proxy:8096` instead. Back up the
original Caddyfile; validate changes before reload. Do not overwrite
the current Caddy configuration or disrupt other applications.

## 5. End-to-end validation and mobile rollout

- Verify `https://ai.edubridge.win/health` over TLS returns 200.
- Verify `POST /v1/assistant/ask` without Firebase Bearer authentication
  returns **401**. Use fake prompt text; do not send real keys.
- Confirm Firebase Auth token verification and transactional Firestore
  counters with a TEST account only after budget controls are present.
- Add verified Firebase App Check enforcement before enabling for everyone.
- Build the **signed** Flutter release through the project's normal release
  workflow with the public build define
  `MASARI_AI_PROXY_URL=https://ai.edubridge.win/v1/assistant/ask`.
  CI smoke APKs are not signed for distribution.
- Test on Android: login, Arabic/English, consent each question, 401/429/503,
  airplane mode, existing Moodle calendar sync, and scheduled notifications.
- Roll back the **proxy** without affecting existing apps using
  `docker compose -f compose.oracle.yaml stop masari-ai`. Users retain local
  task and calendar functionality.

## Operations and scale

Firestore transaction limits are initially 3/user/minute, 10/user/UTC-day,
300 globally/UTC-day. These cap requests, **not dollars**. TokenRouter may
bill independently; review model cost, enforce financial limits at provider
and budget monitoring. Set Firestore TTL on `masari_ai_usage.expiresAt`.
The single shared Firestore daily counter is intended for a modest initial
load and may cause contention as concurrency increases.

Do not run a publicly exposed service account key in a widely accessible
directory or image layer. Rotate any exposed credentials immediately.
