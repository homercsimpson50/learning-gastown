# Gas Town container image with keyring support for Claude Code credentials.
#
# Build context must be the gastown source repo:
#   cd <gastown-src> && docker build -t gastown:latest \
#       -f ~/learning-gastown/guides/containerized/Dockerfile .
FROM docker/sandbox-templates:claude-code

ARG GO_VERSION=1.25.6

USER root

# Install system dependencies + keyring for Claude Code credential storage
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    sqlite3 \
    tmux \
    curl \
    ripgrep \
    zsh \
    gh \
    netcat-openbsd \
    tini \
    vim \
    dbus dbus-x11 \
    gnome-keyring \
    libsecret-1-0 \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install Go from official tarball (apt golang-go is too old)
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH="/app/gastown:/usr/local/go/bin:/home/agent/go/bin:${PATH}"

# Install beads (bd) and dolt
RUN curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
RUN curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash

# Set up directories
RUN mkdir -p /app /gt /gt/.dolt-data && chown -R agent:agent /app /gt

# Environment setup for bash and zsh
RUN echo 'export PATH="/app/gastown:$PATH"' >> /etc/profile.d/gastown.sh && \
    echo 'export PATH="/app/gastown:$PATH"' >> /etc/zsh/zshenv
RUN echo 'export COLORTERM="truecolor"' >> /etc/profile.d/colorterm.sh && \
    echo 'export COLORTERM="truecolor"' >> /etc/zsh/zshenv
RUN echo 'export TERM="xterm-256color"' >> /etc/profile.d/term.sh && \
    echo 'export TERM="xterm-256color"' >> /etc/zsh/zshenv

USER agent

COPY --chown=agent:agent . /app/gastown

RUN cd /app/gastown && make build

# Write custom entrypoint with keyring startup and host settings sync.
# (Can't COPY from the guide directory since the build context is gastown source.)
RUN cat > /app/docker-entrypoint.sh <<'ENTRY'
#!/bin/sh
set -e

# Re-apply git/dolt config on every start so env var changes take effect
# even when the home volume already exists from a previous run.
if [ -n "$GIT_USER" ] && [ -n "$GIT_EMAIL" ]; then
    git config --global user.name "$GIT_USER"
    git config --global user.email "$GIT_EMAIL"
    git config --global credential.helper store
    dolt config --global --add user.name "$GIT_USER"
    dolt config --global --add user.email "$GIT_EMAIL"
fi

# --- D-Bus + GNOME Keyring for Claude Code credential storage ---
# Claude Code on Linux uses libsecret, which needs a running keyring daemon.
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
        eval "$(dbus-launch --sh-syntax)" 2>/dev/null || true
        export DBUS_SESSION_BUS_ADDRESS
    fi
    eval "$(printf '' | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null)" || true
    export GNOME_KEYRING_CONTROL
    export SSH_AUTH_SOCK
    if [ -n "$CLAUDE_ENV_FILE" ]; then
        cat >> "$CLAUDE_ENV_FILE" <<ENVEOF
export DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
export GNOME_KEYRING_CONTROL="${GNOME_KEYRING_CONTROL:-}"
ENVEOF
    fi
fi

# --- Sync host Claude config into writable home ---
# Host .claude is mounted read-only at /home/agent/.claude-host.
# Syncs settings AND credentials so the container inherits the host's
# auth (Google OAuth / Max subscription) without needing browser login.
CLAUDE_HOST="/home/agent/.claude-host"
CLAUDE_HOME="/home/agent/.claude"
if [ -d "$CLAUDE_HOST" ]; then
    mkdir -p "$CLAUDE_HOME"
    for f in settings.json settings.local.json .credentials.json; do
        if [ -f "$CLAUDE_HOST/$f" ] && [ ! -f "$CLAUDE_HOME/$f" ]; then
            cp "$CLAUDE_HOST/$f" "$CLAUDE_HOME/$f"
        fi
    done
    if [ -d "$CLAUDE_HOST/projects" ] && [ ! -d "$CLAUDE_HOME/projects" ]; then
        cp -r "$CLAUDE_HOST/projects" "$CLAUDE_HOME/projects"
    fi
fi

if [ ! -f /gt/mayor/town.json ]; then
    echo "Initializing Gas Town workspace at /gt..."
    /app/gastown/gt install /gt --git
else
    echo "Refreshing Gas Town workspace at /gt..."
    /app/gastown/gt install /gt --git --force
fi

exec "$@"
ENTRY
RUN chmod +x /app/docker-entrypoint.sh

WORKDIR /gt

ENTRYPOINT ["tini", "--", "/app/docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
