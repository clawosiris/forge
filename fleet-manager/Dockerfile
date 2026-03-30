FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_ENV=production
ENV OPENCLAW_HOME=/home/openclaw/.openclaw
ENV OPENCLAW_CONFIG=/home/openclaw/.openclaw/openclaw.json5
ENV CONTAINER_HOST=unix:///run/podman/podman.sock

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg \
      jq \
      podman \
      tini \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g openclaw \
    && useradd --create-home --shell /bin/bash --groups root openclaw \
    && mkdir -p /opt/fleet-manager \
    && chown -R openclaw:openclaw /opt/fleet-manager /home/openclaw \
    && rm -rf /var/lib/apt/lists/*

COPY fleet-manager/config/openclaw.json5 /opt/fleet-manager/openclaw.json5
COPY fleet-manager/workspace /opt/fleet-manager/workspace
COPY fleet-manager/entrypoint.sh /usr/local/bin/fleet-manager-entrypoint

RUN chmod +x /usr/local/bin/fleet-manager-entrypoint

USER openclaw
WORKDIR /home/openclaw/.openclaw/workspace

EXPOSE 18799

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/fleet-manager-entrypoint"]
