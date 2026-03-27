# Fleet Manager container
# Based on official OpenClaw image, adds Podman CLI for managing sibling containers
FROM ghcr.io/openclaw/openclaw:main-slim

USER root

# Add Podman CLI for container orchestration
RUN apt-get update && apt-get install -y --no-install-recommends \
    podman \
    jq \
    && rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /home/node

# Copy Fleet Manager config and workspace
COPY --chown=node:node config/ .openclaw/
COPY --chown=node:node workspace/ .openclaw/workspace/

# Podman socket path inside container
ENV CONTAINER_HOST=unix:///run/podman/podman.sock

ENTRYPOINT ["openclaw", "gateway", "start", "--config", "/home/node/.openclaw/openclaw.json5"]
