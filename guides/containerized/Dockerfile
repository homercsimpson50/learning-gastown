# Overlay on the upstream gastown image to add keyring support
# for Claude Code credential persistence in containers.
#
# Build:
#   docker build -t gastown:latest -f Dockerfile .
#
# Requires the upstream image to exist first:
#   cd <gastown-src> && docker build -t gastown-base:latest -f Dockerfile .

FROM gastown-base:latest

USER root

# Add D-Bus + GNOME Keyring for Claude Code credential storage (libsecret)
RUN apt-get update && apt-get install -y --no-install-recommends \
    dbus dbus-x11 \
    gnome-keyring \
    libsecret-1-0 \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

USER agent

# Replace entrypoint with one that starts the keyring daemon
# and syncs host settings from the read-only staging mount
COPY --chown=agent:agent docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

WORKDIR /gt

ENTRYPOINT ["tini", "--", "/app/docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
