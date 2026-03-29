# Forge instance container
# Based on official OpenClaw image, adds coding agents and dev tools
FROM ghcr.io/openclaw/openclaw:main-slim

USER root

# Add development tools and coding agents
RUN apt-get update && apt-get install -y --no-install-recommends \
    gh \
    build-essential \
    python3 \
    jq \
    && npm install -g @anthropic-ai/claude-code @openai/codex \
    && rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /home/node

# Copy Forge config and workspace template
# OpenClaw reads config from ~/.openclaw/openclaw.json
COPY --chown=node:node config/openclaw.json5 .openclaw/openclaw.json
COPY --chown=node:node workspace/ .openclaw/workspace/

# Run gateway in foreground (no systemd in container)
ENTRYPOINT ["openclaw", "gateway"]
