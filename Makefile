.DEFAULT_GOAL := help

# eyrie-flock — a self-hostable stack of AI-agent tools that share one Docker
# network (project `eyrie-flock`). opencode is the base tool; the rest are
# overlays layered on top of it.
BASE := docker-compose.opencode.yml
COMPOSE := docker compose -f $(BASE)

# Overlay files, per tool.
HEADROOM := docker-compose.headroom.yml
CADDY := docker-compose.caddy.yml
PAPERCLIP := docker-compose.paperclip.yml
OPENCLAW_F := docker-compose.openclaw.yml
OPENCLAW := $(COMPOSE) -f $(OPENCLAW_F)

# Where to symlink the `opencode` command. ~/.local/bin is on most PATHs.
PREFIX ?= $(HOME)/.local/bin
BIN_NAME ?= opencode
SSH_DIR_LOCAL ?= ssh

.PHONY: help setup ssh-key build up up-all up-tls up-headroom up-headroom-all up-paperclip paperclip-secret up-openclaw openclaw-onboard openclaw-token openclaw-cli down down-tls down-headroom down-headroom-all down-paperclip down-openclaw restart logs ps shell auth oc pull update install uninstall

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## First run: create .env, data dirs, and a dedicated git SSH key
	@test -f .env || cp .env.example .env
	@mkdir -p config data projects
	@$(MAKE) --no-print-directory ssh-key
	@echo ""
	@echo "Done. Edit .env (PUID/PGID, OPENCODE_SERVER_PASSWORD), then: make up"

ssh-key: ## Generate a dedicated SSH key for git/GitHub in ./ssh (never copies your personal key)
	@mkdir -p $(SSH_DIR_LOCAL) && chmod 700 $(SSH_DIR_LOCAL)
	@if [ ! -f $(SSH_DIR_LOCAL)/id_ed25519 ]; then \
		ssh-keygen -t ed25519 -N "" -C "opencode-$$(hostname)" -f $(SSH_DIR_LOCAL)/id_ed25519 >/dev/null; \
		echo "Generated $(SSH_DIR_LOCAL)/id_ed25519"; \
	else \
		echo "$(SSH_DIR_LOCAL)/id_ed25519 already exists — keeping it"; \
	fi
	@touch $(SSH_DIR_LOCAL)/known_hosts
	@ssh-keyscan github.com 2>/dev/null >> $(SSH_DIR_LOCAL)/known_hosts || true
	@sort -u $(SSH_DIR_LOCAL)/known_hosts -o $(SSH_DIR_LOCAL)/known_hosts
	@echo ""
	@echo "Add this PUBLIC key to GitHub (Settings > SSH and GPG keys, or a repo Deploy key):"
	@echo "--------------------------------------------------------------------------------"
	@cat $(SSH_DIR_LOCAL)/id_ed25519.pub
	@echo "--------------------------------------------------------------------------------"

build: ## Build the image
	$(COMPOSE) build

up: ## Start opencode only (detached)
	$(COMPOSE) up -d
	@echo "Web: http://localhost:$$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 4096)"

up-all: ## Start the full agent stack: opencode + Paperclip + OpenClaw (shared network)
	@$(MAKE) --no-print-directory paperclip-secret
	@$(MAKE) --no-print-directory openclaw-token
	$(COMPOSE) -f $(PAPERCLIP) -f $(OPENCLAW_F) up -d
	@echo "opencode:  http://localhost:$$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 4096)"
	@echo "Paperclip: http://localhost:$$(grep -E '^PAPERCLIP_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 3100)"
	@echo "OpenClaw:  http://localhost:$$(grep -E '^OPENCLAW_GATEWAY_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 18789)"

up-tls: ## Start opencode with Caddy + automatic HTTPS (needs OPENCODE_DOMAIN in .env)
	$(COMPOSE) -f $(CADDY) up -d
	@echo "Web: https://$$(grep -E '^OPENCODE_DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ')"

up-headroom: ## Start opencode (+ OpenClaw if present) with Headroom proxy
	HEADROOM_ENABLED=1 $(COMPOSE) -f $(HEADROOM) up -d
	@echo "Web: http://localhost:$$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 4096)"
	@echo "Headroom dashboard: http://localhost:$$(grep -E '^HEADROOM_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 8787)"

up-headroom-all: ## Start the full agent stack + Headroom (opencode + Paperclip + OpenClaw)
	@$(MAKE) --no-print-directory paperclip-secret
	@$(MAKE) --no-print-directory openclaw-token
	HEADROOM_ENABLED=1 $(COMPOSE) -f $(PAPERCLIP) -f $(OPENCLAW_F) -f $(HEADROOM) up -d
	@echo "opencode:  http://localhost:$$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 4096)"
	@echo "Paperclip: http://localhost:$$(grep -E '^PAPERCLIP_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 3100)"
	@echo "OpenClaw:  http://localhost:$$(grep -E '^OPENCLAW_GATEWAY_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 18789)"
	@echo "Headroom:  http://localhost:$$(grep -E '^HEADROOM_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 8787)"

down-headroom: ## Stop the stack including Headroom
	$(COMPOSE) -f $(HEADROOM) down

down-headroom-all: ## Stop the full agent stack + Headroom
	HEADROOM_ENABLED=1 $(COMPOSE) -f $(PAPERCLIP) -f $(OPENCLAW_F) -f $(HEADROOM) down

up-paperclip: ## Start opencode + the Paperclip agent control plane (board on port 3100)
	@$(MAKE) --no-print-directory paperclip-secret
	$(COMPOSE) -f $(PAPERCLIP) up -d
	@echo "Web: http://localhost:$$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 4096)"
	@echo "Paperclip board: http://localhost:$$(grep -E '^PAPERCLIP_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 3100)"

down-paperclip: ## Stop the stack including Paperclip
	$(COMPOSE) -f $(PAPERCLIP) down

openclaw-onboard: ## First run: generate OpenClaw config + auth secret (interactive)
	@$(MAKE) --no-print-directory openclaw-token
	$(OPENCLAW) run --rm --no-deps --entrypoint node openclaw dist/index.js onboard --mode local --no-install-daemon
	$(OPENCLAW) run --rm --no-deps --entrypoint node openclaw dist/index.js config set \
		--batch-json '[{"path":"gateway.mode","value":"local"},{"path":"gateway.bind","value":"lan"},{"path":"gateway.controlUi.allowedOrigins","value":["http://localhost:18789","http://127.0.0.1:18789"]}]'
	@echo "Onboarding done. Start it with: make up-openclaw"

up-openclaw: ## Start opencode + the OpenClaw agent gateway (Control UI on port 18789)
	@$(MAKE) --no-print-directory openclaw-token
	$(OPENCLAW) up -d openclaw
	@echo "Web: http://localhost:$$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 4096)"
	@echo "OpenClaw Control UI: http://localhost:$$(grep -E '^OPENCLAW_GATEWAY_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 18789)"

down-openclaw: ## Stop the stack including OpenClaw
	$(OPENCLAW) down

openclaw-cli: ## Run an OpenClaw CLI command:  make openclaw-cli ARGS="dashboard --no-open"
	$(OPENCLAW) run --rm openclaw-cli $(ARGS)

openclaw-token: ## Ensure OPENCLAW_GATEWAY_TOKEN is set in .env (generates one if empty)
	@test -f .env || cp .env.example .env
	@if ! grep -qE '^OPENCLAW_GATEWAY_TOKEN=.+' .env; then \
		token=$$(openssl rand -hex 32); \
		if grep -qE '^OPENCLAW_GATEWAY_TOKEN=' .env; then \
			sed -i "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$$token|" .env; \
		else \
			echo "OPENCLAW_GATEWAY_TOKEN=$$token" >> .env; \
		fi; \
		echo "Generated OPENCLAW_GATEWAY_TOKEN in .env"; \
	fi

paperclip-secret: ## Ensure PAPERCLIP_AUTH_SECRET is set in .env (generates one if empty)
	@test -f .env || cp .env.example .env
	@if ! grep -qE '^PAPERCLIP_AUTH_SECRET=.+' .env; then \
		secret=$$(openssl rand -hex 32); \
		if grep -qE '^PAPERCLIP_AUTH_SECRET=' .env; then \
			sed -i "s|^PAPERCLIP_AUTH_SECRET=.*|PAPERCLIP_AUTH_SECRET=$$secret|" .env; \
		else \
			echo "PAPERCLIP_AUTH_SECRET=$$secret" >> .env; \
		fi; \
		echo "Generated PAPERCLIP_AUTH_SECRET in .env"; \
	fi

down-tls: ## Stop the stack including Caddy
	$(COMPOSE) -f $(CADDY) down

down: ## Stop and remove opencode (and any orphan tools in the project)
	$(COMPOSE) down --remove-orphans

restart: ## Restart the service
	$(COMPOSE) restart

logs: ## Follow logs
	$(COMPOSE) logs -f

ps: ## Container status
	$(COMPOSE) ps

shell: ## Open a shell inside the container
	$(COMPOSE) exec opencode bash

auth: ## Configure a provider/API key (opencode auth login)
	./bin/opencode auth login

oc: ## Run opencode in the container:  make oc ARGS="run 'do X'"
	./bin/opencode $(ARGS)

install: ## Symlink `opencode` onto your PATH (PREFIX=~/.local/bin, BIN_NAME=opencode)
	@mkdir -p "$(PREFIX)"
	@ln -sf "$(CURDIR)/bin/opencode" "$(PREFIX)/$(BIN_NAME)"
	@echo "Linked $(PREFIX)/$(BIN_NAME) -> $(CURDIR)/bin/opencode"
	@command -v "$(BIN_NAME)" >/dev/null 2>&1 && echo "OK: '$(BIN_NAME)' resolves to $$(command -v $(BIN_NAME))" \
		|| echo "NOTE: $(PREFIX) is not on your PATH — add it or use a different PREFIX."

uninstall: ## Remove the symlink created by `make install`
	@rm -f "$(PREFIX)/$(BIN_NAME)" && echo "Removed $(PREFIX)/$(BIN_NAME)"

pull: ## Pull the latest base images
	docker pull node:22-bookworm-slim

update: ## Rebuild with the latest opencode and restart
	$(COMPOSE) build --no-cache --pull
	$(COMPOSE) up -d
