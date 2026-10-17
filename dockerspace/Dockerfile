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
# Steps       1. FROM redis:<REDIS_VERSION>           (.env)
#             2. + python3, a venv in /opt/venv · bash + curl (the agent runs its own signup_with_kms.sh)
#             3. + cache-agent/requirements.txt  (the agent's packages, incl. hvac = kms client)
#
# Output      image mycache-redis:<REDIS_VERSION>
#
# Next        docker compose up -d
# ─────────────────────────────────────────────────────────────────────────────
ARG REDIS_VERSION=7-alpine
ARG REDIS_DIGEST=sha256:520775a41a63e77e06c73e35d2fd9cc15921a609516818796b4ecbb813078bc7
FROM redis:${REDIS_VERSION}@${REDIS_DIGEST}

# bash + curl: the cache-agent runs its own connect_external/kms/signup_with_kms.sh inside the container (TESTSERVER-24)
RUN apk add --no-cache python3 bash curl \
 && python3 -m venv /opt/venv

COPY cache-agent/requirements.txt /tmp/requirements.txt
RUN /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt && rm -f /tmp/requirements.txt
