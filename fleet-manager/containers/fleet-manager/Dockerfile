# Fleet Manager container
# Based on official OpenClaw image, adds Podman CLI for managing sibling containers
FROM ghcr.io/openclaw/openclaw:main-slim

USER root

# Add Podman CLI and systemd client for container orchestration
RUN apt-get update && apt-get install -y --no-install-recommends \
    podman \
    jq \
    iproute2 \
    systemd \
    && rm -rf /var/lib/apt/lists/* \
    && usermod -aG root node

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
