# ─────────────────────────────────────────────────────────────────────────────
# Dockerfile — mycache's own image: Redis + Python, so the container can fetch its
# own secrets from kms and run cache-agent — offline once built.
#
# What for    redis:7-alpine has no Python — the cache-agent (the container's entry point,
#             Redis's assistant) needs it. Before, it was downloaded at run time and lost.
#
# Who         docker compose (start.sh) — built ONCE (needs the internet once), then the
#             image is kept and every later start is offline.
#
# How         bash start.sh                          (builds it when missing)
#             docker compose build redis             (rebuild after a requirements change)
#
# Steps       0. stage fluentbit: Fluent Bit v<FLUENT_BIT_VERSION> compiled from its source on the SAME redis
#                base (Alpine = musl has no fluent-bit package; v5 ships for glibc only) — tail in · loki out (LOGAN-29)
#             1. FROM redis:<REDIS_VERSION>           (.env)
#             2. + python3, a venv in /opt/venv · bash + curl (the agent runs its own signup_with_kms.sh)
#                + Fluent Bit's runtime libraries and /usr/local/bin/fluent-bit (the cache-agent starts it)
#             3. + cache-agent/requirements.txt  (the agent's packages, incl. hvac = kms client)
#
# Output      image mycache-redis:<REDIS_VERSION>
#
# Next        docker compose up -d
# ─────────────────────────────────────────────────────────────────────────────
ARG REDIS_VERSION=7-alpine
ARG REDIS_DIGEST=sha256:520775a41a63e77e06c73e35d2fd9cc15921a609516818796b4ecbb813078bc7

# ── Fluent Bit, built once from its pinned source (LOGAN-29) ────────────────────
FROM redis:${REDIS_VERSION}@${REDIS_DIGEST} AS fluentbit
ARG FLUENT_BIT_VERSION=5.1.4
ARG FLUENT_BIT_SHA256=cfdb83fe8912529e70421a4302374fd0695808a33b8a47f8dd748a64a3257a58
RUN apk add --no-cache build-base cmake flex bison linux-headers openssl-dev yaml-dev zlib-dev fts-dev curl
RUN curl -fsSL -o /tmp/fb.tar.gz https://github.com/fluent/fluent-bit/archive/refs/tags/v${FLUENT_BIT_VERSION}.tar.gz \
 && echo "${FLUENT_BIT_SHA256}  /tmp/fb.tar.gz" | sha256sum -c - && tar -xzf /tmp/fb.tar.gz -C /tmp && mv /tmp/fluent-bit-${FLUENT_BIT_VERSION} /tmp/fb
# musl: fts lives in its own library (the final link is C++) · no Kafka / LuaJIT / WASM / systemd — not used here
RUN cd /tmp/fb/build && cmake .. -DCMAKE_BUILD_TYPE=Release -DFLB_RELEASE=On -DFLB_CORO_STACK_SIZE=24576 \
      -DFLB_SHARED_LIB=Off -DFLB_EXAMPLES=Off -DFLB_KAFKA=Off -DFLB_LUAJIT=Off -DFLB_WASM=Off -DFLB_JEMALLOC=Off \
      -DFLB_IN_SYSTEMD=Off -DFLB_TLS=On -DFLB_PREFER_SYSTEM_LIBS=On \
      -DCMAKE_C_STANDARD_LIBRARIES=-lfts -DCMAKE_CXX_STANDARD_LIBRARIES=-lfts >/tmp/cmake.log 2>&1 \
 && make -j"$(nproc)" >/tmp/make.log 2>&1 && strip bin/fluent-bit \
 || { tail -40 /tmp/cmake.log /tmp/make.log; exit 1; }

# ── the image ───────────────────────────────────────────────────────────────────
FROM redis:${REDIS_VERSION}@${REDIS_DIGEST}

# bash + curl: the cache-agent runs its own connect_external/kms/signup_with_kms.sh inside the container (TESTSERVER-24)
# libssl3 … libgcc: what fluent-bit links to
RUN apk add --no-cache python3 bash curl libssl3 yaml zlib fts libstdc++ libgcc \
 && python3 -m venv /opt/venv
COPY --from=fluentbit /tmp/fb/build/bin/fluent-bit /usr/local/bin/fluent-bit

COPY cache-agent/requirements.txt /tmp/requirements.txt
RUN /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt && rm -f /tmp/requirements.txt
