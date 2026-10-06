.PHONY: install switch update fmt check show clean help
.PHONY: omniwm-deploy omniwm-harvest validate-omniwm test-omniwm test-profiles test-bootstrap
.PHONY: ghostty-deploy ghostty-harvest test-ghostty zed-deploy zed-harvest validate-zed test-zed

.PHONY: herdr-deploy herdr-harvest validate-herdr test-herdr doctor test-doctor brew-bundle

PROFILE ?= zaki
NIX_FILES := $(wildcard $(shell git ls-files --cached --others --exclude-standard -- '*.nix'))

install: ## Apply config with the locked Home Manager
	nix run .#home-manager -- switch --flake .#$(PROFILE)

switch: ## Apply config for PROFILE (default: zaki)
	nix run .#home-manager -- switch --flake .#$(PROFILE)

brew-bundle: ## Install the casks in Brewfile without upgrading installed ones
	brew bundle --file=Brewfile --no-upgrade

update: ## Update flake inputs, then apply
	nix flake update && $(MAKE) switch PROFILE=$(PROFILE)

fmt: validate-omniwm validate-zed validate-herdr ## Format all Nix files and validate app settings
	nixfmt $(NIX_FILES)

validate-omniwm:
	python3 scripts/validate-omniwm.py

validate-zed:
	python3 -m json.tool apps/zed/settings.json >/dev/null

validate-herdr:
	python3 -c 'import pathlib, tomllib; tomllib.loads(pathlib.Path("apps/herdr/config.toml").read_text(encoding="utf-8"))'

test-omniwm: ## Test OmniWM seed and deployment behavior
	python3 -B -m unittest -v tests/test_omniwm_deployment.py

test-profiles: ## Test profile ownership boundaries
	python3 -B -m unittest -v tests/test_profile_boundaries.py

test-bootstrap: ## Test fresh-machine and rerun behavior
	python3 -B -m unittest -v tests/test_bootstrap.py

test-ghostty: ## Test Ghostty seed and deployment behavior
	python3 -B -m unittest -v tests/test_ghostty_deployment.py

test-zed: ## Test Zed seed, deployment, and harvesting behavior
	python3 -B -m unittest -v tests/test_zed_deployment.py

test-herdr: ## Test validated Herdr configuration transfer
	python3 -B -m unittest -v tests/test_herdr_config.py

test-doctor: ## Test the stack health check against simulated system output
	python3 -B -m unittest -v tests/test_doctor.py

doctor: ## Check OmniWM, skhd, Secure Input, the Caps Lock remap, and seed drift (read-only)
	python3 scripts/doctor.py

check: validate-omniwm validate-zed validate-herdr test-omniwm test-zed test-ghostty test-herdr test-doctor test-profiles test-bootstrap ## Run repository checks
	nix fmt -- --check $(NIX_FILES)
	sh -n bootstrap.sh
	nix run nixpkgs#shellcheck -- bootstrap.sh

show: ## Inspect the flake outputs
	nix flake show

clean: ## Remove the result symlink
	rm -f result

omniwm-deploy: ## Push repo OmniWM settings to the live file and restart it (overwrites GUI edits)
	pkill -x OmniWM || true
	@attempts=0; while pgrep -x OmniWM >/dev/null; do \
		attempts=$$((attempts + 1)); \
		if [ "$$attempts" -ge 50 ]; then echo "OmniWM did not stop" >&2; exit 1; fi; \
		sleep 0.1; \
	done
	mkdir -p ~/.config/omniwm
	install -m 0644 apps/omniwm/settings.toml ~/.config/omniwm/settings.toml
	open -a OmniWM

omniwm-harvest: ## Pull live OmniWM settings back into the repo for review
	diff -u apps/omniwm/settings.toml ~/.config/omniwm/settings.toml && echo "no changes" || cp ~/.config/omniwm/settings.toml apps/omniwm/settings.toml
	@echo "Review the diff above (git diff), then commit what you want to keep."

ghostty-deploy: ## Push the repository Ghostty seed into the live config (overwrites live edits)
	mkdir -p ~/.config/ghostty
	install -m 0644 apps/ghostty/config ~/.config/ghostty/config
	@echo "Reload Ghostty with Cmd+Shift+, to apply."

ghostty-harvest: ## Pull live Ghostty edits back into the repository seed for review
	diff -u apps/ghostty/config ~/.config/ghostty/config && echo "no changes" || cp ~/.config/ghostty/config apps/ghostty/config
	@echo "Review the diff above (git diff), then commit what you want to keep."

herdr-deploy: validate-herdr ## Push the repository Herdr seed into the live config (overwrites live edits)
	python3 scripts/herdr-config.py apps/herdr/config.toml "$$HOME/.config/herdr/config.toml"
	@echo "Apply with 'herdr server reload-config', or restart the Herdr client."

herdr-harvest: ## Pull live Herdr edits into the repository seed for review
	python3 scripts/herdr-config.py "$$HOME/.config/herdr/config.toml" apps/herdr/config.toml
	@echo "Review with 'git diff -- apps/herdr/config.toml' before committing."

zed-deploy: validate-zed ## Seed Zed with the shared repository settings
	@set -eu; \
	case "$(PROFILE)" in \
	  zaki|zaki@cekat|zaki@windows) seed=apps/zed/settings.json ;; \
	  *) echo "unsupported PROFILE=$(PROFILE)" >&2; exit 2 ;; \
	esac; \
	live="$$HOME/.config/zed/settings.json"; \
	mkdir -p "$$(dirname "$$live")"; \
	tmp="$$(mktemp "$${live}.tmp.XXXXXX")"; \
	trap 'rm -f "$$tmp"' EXIT HUP INT TERM; \
	jq . "$${seed}" > "$$tmp"; \
	chmod 0644 "$$tmp"; \
	mv -f "$$tmp" "$$live"; \
	trap - EXIT HUP INT TERM

zed-harvest: validate-zed ## Pull live Zed settings back into the shared repository seed
	@set -eu; \
	live="$$HOME/.config/zed/settings.json"; \
	if [ ! -f "$$live" ]; then echo "missing Zed settings: $$live" >&2; exit 1; fi; \
	case "$(PROFILE)" in \
	  zaki|zaki@cekat|zaki@windows) ;; \
	  *) echo "unsupported PROFILE=$(PROFILE)" >&2; exit 2 ;; \
	esac; \
	tmp="$$(mktemp apps/zed/settings.json.tmp.XXXXXX)"; \
	trap 'rm -f "$$tmp"' EXIT HUP INT TERM; \
	jq -se 'if length != 1 or (.[0] | type) != "object" then error("live settings must contain exactly one JSON object") elif (.[0].agent_servers? // {} | if type == "object" then has("pi-acp") else false end) then error("live settings contain agent_servers.pi-acp; remove it before harvesting shared settings") else .[0] end' "$$live" > "$$tmp"; \
	chmod 0644 "$$tmp"; \
	mv -f "$$tmp" apps/zed/settings.json; \
	trap - EXIT HUP INT TERM

help: ## List targets
	@grep -E '^[[:alnum:]_-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'
