# Masari Oracle AI proxy: safe deployment runbook

> Production service: `https://ai.edubridge.win`. Repository: `MohammedEmad333/masari`, **not** `EduBridge-Team/EduBridge`.
>
> **Status:** deployment location and Compose file name must be verified on the actual Oracle host. Do not assume `~/ai-proxy` exists. A successful `/health` response proves service availability, not the deployed Git revision.

## Discover the live Compose project (read-only)

Run from any directory on the Oracle host:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
docker ps --filter 'name=ai-proxy' --format '{{.Names}}'
docker inspect ai-proxy-masari-ai-proxy-1 \
  --format 'workdir={{index .Config.Labels "com.docker.compose.project.working_dir"}} config={{index .Config.Labels "com.docker.compose.project.config_files"}} service={{index .Config.Labels "com.docker.compose.service"}}'
```

If the container name differs, substitute the name from `docker ps`. If the Compose labels are absent, inspect the deployment manually; **do not guess a path**. The `working_dir` and `config_files` labels identify the deployment directory and Compose configuration actually used.

## Verify the source repository before any pull

```bash
cd '/PATH/REPORTED/BY/COMPOSE/WORKDIR'
pwd
git remote -v
git status --short
git rev-parse --show-toplevel
```

The Git remote must be `MohammedEmad333/masari` (or an explicitly documented deployment mirror), not EduBridge. If the Compose working directory is outside the Git checkout, identify the source path from the Compose build context and inspect that repository. Stop if the path, remote, or uncommitted changes are unexpected.

## Deploy only after checking the Compose file

From the verified **Masari** source checkout:

```bash
git fetch origin main
git status --short
git pull --ff-only origin main
git rev-parse --short HEAD
```

From the verified Compose working directory, with the exact Compose config path discovered above:

```bash
docker compose -f /VERIFIED/PATH/compose.yml config --services
docker compose -f /VERIFIED/PATH/compose.yml up -d --build <VERIFIED_AI_PROXY_SERVICE_NAME>
docker compose -f /VERIFIED/PATH/compose.yml ps
curl -fsS https://ai.edubridge.win/health
```

Replace the placeholders with the inspected values. Avoid rebuilding unrelated containers. Do not run `docker compose down -v`, `docker volume prune`, or commands that delete PostgreSQL data. Back up PostgreSQL before migrations or account deletion.

## Post-deploy checks

1. Confirm the running image/container was recreated using the intended Masari commit. `/health` returning 200 alone is insufficient.
2. Confirm `MASARI_QUOTA_BACKEND=postgres` and `MASARI_ORACLE_AUTH_ENABLED=true` **without printing secret values**.
3. Verify the Google exchange endpoint rejects requests without a valid identity token (401); do not paste credentials into shell history.
4. Check sanitized service logs for errors; never share bearer tokens, Google ID tokens, database passwords, calendar URLs, or service-account JSON.
5. Only then install a signed APK built from compatible `main` and test Google → Oracle account creation.

## Incident: wrong repository pulled

If `cd ~/ai-proxy` fails, the shell remains in its previous directory. Running `git pull` immediately afterward can update an unrelated checkout, such as `~/EduBridge`. A subsequent `docker compose` failure means the deployment did not run. Inspect `pwd` and `git remote -v` before proceeding; do not reset unrelated work without review.

## Auth transition caveat

PR #158 removed App Check only from `POST /v1/auth/google`. The exchange still requires a **Firebase ID token from a Google-authenticated Firebase user**. Direct Google OIDC verification and full Firebase Authentication removal are separate, unfinished work. Do not claim Oracle-first migration complete or delete existing account data until tested.
