FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs npm git curl jq gh build-essential python3 ca-certificates && \
    npm install -g openclaw @anthropic/claude-code codex && \
    useradd -m -s /bin/bash openclaw && \
    rm -rf /var/lib/apt/lists/*

USER openclaw
WORKDIR /home/openclaw

COPY --chown=openclaw:openclaw config/ .openclaw/
COPY --chown=openclaw:openclaw workspace/ .openclaw/workspace/

ENTRYPOINT ["openclaw", "gateway", "start", "--config", "/home/openclaw/.openclaw/openclaw.json5"]
