# Fleet Manager container
# Based on official OpenClaw image, adds Podman CLI for managing sibling containers
FROM ghcr.io/openclaw/openclaw:main-slim

USER root

# Add Podman CLI and host-spawn for container orchestration
RUN apt-get update && apt-get install -y --no-install-recommends \
    podman \
    jq \
    iproute2 \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && usermod -aG root node \
    && curl -fsSL -o /usr/local/bin/host-spawn \
       https://github.com/1player/host-spawn/releases/download/v1.6.0/host-spawn-x86_64 \
    && chmod +x /usr/local/bin/host-spawn

USER node
WORKDIR /home/node

# Copy Fleet Manager config and workspace
# OpenClaw reads config from ~/.openclaw/openclaw.json
COPY --chown=node:node config/openclaw.json5 .openclaw/openclaw.json
COPY --chown=node:node workspace/ .openclaw/workspace/

# Podman socket path inside container
ENV CONTAINER_HOST=unix:///run/podman/podman.sock

# Run gateway in foreground (no systemd in container)
ENTRYPOINT ["openclaw", "gateway"]
