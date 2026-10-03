# ─────────────────────────────────────────────────────────────────────────────
# Dockerfile — mycache's own image: Redis + Python, so the container can fetch its
# own secrets from kms and run cache-agent — offline once built.
#
# What for    redis:7-alpine has no Python. Before, cache-agent/build.sh downloaded it at
#             run time (apk add, internet) and it was lost on every re-create.
#
# Who         docker compose (start.sh) — built ONCE (needs the internet once), then the
#             image is kept and every later start is offline.
#
# How         bash start.sh                          (builds it when missing)
#             docker compose build redis             (rebuild after a requirements change)
#
# Steps       1. FROM redis:<REDIS_VERSION>           (.env)
#             2. + python3, a venv in /opt/venv
#             3. + connect_external/kms/requirements.txt  (hvac — kms client)
#             4. + cache-agent/requirements.txt           (the agent's packages)
#
# Output      image mycache-redis:<REDIS_VERSION>
#
# Next        docker compose up -d
# ─────────────────────────────────────────────────────────────────────────────
ARG REDIS_VERSION=7-alpine
FROM redis:${REDIS_VERSION}

RUN apk add --no-cache python3 \
 && python3 -m venv /opt/venv

COPY connect_external/kms/requirements.txt /tmp/req-kms.txt
COPY cache-agent/requirements.txt          /tmp/req-agent.txt
RUN /opt/venv/bin/pip install --no-cache-dir -r /tmp/req-kms.txt -r /tmp/req-agent.txt \
 && rm -f /tmp/req-*.txt
