# syntax=docker/dockerfile:1

# ── Stage 1: install dependencies, including devDependencies ────────────────
# Build tools and test runners are needed to install, but they are not needed to
# run the app. Separating the two stages keeps them out of the final image.
FROM node:22-alpine AS deps

WORKDIR /app

# Copy ONLY the manifests first. This is the single most important Docker build
# optimisation: as long as the manifests are unchanged, this layer is reused from
# cache, so `npm ci` is skipped entirely on rebuilds.
COPY package.json package-lock.json ./

# `npm ci`, not `npm install`: reproducible, and it fails if the lock file and
# package.json disagree.
RUN npm ci

# ── Stage 2: the runtime ────────────────────────────────────────────────────
# A fresh, minimal base. The deps stage's node_modules is NOT here, which is why
# the two stages are separate images.
FROM node:22-alpine AS runtime

WORKDIR /app

# Run as a non-root user. `node` already exists in the official image.
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node build.mjs ./
COPY --chown=node:node src ./src

# Build inside the image, so the artifact ships built rather than requiring a
# build step at run time. Cheap here; for a heavy build, build outside and COPY
# the output instead.
RUN node build.mjs && rm -rf node_modules

# Do not run as root.
USER node

# ENTRYPOINT, not CMD. This matters and it is a real distinction:
#   CMD    ["node", "dist/app.js"]  -> `docker run img Ada` REPLACES the command
#                                     with "Ada", so node tries to load ./Ada
#   ENTRYPOINT ["node", "dist/app.js"] -> `docker run img Ada` APPENDS "Ada", so
#                                     the app receives it as an argument
# For an application container whose behaviour depends on arguments, ENTRYPOINT
# is correct. Use CMD for a default you expect to be overridden wholesale.
ENTRYPOINT ["node", "dist/app.js"]
