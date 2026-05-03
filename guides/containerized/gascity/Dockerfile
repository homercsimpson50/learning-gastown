# Gas City container image with keyring support for Claude Code credentials.
#
# Build context must be the gascity source repo:
#   cd <gascity-src> && docker build -t gascity:latest \
#       -f ~/code/learning-gastown/guides/containerized/gascity/Dockerfile .
FROM docker/sandbox-templates:claude-code

ARG GO_VERSION=1.25.6

USER root

# Install system dependencies + keyring for Claude Code credential storage.
# Gas City needs: tmux, git, jq, pgrep (procps), lsof, flock (util-linux),
# plus dolt+bd (installed below) for the default beads provider.
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    sqlite3 \
    tmux \
    curl \
    jq \
    procps \
    lsof \
    util-linux \
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

# Install Go from official tarball (apt golang-go is too old for gascity).
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH="/app/gascity/bin:/usr/local/go/bin:/home/agent/go/bin:${PATH}"

# Install beads (bd) and dolt — both required for the default beads provider
# (`gc init` will warn and refuse `gc start` if either is missing).
RUN curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
RUN curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash

# Set up directories. /city is the workspace root inside the container —
# a single Gas City lives there. Keep the dolt data directory on its own
# subpath so we can put it on a Docker volume (see compose) and avoid
# VirtioFS journal corruption when running on macOS.
RUN mkdir -p /app /city /city/.gc /city/.dolt-data && chown -R agent:agent /app /city

# Environment for both shells so `gc` is on PATH for interactive sessions.
RUN echo 'export PATH="/app/gascity/bin:$PATH"' >> /etc/profile.d/gascity.sh && \
    echo 'export PATH="/app/gascity/bin:$PATH"' >> /etc/zsh/zshenv
RUN echo 'export COLORTERM="truecolor"' >> /etc/profile.d/colorterm.sh && \
    echo 'export COLORTERM="truecolor"' >> /etc/zsh/zshenv
RUN echo 'export TERM="xterm-256color"' >> /etc/profile.d/term.sh && \
    echo 'export TERM="xterm-256color"' >> /etc/zsh/zshenv

USER agent

COPY --chown=agent:agent . /app/gascity

# Build the gc binary. Output lives at /app/gascity/bin/gc per the gascity
# Makefile (BUILD_DIR=bin), already on PATH above.
RUN cd /app/gascity && make build

# Custom entrypoint:
#   1. Apply git/dolt config from env vars (every start, idempotent).
#   2. Start D-Bus + GNOME Keyring so Claude Code can store credentials
#      via libsecret (otherwise `claude` re-prompts every container start).
#   3. Sync host ~/.claude into the container's writable home so the
#      Max subscription / OAuth carries over without browser re-login.
#   4. Sync host ~/.config/gh hosts.yml so `git push` works from agents.
#   5. Run `gc init` once to materialize the city scaffold; on subsequent
#      starts, just continue.
RUN cat > /app/docker-entrypoint.sh <<'ENTRY'
#!/bin/sh
set -e

if [ -n "$GIT_USER" ] && [ -n "$GIT_EMAIL" ]; then
    git config --global user.name "$GIT_USER"
    git config --global user.email "$GIT_EMAIL"
    git config --global credential.helper store
    dolt config --global --add user.name "$GIT_USER"
    dolt config --global --add user.email "$GIT_EMAIL"
fi

# --- D-Bus + GNOME Keyring for Claude Code credential storage ---
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

# --- Sync host gh CLI credentials for git push ---
GH_HOST="/home/agent/.config/gh-host"
GH_HOME="/home/agent/.config/gh"
if [ -d "$GH_HOST" ] && [ -f "$GH_HOST/hosts.yml" ]; then
    mkdir -p "$GH_HOME"
    if [ ! -f "$GH_HOME/hosts.yml" ]; then
        cp "$GH_HOST/hosts.yml" "$GH_HOME/hosts.yml"
    fi
    gh auth setup-git 2>/dev/null || true
fi

# --- Initialize the city if not already done ---
# The user controls the provider via GC_PROVIDER (default: claude-code).
# Pass --provider so init runs non-interactively.
if [ ! -f /city/city.toml ]; then
    echo "Initializing Gas City workspace at /city..."
    cd /city && gc init --provider "${GC_PROVIDER:-claude-code}" .
else
    echo "Gas City workspace already initialized at /city."
fi

exec "$@"
ENTRY
RUN chmod +x /app/docker-entrypoint.sh

WORKDIR /city

ENTRYPOINT ["tini", "--", "/app/docker-entrypoint.sh"]

# Default command: run the supervisor in the foreground. This is the
# in-container equivalent of `gc start` (which on the host registers the
# supervisor as a launchd/systemd service — pointless inside a container).
# Override with `docker compose run --rm gascity bash` for a shell.
CMD ["gc", "supervisor", "run"]
