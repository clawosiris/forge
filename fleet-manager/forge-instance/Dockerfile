FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_ENV=production
ENV OPENCLAW_HOME=/home/openclaw/.openclaw
ENV OPENCLAW_CONFIG=/home/openclaw/.openclaw/openclaw.json5

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      gh \
      gnupg \
      jq \
      python3 \
      tini \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g openclaw @openai/codex \
    && useradd --create-home --shell /bin/bash --groups root openclaw \
    && mkdir -p /opt/forge-instance \
    && chown -R openclaw:openclaw /opt/forge-instance /home/openclaw \
    && rm -rf /var/lib/apt/lists/*

COPY workspace /opt/forge-instance/workspace
COPY fleet-manager/forge-instance/openclaw.json5 /opt/forge-instance/openclaw.json5
COPY fleet-manager/forge-instance/entrypoint.sh /usr/local/bin/forge-instance-entrypoint

RUN chmod +x /usr/local/bin/forge-instance-entrypoint

USER openclaw
WORKDIR /home/openclaw/.openclaw/workspace

EXPOSE 18789

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/forge-instance-entrypoint"]
