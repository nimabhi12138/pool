FROM node:14.21.3-bullseye AS deps

WORKDIR /pool

# Install build toolchain for native addons
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       python3 \
       python3-distutils \
       git \
       libboost-all-dev \
    && rm -rf /var/lib/apt/lists/*

# Update npm to latest v6 to avoid known cb() issues
RUN npm install -g npm@6.14.18

COPY package*.json ./

# npm 6 (bundled with Node 14) uses --production to prune dev deps
ENV npm_config_build_from_source=true

RUN npm config set python /usr/bin/python3 \
    && npm config set fetch-retry-maxtimeout 120000 \
    && npm config set fetch-retries 5 \
    && npm ci --production \
    && npm install --build-from-source cryptoforknote-util bignum

COPY . .

# Ensure native modules are rebuilt against the toolchain we installed
RUN npm rebuild cryptoforknote-util --build-from-source \
    && npm rebuild bignum --build-from-source


FROM node:14.21.3-bullseye

ENV NODE_ENV=production \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    TINI_VERSION=v0.19.0

WORKDIR /pool

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       tini \
       libboost-chrono1.74.0 \
       libboost-filesystem1.74.0 \
       libboost-program-options1.74.0 \
       libboost-system1.74.0 \
       libboost-thread1.74.0 \
       libboost-serialization1.74.0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=deps /pool /pool

# Create non-root user to run the pool
RUN useradd --system --create-home --home-dir /pool --shell /usr/sbin/nologin pool \
    && chown -R pool:pool /pool

USER pool

VOLUME ["/config", "/pool/logs"]

EXPOSE 3336 3337 3338 2117 2119

ENTRYPOINT ["tini", "--"]
CMD ["node", "init.js", "-config=/config/config.json"]
