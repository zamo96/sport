FROM node:20-bullseye-slim AS base

WORKDIR /app

# Живые зеркала bullseye разъезжаются: индекс называет версию ca-certificates,
# которой уже нет в пуле, и сборка падает с 404. Образ сам предлагает снимок
# архива — он неизменяемый, поэтому индекс и файлы там всегда согласованы.
# Release-файл снимка просрочен по определению, отсюда Check-Valid-Until=false.
RUN sed -i \
      -e 's|^# deb http://snapshot|deb http://snapshot|' \
      -e 's|^deb http://deb.debian.org|# deb http://deb.debian.org|' \
      /etc/apt/sources.list \
  && apt-get -o Acquire::Check-Valid-Until=false update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

FROM base AS deps

COPY package.json package-lock.json ./
COPY prisma ./prisma

RUN npm ci

FROM base AS builder

ARG NEXT_PUBLIC_MAP_PROVIDER
ARG NEXT_PUBLIC_YANDEX_MAPS_API_KEY

ENV NEXT_PUBLIC_MAP_PROVIDER=$NEXT_PUBLIC_MAP_PROVIDER
ENV NEXT_PUBLIC_YANDEX_MAPS_API_KEY=$NEXT_PUBLIC_YANDEX_MAPS_API_KEY

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN npm run build

FROM base AS runner

ARG NEXT_PUBLIC_MAP_PROVIDER
ARG NEXT_PUBLIC_YANDEX_MAPS_API_KEY

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3002
ENV NEXT_PUBLIC_MAP_PROVIDER=$NEXT_PUBLIC_MAP_PROVIDER
ENV NEXT_PUBLIC_YANDEX_MAPS_API_KEY=$NEXT_PUBLIC_YANDEX_MAPS_API_KEY

COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/package-lock.json ./package-lock.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/src ./src
COPY --from=builder /app/docs/import ./docs/import
COPY --from=builder /app/tsconfig.json ./tsconfig.json
COPY --from=builder /app/next.config.mjs ./next.config.mjs

EXPOSE 3002

CMD ["npm", "run", "start"]
