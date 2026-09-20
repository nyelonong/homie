.PHONY: install switch update fmt check show clean help
.PHONY: omniwm-deploy omniwm-harvest validate-omniwm test-omniwm test-profiles test-bootstrap
.PHONY: ghostty-deploy ghostty-harvest test-ghostty zed-deploy zed-harvest validate-zed test-zed

PROFILE ?= zaki
NIX_FILES := $(wildcard $(shell git ls-files --cached --others --exclude-standard -- '*.nix'))

install: ## Apply config with the locked Home Manager
	nix run .#home-manager -- switch --flake .#$(PROFILE)

switch: ## Apply config for PROFILE (default: zaki)
	nix run .#home-manager -- switch --flake .#$(PROFILE)

update: ## Update flake inputs, then apply
	nix flake update && $(MAKE) switch PROFILE=$(PROFILE)

fmt: validate-omniwm validate-zed ## Format all Nix files and validate app settings
	nixfmt $(NIX_FILES)

validate-omniwm:
	python3 scripts/validate-omniwm.py

validate-zed:
	python3 -m json.tool apps/zed/settings.json >/dev/null
	python3 -m json.tool apps/zed/cekat-overlay.json >/dev/null

test-omniwm: ## Test OmniWM seed, deployment, and display routing behavior
	python3 -B -m unittest -v tests/test_omniwm_deployment.py tests/test_omniwm_display_routing.py

test-profiles: ## Test profile ownership boundaries
	python3 -B -m unittest -v tests/test_profile_boundaries.py

test-bootstrap: ## Test fresh-machine and rerun behavior
	python3 -B -m unittest -v tests/test_bootstrap.py

test-ghostty: ## Test Ghostty seed and deployment behavior
	python3 -B -m unittest -v tests/test_ghostty_deployment.py

test-zed: ## Test Zed seed, deployment, and harvesting behavior
	python3 -B -m unittest -v tests/test_zed_deployment.py

check: validate-omniwm validate-zed test-omniwm test-zed test-ghostty test-profiles test-bootstrap ## Run repository checks
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

zed-deploy: validate-zed ## Seed Zed with the selected profile's repository settings
	@set -eu; \
	case "$(PROFILE)" in \
	  zaki|zaki@windows) seed=apps/zed/settings.json ;; \
	  zaki@cekat) seed=apps/zed/settings.json; overlay=apps/zed/cekat-overlay.json ;; \
	  *) echo "unsupported PROFILE=$(PROFILE)" >&2; exit 2 ;; \
	esac; \
	live="$$HOME/.config/zed/settings.json"; \
	mkdir -p "$$(dirname "$$live")"; \
	tmp="$$(mktemp "$${live}.tmp.XXXXXX")"; \
	trap 'rm -f "$$tmp"' EXIT HUP INT TERM; \
	if [ "$(PROFILE)" = "zaki@cekat" ]; then \
	  jq -s '.[0] * .[1]' "$${seed}" "$${overlay}" > "$$tmp"; \
	else \
	  jq . "$${seed}" > "$$tmp"; \
	fi; \
	chmod 0644 "$$tmp"; \
	mv -f "$$tmp" "$$live"; \
	trap - EXIT HUP INT TERM

zed-harvest: validate-zed ## Pull live Zed settings back into the selected profile seed
	@set -eu; \
	live="$$HOME/.config/zed/settings.json"; \
	if [ ! -f "$$live" ]; then echo "missing Zed settings: $$live" >&2; exit 1; fi; \
	jq -e 'type == "object"' "$$live" >/dev/null; \
	case "$(PROFILE)" in \
	  zaki|zaki@windows) \
	    if jq -e '(.agent_servers? // {}) | if type == "object" then has("pi-acp") else false end' "$$live" >/dev/null; then \
	      echo "live settings contain Cekat-only agent_servers.pi-acp; use PROFILE=zaki@cekat" >&2; \
	      exit 1; \
	    fi; \
	    tmp="$$(mktemp apps/zed/settings.json.tmp.XXXXXX)"; \
	    trap 'rm -f "$$tmp"' EXIT HUP INT TERM; \
	    jq . "$$live" > "$$tmp"; \
	    chmod 0644 "$$tmp"; \
	    mv -f "$$tmp" apps/zed/settings.json; \
	    trap - EXIT HUP INT TERM ;; \
	  zaki@cekat) \
	    shared_tmp=; \
	    overlay_tmp=; \
	    trap 'rm -f "$$shared_tmp" "$$overlay_tmp"' EXIT HUP INT TERM; \
	    shared_tmp="$$(mktemp apps/zed/settings.json.tmp.XXXXXX)"; \
	    overlay_tmp="$$(mktemp apps/zed/cekat-overlay.json.tmp.XXXXXX)"; \
	    jq 'del(.agent_servers."pi-acp") | if (.agent_servers? | type) == "object" and (.agent_servers | length) == 0 then del(.agent_servers) else . end' "$$live" > "$$shared_tmp"; \
	    if jq -e '(.agent_servers? // {}) | if type == "object" then has("pi-acp") else false end' "$$live" >/dev/null; then \
	      jq '{agent_servers: {"pi-acp": .agent_servers["pi-acp"]}}' "$$live" > "$$overlay_tmp"; \
	    else \
	      printf '{}\\n' > "$$overlay_tmp"; \
	    fi; \
	    chmod 0644 "$$shared_tmp" "$$overlay_tmp"; \
	    mv -f "$$shared_tmp" apps/zed/settings.json; \
	    mv -f "$$overlay_tmp" apps/zed/cekat-overlay.json; \
	    trap - EXIT HUP INT TERM ;; \
	  *) echo "unsupported PROFILE=$(PROFILE)" >&2; exit 2 ;; \
	esac

help: ## List targets
	@grep -E '^[[:alnum:]_-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'
