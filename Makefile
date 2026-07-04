.DEFAULT_GOAL := help

# eyrie-flock — a self-hostable stack of AI-agent tools that share one Docker
# network (project `eyrie-flock`). All tools are independent peers; compose
# what you need and nothing more.
F := docker compose --env-file .env -f

# Compose files — each tool is a standalone or overlay file.
OPENCODE := docker/docker-compose.opencode.yml
HEADROOM := docker/docker-compose.headroom.yml
CADDY := docker/docker-compose.caddy.yml
PAPERCLIP := docker/docker-compose.paperclip.yml
HERMES := docker/docker-compose.hermes.yml
AGENTS := docker/docker-compose.agents.yml
OPENCLAW := docker/docker-compose.openclaw.yml
LOCAL_MODELS := docker/docker-compose.local-models.yml
LOCAL_MODELS_GPU := docker/docker-compose.local-models.gpu.yml
LOCAL_MODELS_LLAMACPP := docker/docker-compose.local-models.llamacpp.yml

# Where to symlink the `opencode` command. ~/.local/bin is on most PATHs.
PREFIX ?= $(HOME)/.local/bin
BIN_NAME ?= opencode
SSH_DIR_LOCAL ?= ssh

.PHONY: help onboard setup ssh-key build build-agents up up-all up-tls up-tls-all up-headroom up-headroom-all up-paperclip paperclip-secret paperclip-onboard paperclip-bootstrap-ceo caddy-public-urls up-openclaw openclaw-onboard openclaw-token openclaw-cli up-hermes down-hermes claude-code cursor-agent down down-tls down-tls-all down-headroom down-headroom-all down-paperclip down-openclaw restart logs ps shell auth auth-opencode auth-claude-code auth-paperclip auth-openclaw auth-hermes oc pull update install uninstall up-local-models down-local-models ollama-pull lmstudio-pull

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

onboard: ## Interactive setup wizard: pick tools + providers, configure .env, build & start
	@bash bin/onboard

setup: onboard ## First run: interactive setup wizard (alias for onboard)

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

build: ## Build the opencode image
	$(F) $(OPENCODE) build

build-agents: ## Build the agent CLI images (Claude Code, Cursor Agent)
	$(F) $(OPENCODE) -f $(AGENTS) build

up: ## Start opencode only (detached)
	$(F) $(OPENCODE) up -d
	@echo "Web: http://localhost:$$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 4096)"

up-all: ## Start the full agent stack: opencode + Paperclip + OpenClaw (shared network)
	@$(MAKE) --no-print-directory paperclip-secret
	@$(MAKE) --no-print-directory openclaw-token
	$(F) $(OPENCODE) -f $(PAPERCLIP) -f $(OPENCLAW) up -d
	@sleep 2
	@$(MAKE) --no-print-directory paperclip-onboard
	@echo "opencode:  http://localhost:$$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 4096)"
	@echo "Paperclip: http://localhost:$$(grep -E '^PAPERCLIP_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 3100)"
	@echo "OpenClaw:  http://localhost:$$(grep -E '^OPENCLAW_GATEWAY_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 18789)"

caddy-public-urls: ## Set companion subdomains + public URLs in .env for Caddy domain
	@domain=$$(grep -E '^OPENCODE_DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d ' '); \
	if [ -n "$$domain" ]; then \
		for entry in "PAPERCLIP_DOMAIN=paperclip.$$domain" "PAPERCLIP_PUBLIC_URL=https://paperclip.$$domain" "HERMES_DOMAIN=hermes.$$domain" "HERMES_PUBLIC_URL=https://hermes.$$domain" "OPENCLAW_DOMAIN=openclaw.$$domain" "OPENCLAW_PUBLIC_URL=https://openclaw.$$domain"; do \
			key=$${entry%%=*}; val=$${entry#*=}; \
			if ! grep -qE "^$$key=" .env 2>/dev/null; then \
				echo "$$key=$$val" >> .env; \
				echo "  → $$key set to $$val"; \
			fi; \
		done; \
	else \
		echo "  → OPENCODE_DOMAIN not set — public URLs not configured"; \
	fi

up-tls: ## Start opencode with Caddy + automatic HTTPS (needs OPENCODE_DOMAIN in .env)
	@$(MAKE) --no-print-directory caddy-public-urls
	$(F) $(OPENCODE) -f $(CADDY) up -d
	@echo "Web: https://$$(grep -E '^OPENCODE_DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ')/"

up-tls-all: ## Start the full agent stack with Caddy + HTTPS
	@$(MAKE) --no-print-directory caddy-public-urls
	@$(MAKE) --no-print-directory paperclip-secret
	@$(MAKE) --no-print-directory openclaw-token
	$(F) $(OPENCODE) -f $(CADDY) -f $(PAPERCLIP) -f $(HERMES) -f $(OPENCLAW) up -d
	@sleep 2
	@$(MAKE) --no-print-directory paperclip-onboard
	@domain=$$(grep -E '^OPENCODE_DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d ' '); \
	echo "opencode:   https://$$domain/"; \
	echo "Paperclip:  https://paperclip.$$domain/"; \
	echo "Hermes:     https://hermes.$$domain/"; \
	echo "OpenClaw:   https://openclaw.$$domain/"

up-headroom: ## Start opencode with Headroom proxy (context compression)
	HEADROOM_ENABLED=1 $(F) $(OPENCODE) -f $(HEADROOM) up -d
	@echo "Web: http://localhost:$$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 4096)"
	@echo "Headroom dashboard: http://localhost:$$(grep -E '^HEADROOM_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 8787)"

up-headroom-all: ## Start full agent stack with Headroom (opencode + Paperclip + OpenClaw)
	@$(MAKE) --no-print-directory paperclip-secret
	@$(MAKE) --no-print-directory openclaw-token
	HEADROOM_ENABLED=1 $(F) $(OPENCODE) -f $(PAPERCLIP) -f $(OPENCLAW) -f $(HEADROOM) up -d
	@sleep 2
	@$(MAKE) --no-print-directory paperclip-onboard
	@echo "opencode:  http://localhost:$$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 4096)"
	@echo "Paperclip: http://localhost:$$(grep -E '^PAPERCLIP_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 3100)"
	@echo "OpenClaw:  http://localhost:$$(grep -E '^OPENCLAW_GATEWAY_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 18789)"
	@echo "Headroom:  http://localhost:$$(grep -E '^HEADROOM_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 8787)"

down-headroom: ## Stop Headroom + opencode
	$(F) $(OPENCODE) -f $(HEADROOM) down

down-headroom-all: ## Stop full agent stack + Headroom
	HEADROOM_ENABLED=1 $(F) $(OPENCODE) -f $(PAPERCLIP) -f $(OPENCLAW) -f $(HEADROOM) down

up-paperclip: ## Start Paperclip agent control plane (standalone on port 3100)
	@$(MAKE) --no-print-directory paperclip-secret
	$(F) $(PAPERCLIP) up -d
	@sleep 2
	@$(MAKE) --no-print-directory paperclip-onboard
	@echo "Paperclip board: http://localhost:$$(grep -E '^PAPERCLIP_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 3100)"

down-paperclip: ## Stop Paperclip
	$(F) $(PAPERCLIP) down

openclaw-onboard: ## First run: generate OpenClaw config + auth secret (interactive)
	@$(MAKE) --no-print-directory openclaw-token
	$(F) $(OPENCLAW) run --rm --no-deps --entrypoint node openclaw dist/index.js onboard --mode local --no-install-daemon
	$(F) $(OPENCLAW) run --rm --no-deps --entrypoint node openclaw dist/index.js config set \
		--batch-json '[{"path":"gateway.mode","value":"local"},{"path":"gateway.bind","value":"lan"},{"path":"gateway.controlUi.allowedOrigins","value":["http://localhost:18789","http://127.0.0.1:18789"]}]'
	@echo "OpenClaw is configured and ready."; \
	read -p "Start OpenClaw now? [Y/n] " ans; \
	ans=$${ans:-Y}; \
	case "$$ans" in [Yy]*) $(MAKE) --no-print-directory up-openclaw ;; *) echo "Start it later with: make up-openclaw" ;; esac

up-openclaw: ## Start OpenClaw agent gateway (standalone, Control UI on port 18789)
	@$(MAKE) --no-print-directory openclaw-token
	$(F) $(OPENCLAW) up -d openclaw
	@echo "OpenClaw Control UI: http://localhost:$$(grep -E '^OPENCLAW_GATEWAY_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 18789)"

down-openclaw: ## Stop OpenClaw
	$(F) $(OPENCLAW) down

up-hermes: ## Start Hermes Agent gateway (standalone, web dashboard on port 8642)
	$(F) $(HERMES) up -d
	@echo "Hermes dashboard: http://localhost:$$(grep -E '^HERMES_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 8642)"

down-hermes: ## Stop Hermes
	$(F) $(HERMES) down

# ── Local model servers (Ollama, LM Studio / llmster, llama.cpp) ───────────
# Reads LOCAL_*_ENABLED flags from .env (set by bin/onboard or manually).
define local_model_profiles
$(shell profiles=""; \
  grep -qE '^LOCAL_OLLAMA_ENABLED=1' .env 2>/dev/null && profiles="$$profiles --profile ollama"; \
  grep -qE '^LOCAL_LMSTUDIO_ENABLED=1' .env 2>/dev/null && profiles="$$profiles --profile lmstudio"; \
  grep -qE '^LOCAL_LLAMACPP_ENABLED=1' .env 2>/dev/null && profiles="$$profiles --profile llamacpp"; \
  echo $$profiles)
endef

define local_model_files
$(shell files="-f $(LOCAL_MODELS)"; \
  grep -qE '^LOCAL_LLAMACPP_ENABLED=1' .env 2>/dev/null && files="$$files -f $(LOCAL_MODELS_LLAMACPP)"; \
  grep -qE '^OLLAMA_USE_GPU=1' .env 2>/dev/null && files="$$files -f $(LOCAL_MODELS_GPU)"; \
  echo $$files)
endef

up-local-models: ## Start enabled local model servers (Ollama / LM Studio / llama.cpp)
	@test -f .env || cp .env.example .env
	@if ! grep -qE '^LOCAL_(OLLAMA|LMSTUDIO|LLAMACPP)_ENABLED=1' .env 2>/dev/null; then \
		echo "No LOCAL_*_ENABLED flags in .env — run ./bin/onboard and select local providers, or set them manually."; \
		exit 1; \
	fi
	@if grep -qE '^LOCAL_LLAMACPP_ENABLED=1' .env 2>/dev/null && ! grep -qE '^LLAMACPP_MODEL=.+' .env; then \
		echo "LOCAL_LLAMACPP_ENABLED=1 but LLAMACPP_MODEL is empty — place a .gguf in ./models/ and set LLAMACPP_MODEL in .env"; \
		exit 1; \
	fi
	@bash bin/configure-local-providers
	$(F) $(OPENCODE) $(local_model_files) $(local_model_profiles) up -d
	@grep -qE '^LOCAL_OLLAMA_ENABLED=1' .env 2>/dev/null && \
		echo "Ollama:    http://localhost:$$(grep -E '^OLLAMA_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 11434)"
	@grep -qE '^LOCAL_LMSTUDIO_ENABLED=1' .env 2>/dev/null && \
		echo "LM Studio: http://localhost:$$(grep -E '^LMSTUDIO_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 1234)"
	@grep -qE '^LOCAL_LLAMACPP_ENABLED=1' .env 2>/dev/null && \
		echo "llama.cpp: http://localhost:$$(grep -E '^LLAMACPP_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 8080)"

down-local-models: ## Stop local model servers
	$(F) $(OPENCODE) $(local_model_files) $(local_model_profiles) down

ollama-pull: ## Pull an Ollama model: make ollama-pull MODEL=llama3.1
	@test -n "$(MODEL)" || (echo "Usage: make ollama-pull MODEL=llama3.1" && exit 1)
	docker exec eyrie-ollama ollama pull $(MODEL)

lmstudio-pull: ## Download a model into llmster: make lmstudio-pull MODEL=openai/gpt-oss-20b
	@test -n "$(MODEL)" || (echo "Usage: make lmstudio-pull MODEL=openai/gpt-oss-20b" && exit 1)
	docker exec eyrie-lmstudio lms get $(MODEL)

claude-code: ## Run Claude Code CLI:  make claude-code ARGS="refactor this file"
	$(F) $(OPENCODE) -f $(AGENTS) run --rm claude-code $(ARGS)

cursor-agent: ## Run Cursor Agent CLI:  make cursor-agent ARGS="-p -- 'write tests'"
	$(F) $(OPENCODE) -f $(AGENTS) run --rm cursor-agent $(ARGS)

openclaw-cli: ## Run an OpenClaw CLI command:  make openclaw-cli ARGS="dashboard --no-open"
	$(F) $(OPENCLAW) run --rm openclaw-cli $(ARGS)

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

paperclip-bootstrap-ceo: ## Generate a one-time admin invite URL for first-user sign-in
	@base_url=$$(grep -E '^PAPERCLIP_PUBLIC_URL=' .env 2>/dev/null | cut -d= -f2- | tr -d ' '); \
	[ -z "$$base_url" ] && base_url="http://localhost:$$(grep -E '^PAPERCLIP_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo 3100)"; \
	docker exec eyrie-paperclip pnpm paperclipai auth bootstrap-ceo \
		--data-dir /paperclip --base-url "$$base_url" 2>/dev/null \
		| grep -o 'https\?://[^ ]*invite/[^ ]*' \
		|| echo "Invite not generated — board already has an admin? Try: docker exec eyrie-paperclip pnpm paperclipai auth bootstrap-ceo --data-dir /paperclip --base-url $$base_url"

paperclip-onboard: ## First-run: onboard Paperclip with authenticated mode inside the container
	@cat bin/paperclip-onboard | docker exec -i eyrie-paperclip bash 2>/dev/null \
		|| echo "  → Paperclip container not running (onboard skipped)"

down-tls: ## Stop Caddy + opencode
	$(F) $(OPENCODE) -f $(CADDY) down

down-tls-all: ## Stop full agent stack with Caddy
	$(F) $(OPENCODE) -f $(CADDY) -f $(PAPERCLIP) -f $(HERMES) -f $(OPENCLAW) down

down: ## Stop all services in the eyrie-flock project
	docker compose -p eyrie-flock down --remove-orphans

restart: ## Restart the opencode service
	$(F) $(OPENCODE) restart

logs: ## Follow logs (opencode by default)
	$(F) $(OPENCODE) logs -f

ps: ## Container status (all eyrie-flock services)
	docker compose -p eyrie-flock ps

shell: ## Open a shell inside the opencode container
	$(F) $(OPENCODE) exec opencode bash

auth: ## Configure OAuth / login for all running tools (opencode, Claude Code, Paperclip, OpenClaw, Hermes)
	./bin/auth

auth-opencode: ## OAuth login: opencode subscription providers (Copilot, ChatGPT Plus, etc.)
	./bin/auth opencode

auth-claude-code: ## OAuth login: Claude Code subscription
	./bin/auth claude-code

auth-paperclip: ## Open Paperclip board to configure OAuth / sign-in
	./bin/auth paperclip

auth-openclaw: ## Open OpenClaw Control UI to configure channel auth
	./bin/auth openclaw

auth-hermes: ## Open Hermes dashboard to configure auth
	./bin/auth hermes

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

update: ## Rebuild opencode with the latest release and restart
	$(F) $(OPENCODE) build --no-cache --pull
	$(F) $(OPENCODE) up -d
