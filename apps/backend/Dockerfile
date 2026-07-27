# Multi-stage build. Produces a deployable artifact from the emitting
# tsconfig.build.json — previously the project had noEmit: true, no build
# script and no container, so there was no path from a green CI run to a
# running server.

FROM node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:22-alpine
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=4000

# Migrations are read from disk at runtime by the file-based runner.
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./package.json
COPY src/db/migrations ./dist/db/migrations

USER node
EXPOSE 4000

# Readiness, not liveness: an instance that cannot reach PostgreSQL must not be
# reported healthy.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||4000)+'/health/ready').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Run migrations as an explicit deploy step before starting:
#   docker run --rm --env-file .env nex-backend npm run migrate
CMD ["node", "dist/index.js"]
