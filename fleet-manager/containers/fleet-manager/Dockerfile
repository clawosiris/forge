FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs npm curl jq podman ca-certificates git python3 && \
    npm install -g openclaw && \
    useradd -m -s /bin/bash openclaw && \
    rm -rf /var/lib/apt/lists/*

USER openclaw
WORKDIR /home/openclaw

COPY --chown=openclaw:openclaw config/ .openclaw/
COPY --chown=openclaw:openclaw workspace/ .openclaw/workspace/

ENV CONTAINER_HOST=unix:///run/podman/podman.sock

ENTRYPOINT ["openclaw", "gateway", "start", "--config", "/home/openclaw/.openclaw/openclaw.json5"]
