FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force

COPY index.mjs core.mjs firestore_quota.mjs postgres_quota.mjs \
     oracle_sessions.mjs oracle_pairing.mjs oracle_pairing_rate.mjs \
     oracle_pairing_http.mjs oracle_provision.mjs \
     oracle_google_accounts.mjs oracle_google_http.mjs ./

USER 1000:1000
EXPOSE 8096
CMD ["node", "index.mjs"]
