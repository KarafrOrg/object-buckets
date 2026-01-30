.PHONY: help
.DEFAULT_GOAL := help

# Chart configuration
CHART_NAME := object-bucket
CHART_VERSION := $(shell grep '^version:' Chart.yaml | awk '{print $$2}')
CHART_REPO_URL ?= https://charts.example.com
CHART_REPO_NAME ?= my-charts

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Display this help message
	@echo "$(BLUE)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

.PHONY: lint
lint: ## Lint the Helm chart
	@echo "$(BLUE)Linting Helm chart...$(NC)"
	@helm lint .
	@echo "$(GREEN)Linting complete$(NC)"

.PHONY: template
template: ## Generate templates with default values
	@echo "$(BLUE)Generating templates...$(NC)"
	@helm template $(CHART_NAME) .
	@echo "$(GREEN)Templates generated$(NC)"

.PHONY: template-debug
template-debug: ## Generate templates with debug output
	@echo "$(BLUE)Generating templates with debug...$(NC)"
	@helm template $(CHART_NAME) . --debug

.PHONY: template-examples
template-examples: ## Generate templates using example values
	@echo "$(BLUE)Generating templates with example values...$(NC)"
	@helm template $(CHART_NAME) . -f values.example.yaml

.PHONY: validate
validate: lint template ## Validate chart (lint + template)
	@echo "$(GREEN)Validation complete$(NC)"

.PHONY: docs
docs: ## Generate chart documentation using helm-docs
	@echo "$(BLUE)Generating documentation...$(NC)"
	@if command -v helm-docs >/dev/null 2>&1; then \
		helm-docs .; \
		echo "$(GREEN)Documentation generated$(NC)"; \
	else \
		echo "$(RED)helm-docs not found. Install it with: brew install norwoodj/tap/helm-docs$(NC)"; \
		exit 1; \
	fi

.PHONY: docs-check
docs-check: ## Check if documentation is up to date
	@echo "$(BLUE)Checking documentation...$(NC)"
	@if command -v helm-docs >/dev/null 2>&1; then \
		helm-docs --dry-run . && echo "$(GREEN)Documentation is up to date$(NC)" || \
		(echo "$(RED)Documentation is out of date. Run 'make docs' to update$(NC)" && exit 1); \
	else \
		echo "$(YELLOW)helm-docs not found, skipping check$(NC)"; \
	fi

.PHONY: package
package: validate ## Package the Helm chart
	@echo "$(BLUE)Packaging Helm chart...$(NC)"
	@helm package .
	@echo "$(GREEN)Chart packaged: $(CHART_NAME)-$(CHART_VERSION).tgz$(NC)"

.PHONY: package-sign
package-sign: validate ## Package and sign the Helm chart
	@echo "$(BLUE)Packaging and signing Helm chart...$(NC)"
	@helm package --sign --key '$(GPG_KEY)' --keyring ~/.gnupg/secring.gpg .
	@echo "$(GREEN)Chart packaged and signed$(NC)"

.PHONY: install
install: ## Install the chart in the current namespace
	@echo "$(BLUE)Installing chart...$(NC)"
	@helm install $(CHART_NAME) .
	@echo "$(GREEN)Chart installed$(NC)"

.PHONY: install-dry-run
install-dry-run: ## Perform a dry-run installation
	@echo "$(BLUE)Performing dry-run installation...$(NC)"
	@helm install $(CHART_NAME) . --dry-run --debug

.PHONY: upgrade
upgrade: ## Upgrade the chart in the current namespace
	@echo "$(BLUE)Upgrading chart...$(NC)"
	@helm upgrade $(CHART_NAME) .
	@echo "$(GREEN)Chart upgraded$(NC)"

.PHONY: uninstall
uninstall: ## Uninstall the chart from the current namespace
	@echo "$(BLUE)Uninstalling chart...$(NC)"
	@helm uninstall $(CHART_NAME)
	@echo "$(GREEN)Chart uninstalled$(NC)"

.PHONY: test
test: ## Run chart tests
	@echo "$(BLUE)Running chart tests...$(NC)"
	@helm test $(CHART_NAME)
	@echo "$(GREEN)Tests complete$(NC)"

.PHONY: clean
clean: ## Clean generated files
	@echo "$(BLUE)Cleaning generated files...$(NC)"
	@rm -f $(CHART_NAME)-*.tgz
	@rm -f $(CHART_NAME)-*.tgz.prov
	@echo "$(GREEN)Cleanup complete$(NC)"

.PHONY: index
index: ## Generate Helm repository index
	@echo "$(BLUE)Generating repository index...$(NC)"
	@helm repo index . --url $(CHART_REPO_URL)
	@echo "$(GREEN)Repository index generated$(NC)"

.PHONY: publish
publish: clean docs validate package ## Full publish workflow (clean, docs, validate, package)
	@echo "$(GREEN)Chart ready for publishing: $(CHART_NAME)-$(CHART_VERSION).tgz$(NC)"
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Upload $(CHART_NAME)-$(CHART_VERSION).tgz to your chart repository"
	@echo "  2. Run 'make index' to update the repository index"
	@echo "  3. Commit and push the updated index.yaml"

.PHONY: publish-oci
publish-oci: validate package ## Publish chart to OCI registry
	@echo "$(BLUE)Publishing chart to OCI registry...$(NC)"
	@if [ -z "$(OCI_REGISTRY)" ]; then \
		echo "$(RED)OCI_REGISTRY environment variable not set$(NC)"; \
		echo "$(YELLOW)Usage: make publish-oci OCI_REGISTRY=oci://registry.example.com/charts$(NC)"; \
		exit 1; \
	fi
	@helm push $(CHART_NAME)-$(CHART_VERSION).tgz $(OCI_REGISTRY)
	@echo "$(GREEN)Chart published to $(OCI_REGISTRY)$(NC)"

.PHONY: version
version: ## Display current chart version
	@echo "$(BLUE)Chart:$(NC) $(CHART_NAME)"
	@echo "$(BLUE)Version:$(NC) $(CHART_VERSION)"

.PHONY: version-bump-patch
version-bump-patch: ## Bump patch version (0.0.X)
	@echo "$(BLUE)Bumping patch version...$(NC)"
	@CURRENT_VERSION=$$(grep '^version:' Chart.yaml | awk '{print $$2}'); \
	IFS='.' read -r MAJOR MINOR PATCH <<< "$$CURRENT_VERSION"; \
	NEW_PATCH=$$((PATCH + 1)); \
	NEW_VERSION="$$MAJOR.$$MINOR.$$NEW_PATCH"; \
	echo "$(YELLOW)Current version: $$CURRENT_VERSION$(NC)"; \
	echo "$(GREEN)New version: $$NEW_VERSION$(NC)"; \
	if [[ "$$OSTYPE" == "darwin"* ]]; then \
		sed -i '' "s/^version: .*/version: $$NEW_VERSION/" Chart.yaml; \
	else \
		sed -i "s/^version: .*/version: $$NEW_VERSION/" Chart.yaml; \
	fi; \
	echo "$(GREEN)Version bumped to $$NEW_VERSION$(NC)"; \
	echo "$(YELLOW)Don't forget to commit:$(NC)"; \
	echo "  git add Chart.yaml && git commit -m 'Bump version to $$NEW_VERSION' && git tag v$$NEW_VERSION"

.PHONY: version-bump-minor
version-bump-minor: ## Bump minor version (0.X.0)
	@echo "$(BLUE)Bumping minor version...$(NC)"
	@CURRENT_VERSION=$$(grep '^version:' Chart.yaml | awk '{print $$2}'); \
	IFS='.' read -r MAJOR MINOR PATCH <<< "$$CURRENT_VERSION"; \
	NEW_MINOR=$$((MINOR + 1)); \
	NEW_VERSION="$$MAJOR.$$NEW_MINOR.0"; \
	echo "$(YELLOW)Current version: $$CURRENT_VERSION$(NC)"; \
	echo "$(GREEN)New version: $$NEW_VERSION$(NC)"; \
	if [[ "$$OSTYPE" == "darwin"* ]]; then \
		sed -i '' "s/^version: .*/version: $$NEW_VERSION/" Chart.yaml; \
	else \
		sed -i "s/^version: .*/version: $$NEW_VERSION/" Chart.yaml; \
	fi; \
	echo "$(GREEN)Version bumped to $$NEW_VERSION$(NC)"; \
	echo "$(YELLOW)Don't forget to commit:$(NC)"; \
	echo "  git add Chart.yaml && git commit -m 'Bump version to $$NEW_VERSION' && git tag v$$NEW_VERSION"

.PHONY: version-bump-major
version-bump-major: ## Bump major version (X.0.0)
	@echo "$(BLUE)Bumping major version...$(NC)"
	@CURRENT_VERSION=$$(grep '^version:' Chart.yaml | awk '{print $$2}'); \
	IFS='.' read -r MAJOR MINOR PATCH <<< "$$CURRENT_VERSION"; \
	NEW_MAJOR=$$((MAJOR + 1)); \
	NEW_VERSION="$$NEW_MAJOR.0.0"; \
	echo "$(YELLOW)Current version: $$CURRENT_VERSION$(NC)"; \
	echo "$(GREEN)New version: $$NEW_VERSION$(NC)"; \
	if [[ "$$OSTYPE" == "darwin"* ]]; then \
		sed -i '' "s/^version: .*/version: $$NEW_VERSION/" Chart.yaml; \
	else \
		sed -i "s/^version: .*/version: $$NEW_VERSION/" Chart.yaml; \
	fi; \
	echo "$(GREEN)Version bumped to $$NEW_VERSION$(NC)"; \
	echo "$(YELLOW)Don't forget to commit:$(NC)"; \
	echo "  git add Chart.yaml && git commit -m 'Bump version to $$NEW_VERSION' && git tag v$$NEW_VERSION"

.PHONY: ci
ci: docs-check validate ## Run CI checks (docs-check, validate)
	@echo "$(GREEN)All CI checks passed$(NC)"

.PHONY: pre-commit
pre-commit: lint docs ## Run pre-commit checks (lint, docs)
	@echo "$(GREEN)Pre-commit checks passed$(NC)"

.PHONY: install-tools
install-tools: ## Install required tools (helm-docs)
	@echo "$(BLUE)Installing required tools...$(NC)"
	@if ! command -v helm-docs >/dev/null 2>&1; then \
		echo "$(BLUE)Installing helm-docs...$(NC)"; \
		if [[ "$$OSTYPE" == "darwin"* ]]; then \
			brew install norwoodj/tap/helm-docs; \
		else \
			echo "$(YELLOW)Please install helm-docs manually: https://github.com/norwoodj/helm-docs$(NC)"; \
		fi \
	else \
		echo "$(GREEN)helm-docs already installed$(NC)"; \
	fi

