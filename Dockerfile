FROM node:22-bookworm-slim

# Tools the agent needs to actually work on repos/projects.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        openssh-client \
        ca-certificates \
        ripgrep \
        fd-find \
        less \
        curl \
        bash \
        tini \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s "$(command -v fdfind)" /usr/local/bin/fd

# opencode CLI (includes the web/serve mode).
ARG OPENCODE_VERSION=latest
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" && npm cache clean --force

# Fixed HOME + explicit XDG dirs so config/data paths are predictable
# regardless of the UID/GID the container runs as.
ENV HOME=/home/opencode \
    XDG_CONFIG_HOME=/home/opencode/.config \
    XDG_DATA_HOME=/home/opencode/.local/share \
    XDG_CACHE_HOME=/home/opencode/.cache

# Create dirs with wide permissions — the real owner comes from the bind mounts
# (host UID), and the container runs as that same UID via compose (user:).
RUN mkdir -p \
        /home/opencode/.config/opencode \
        /home/opencode/.local/share/opencode \
        /home/opencode/.cache \
        /home/opencode/.ssh \
        /projects \
    && chmod -R 777 /home/opencode /projects

WORKDIR /projects

EXPOSE 4096

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
