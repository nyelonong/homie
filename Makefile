.PHONY: switch update fmt show clean help

PROFILE ?= zaki

install: ## Install home-manager
	nix run github:nix-community/home-manager -- switch --flake .#$(PROFILE)

switch: ## Apply config for PROFILE (default: zaki)
	home-manager switch --flake .#$(PROFILE)

update: ## Update flake inputs, then apply
	nix flake update && home-manager switch --flake .#$(PROFILE)

fmt: ## Format all Nix files
	nixfmt *.nix hosts/*.nix

show: ## Inspect the flake outputs
	nix flake show

clean: ## Remove the result symlink
	rm -f result

help: ## List targets
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'
