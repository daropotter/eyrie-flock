FROM node:22-bookworm-slim

# Tools for the agent + rclone for R2 persistence.
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
        rclone \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s "$(command -v fdfind)" /usr/local/bin/fd

ARG OPENCODE_VERSION=latest
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" && npm cache clean --force

ENV HOME=/home/opencode \
    XDG_CONFIG_HOME=/home/opencode/.config \
    XDG_DATA_HOME=/home/opencode/.local/share \
    XDG_CACHE_HOME=/home/opencode/.cache

RUN mkdir -p \
        /home/opencode/.config/opencode \
        /home/opencode/.local/share/opencode \
        /home/opencode/.cache \
        /home/opencode/.ssh \
        /projects

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /projects
EXPOSE 4096

# tini as PID 1 forwards SIGTERM to entrypoint.sh so it can flush state to R2.
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]
