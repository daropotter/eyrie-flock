# eyrie-flock

A self-hostable, batteries-included **stack of AI-agent tools** that share one
Docker network and work together. Drop it on a VPS (or your laptop) and pick the
pieces you want — a coding agent with a web UI, a token-saving proxy, a task
board where agents run in heartbeats, and an always-on gateway to chat channels.

Nothing is mandatory except the base tool. Each tool is a Compose overlay you
layer on top; bring up any combination with a single `make` command.

## What's in the flock

| Tool | Role | Port | Start |
|------|------|------|-------|
| [**opencode**](https://opencode.ai) | AI coding agent — web UI + CLI, with persistence and attached projects | `4096` | `make up` |
| [**Headroom**](https://github.com/chopratejas/headroom) | Local context-compression proxy in front of the LLM providers (40–95% fewer input tokens) | `8787` | `make up-headroom` |
| [**Paperclip**](https://github.com/paperclipai/paperclip) | AI-agent control plane — a task board where agents pick up issues and run in heartbeats | `3100` | `make up-paperclip` |
| [**OpenClaw**](https://openclaw.ai) | Always-on agent gateway — connects agents to chat channels (WhatsApp, Telegram, Discord, …) | `18789` | `make up-openclaw` |
| **Caddy** | Reverse proxy with automatic HTTPS (Let's Encrypt) in front of opencode | `80/443` | `make up-tls` |

The whole flock at once (opencode + Paperclip + OpenClaw): **`make up-all`**.

> There's also a Cloudflare Containers deploy for opencode alone — see
> [Deploying to Cloudflare](#deploying-opencode-to-cloudflare-containers).

## How the tools fit together

Every tool runs in the same Compose project (**`eyrie-flock`**) on one shared
network, so they reach each other by service name:

- `opencode:4096` — the coding agent's HTTP server
- `headroom:8787` — the compression proxy
- `paperclip:3100` — the task board
- `openclaw:18789` — the agent gateway

Concretely, that means when you run them together:

- **Paperclip / OpenClaw → opencode**: their adapters can drive this repo's
  opencode server at `http://opencode:4096` (or spawn the bundled `opencode` /
  `claude` / `codex` CLIs their images ship with).
- **opencode → Headroom**: opencode's Anthropic/OpenAI traffic is transparently
  routed through `http://headroom:8787` while the Headroom overlay is active.
- **Ports** don't collide (4096 / 8787 / 3100 / 18789+18790 / 80+443) and are all
  bound to `BIND_ADDR` (localhost by default) except Caddy's public 80/443.

Because they're one project, `make down` tears the whole flock down cleanly.

## Requirements

- Docker + the `docker compose` plugin.

## Quick start

```bash
make setup          # creates .env and the config/ data/ projects/ directories
# edit .env:
#   - PUID/PGID = your `id -u` / `id -g`
#   - OPENCODE_SERVER_PASSWORD = set a password (important for network access!)
make build
make up             # opencode starts in the background
make auth           # log in a provider / paste an API key (stored in ./data)
```

opencode's web UI is at `http://localhost:4096`. Basic-auth login: user
`opencode` (or `OPENCODE_SERVER_USERNAME`) + your password.

Add more tools whenever you like — e.g. `make up-paperclip`, `make up-openclaw`,
or everything with `make up-all`.

---

## opencode — the coding agent

Containerized [opencode](https://opencode.ai) in **web** mode (browser + mobile)
with full **persistence** and the ability to run the `opencode` command through
Docker (locally or over SSH).

- **Web UI** (`opencode serve`) on port `4096` — reachable from anywhere,
  including your phone.
- **Persistence**: configuration, API keys, connected providers, the default
  agent, and sessions survive restarts (`./config` and `./data`).
- **Attach projects**: drop or symlink a repo into `./projects` and opencode
  sees it under `/projects`.
- **CLI through Docker**: `bin/opencode ...` runs commands inside the container,
  sharing the same config as the web instance.

### Persistence — where things live

| On the host  | In the container            | What it holds |
|--------------|-----------------------------|---------------|
| `./config`   | `~/.config/opencode`        | `opencode.json`, agents, MCP config |
| `./data`     | `~/.local/share/opencode`   | `auth.json` (API keys), sessions `opencode.db` |
| `./projects` | `/projects`                 | your repositories / working files |

Restarting deletes nothing — everything lives in these directories. Backup =
archive `config/` and `data/`. The other tools persist their own state in named
Docker volumes (`paperclip_data`, `openclaw_home`, `headroom_data`, …).

> Migrating an existing opencode setup from the host? Copy `~/.config/opencode`
> into `./config` and `~/.local/share/opencode` into `./data` (container stopped).

### Attaching projects

Anything under `./projects` is visible to opencode at `/projects`:

```bash
# a new project
git clone git@github.com:owner/repo.git projects/repo

# or attach an existing host directory without copying
ln -s /path/to/my/repo projects/repo
```

> Symlinks only work if their target is also mounted into the container. For
> directories outside `./projects`, add your own volume in
> `docker-compose.opencode.yml`, e.g. `- /home/me/work/myapp:/projects/myapp`.

### Git / GitHub access

`make setup` (or `make ssh-key`) generates a **dedicated** SSH key in `./ssh` and
prints its public half — add it to GitHub (account key, or a per-repo Deploy key).
The container mounts `./ssh` read-only, so git clone/pull/push over SSH works
without ever copying your personal key onto the server. `known_hosts` is
pre-seeded with GitHub's host keys. Prefer HTTPS instead? Set `GH_TOKEN` in `.env`.

### Running `opencode` from the command line

Install it on your PATH so you can type `opencode` from anywhere:

```bash
make install          # symlinks ./bin/opencode -> ~/.local/bin/opencode
```

Then, from any directory:

```bash
opencode                          # TUI
opencode run "fix the failing tests"
opencode auth login               # add a provider/key
opencode models                   # list models
```

`PREFIX` and `BIN_NAME` are configurable:

```bash
sudo make install PREFIX=/usr/local/bin      # available in the default PATH (good for SSH)
make install BIN_NAME=ocd                     # install as `ocd` to keep a native `opencode`
make uninstall                                # remove the symlink
```

The wrapper is **location-independent** (resolves its own path, even through the
symlink) and **directory-aware**:

- Inside the mounted `./projects` tree → runs with the matching `/projects/...`
  working dir, reusing the live web container when it's up.
- Anywhere else → starts a one-off container with the **current directory
  bind-mounted at the same path**, so `opencode` works on whatever repo you're
  standing in — just like the native binary.

Notes:

- **Over SSH**, a non-interactive shell (`ssh host 'opencode ...'`) often uses a
  minimal PATH that excludes `~/.local/bin`. Either install system-wide
  (`sudo make install PREFIX=/usr/local/bin`) or wrap in a login shell
  (`ssh host 'bash -lc "opencode run ..."'`).
- **Shadowing a native install**: installing into an earlier PATH entry makes
  this Docker wrapper take over. Use `BIN_NAME=ocd` to keep both.

### External / mobile access

By default the port is bound to `127.0.0.1` (safe). To expose it more widely:

- **LAN**: set `BIND_ADDR=0.0.0.0` in `.env` and **set** `OPENCODE_SERVER_PASSWORD`.
  Reach it at `http://MACHINE-IP:4096`.
- **Public / internet**: keep `BIND_ADDR=127.0.0.1` and put TLS in front — use
  `make up-tls` (Caddy) or your own reverse proxy → `http://127.0.0.1:4096`.

Always protect the server with a password whenever it listens beyond localhost.

### Updating opencode

```bash
make update          # build --no-cache --pull + up -d
```

Pin a version: set `OPENCODE_VERSION=0.x.y` in `.env` and run `make build`.

---

## Headroom — token-saving proxy

[Headroom](https://github.com/chopratejas/headroom) is a local context-compression
proxy that sits between opencode and the LLM provider and shrinks everything the
agent sends (tool outputs, files, logs, history) — typically **40–95% fewer input
tokens for the same answers**. Everything stays on your machine.

```bash
make up-headroom
# = docker compose -f docker-compose.opencode.yml -f docker-compose.headroom.yml up -d
```

- A `headroom` service runs the proxy on port `8787`.
- opencode is pointed at it via `OPENCODE_CONFIG_CONTENT` — an **inline config
  layer** that overrides the Anthropic/OpenAI provider `baseURL` *only while the
  overlay is active*. Your persisted `./config` is untouched.
- opencode reaches the proxy at `http://headroom:8787`; the port is also
  published on `127.0.0.1:8787` for the live savings dashboard.

Only the **anthropic** and **openai** providers are routed (auto-detected from
the request). Other providers keep talking to their APIs directly.

Tuning (`.env`): `HEADROOM_MODE` (`optimize` default / `cache` / `audit` /
`passthrough`), `HEADROOM_OUTPUT_SHAPER=1` (also trim output tokens),
`HEADROOM_VERSION`. Stop it with `make down-headroom`.

---

## Paperclip — agent control plane

[Paperclip](https://github.com/paperclipai/paperclip) is a self-hosted **AI-agent
control plane** — a task board where agents pick up issues, run in heartbeats,
comment, and coordinate. Its prebuilt image ships the `claude`, `codex` **and
`opencode`** CLIs, so its local (process) adapters can drive agents right inside
the container.

```bash
make up-paperclip
# = docker compose -f docker-compose.opencode.yml -f docker-compose.paperclip.yml up -d
```

- The `paperclip` service runs the control plane on port `3100` and serves its
  web board at `/` (bound to `BIND_ADDR`).
- Shares the network with opencode, so a Paperclip HTTP adapter can reach
  `http://opencode:4096`.
- `make up-paperclip` generates a stable `PAPERCLIP_AUTH_SECRET` into `.env` the
  first time (or set your own with `openssl rand -hex 32`).
- State (embedded SQLite DB, uploads, secrets key, workspace) persists in the
  `paperclip_data` volume.

Tuning (`.env`): `PAPERCLIP_PORT`, `PAPERCLIP_PUBLIC_URL` (set when reached on
something other than `http://localhost:${PAPERCLIP_PORT}`), `PAPERCLIP_VERSION`.
Local adapters reuse the `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` from `.env`.
Stop it with `make down-paperclip`.

---

## OpenClaw — agent gateway

[OpenClaw](https://openclaw.ai) is an always-on **AI-agent gateway**: a single
long-lived process that connects your agents to chat channels (WhatsApp,
Telegram, Discord, Signal, Slack, …) and dispatches agent sessions, with a web
**Control UI** on port `18789`.

It needs a one-time onboarding (generates its config + auth secret), then starts
like the other tools:

```bash
make openclaw-onboard   # once: interactive — generates config, sets bind/origins
make up-openclaw        # start the gateway (detached)
# = docker compose -f docker-compose.opencode.yml -f docker-compose.openclaw.yml up -d openclaw
```

Open the Control UI at `http://localhost:18789` and paste the token — `make
up-openclaw` writes `OPENCLAW_GATEWAY_TOKEN` into `.env` for you (or set your own
with `openssl rand -hex 32`).

- The `openclaw` gateway serves the Control UI on `18789` (bridge `18790`),
  bound to `BIND_ADDR`.
- Config, workspace, and the auth-profile secret persist in the `openclaw_home`
  and `openclaw_secrets` volumes.
- `host.docker.internal` is mapped, so OpenClaw's bundled local-model providers
  can reach a host-side Ollama / LM Studio.

Management CLI:

```bash
make openclaw-cli ARGS="dashboard --no-open"
make openclaw-cli ARGS="channels login"          # e.g. WhatsApp QR
```

Tuning (`.env`): `OPENCLAW_VERSION` (or `OPENCLAW_IMAGE` for Docker Hub
`openclaw/openclaw`), `OPENCLAW_GATEWAY_PORT`, `OPENCLAW_BRIDGE_PORT`,
`OPENCLAW_GATEWAY_BIND` (`lan`/`local`), `OPENCLAW_TZ`. Stop it with
`make down-openclaw`.

---

## Make commands

```
make help        # list commands
make setup       # .env + directories + dedicated git SSH key
make ssh-key     # (re)generate the dedicated git SSH key in ./ssh
make build       # build the opencode image
make up          # start opencode only
make up-all      # start opencode + Paperclip + OpenClaw (shared network)
make up-headroom # opencode + Headroom token-saving proxy
make up-paperclip# opencode + Paperclip control plane
make up-openclaw # opencode + OpenClaw gateway (run `make openclaw-onboard` once first)
make up-tls      # opencode behind Caddy + automatic HTTPS
make down        # stop the whole flock
make down-*      # stop a specific tool overlay (down-headroom/-paperclip/-openclaw/-tls)
make restart     # restart opencode
make logs        # follow logs
make ps          # container status
make shell       # bash inside the opencode container
make auth        # opencode auth login
make oc ARGS=    # any opencode command: make oc ARGS="run 'do X'"
make install     # symlink `opencode` onto your PATH
make uninstall   # remove that symlink
make update      # rebuild opencode with the latest release and restart
```

## Security checklist

- [ ] `OPENCODE_SERVER_PASSWORD` is set when `BIND_ADDR != 127.0.0.1`.
- [ ] Auth secrets (`PAPERCLIP_AUTH_SECRET`, `OPENCLAW_GATEWAY_TOKEN`) are set
      before exposing those tools beyond localhost.
- [ ] `.env`, `config/`, `data/` are gitignored (they are) — never commit keys.
- [ ] SSH keys mounted read-only (`SSH_DIR`, defaults to `~/.ssh`).
- [ ] Front any tool you expose publicly with TLS (`make up-tls` or your own proxy).

## Project layout

```
eyrie-flock/
├── Dockerfile                    # opencode image: node + opencode + git/ssh/ripgrep
├── docker-compose.opencode.yml   # base tool: opencode (web service, volumes, ports)
├── docker-compose.headroom.yml   # overlay: Headroom token-saving proxy
├── docker-compose.paperclip.yml  # overlay: Paperclip agent control plane
├── docker-compose.openclaw.yml   # overlay: OpenClaw agent gateway
├── docker-compose.caddy.yml      # overlay: Caddy reverse proxy + HTTPS
├── .env.example                  # configuration (copy to .env)
├── Makefile                      # shortcuts for every tool + combinations
├── bin/opencode                  # opencode CLI wrapper (exec/run through Docker)
├── deploy/                       # VPS (Hetzner) deploy helpers
├── cloudflare/                   # opencode-only deploy to Cloudflare Containers
├── config/                       # [persistence] opencode configuration
├── data/                         # [persistence] opencode API keys + sessions
└── projects/                     # attached repositories / files
```

## Deploying opencode to Cloudflare Containers

A ready-to-deploy variant lives in [`cloudflare/`](cloudflare/) — a Worker +
Container running **opencode** with configuration/keys/sessions persisted to
**R2** (Cloudflare's container disk is ephemeral). See
[`cloudflare/README.md`](cloudflare/README.md). This variant covers opencode
only; the rest of the flock runs best on a VPS with the Compose setup above.

Rough monthly cost for 24/7 with ~1 agent request/hour: **~$5** if you let it
scale to zero, **~$12–13** if it never sleeps. A small always-on VPS (e.g.
Hetzner CX23, ~€5.5 for 2 vCPU/4 GB) is comparable or cheaper and runs this
repo's Compose setup unchanged with native disk persistence.

## License

[MIT](LICENSE)
