.PHONY: switch update fmt show clean help omniwm-deploy omniwm-harvest validate-omniwm

PROFILE ?= zaki

install: ## Install home-manager
	nix run github:nix-community/home-manager -- switch --flake .#$(PROFILE)

switch: ## Apply config for PROFILE (default: zaki)
	home-manager switch --flake .#$(PROFILE)

update: ## Update flake inputs, then apply
	nix flake update && home-manager switch --flake .#$(PROFILE)

fmt: validate-omniwm ## Format all Nix files and validate OmniWM settings
	nixfmt *.nix hosts/*.nix

validate-omniwm:
	python3 scripts/validate-omniwm.py

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

help: ## List targets
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'
