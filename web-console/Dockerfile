# Image runtime du back-office Astro (SSR node standalone) — build amd64.
# Contexte de build = web-console/ (ce dossier).
#   podman build --platform linux/amd64 \
#     --build-arg PUBLIC_API_BASE=http://192.168.1.100:3000 \
#     -t nubia-console:latest -f web-console/Dockerfile web-console
#
# PUBLIC_API_BASE est inliné au BUILD par Astro (variables PUBLIC_*),
# d'où le passage en build-arg.
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG PUBLIC_API_BASE=http://192.168.1.100:3000
ENV PUBLIC_API_BASE=$PUBLIC_API_BASE
RUN npm run build

FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production HOST=0.0.0.0 PORT=4321
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
EXPOSE 4321
CMD ["node", "./dist/server/entry.mjs"]
