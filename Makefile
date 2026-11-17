# The method's Definition of Done gate (docs/method.md). CI runs the same target.

MARKDOWNLINT_VERSION ?= 0.24.0
PYTHON ?= python3

.PHONY: verify lint links method test charts golden

verify: lint links method test charts ## Everything a PR must pass

lint: ## markdownlint with .markdownlint.yaml
	npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) "**/*.md" "#node_modules"

links: ## every relative Markdown link resolves
	$(PYTHON) hack/check_method.py links

method: ## roadmap, planning-doc and ADR rules
	$(PYTHON) hack/check_method.py repo

test: ## tests for the method checks themselves
	$(PYTHON) -m unittest discover -s hack -p 'test_*.py'

charts: ## render tests and CRD validation for the charts (needs helm, yq, go)
	hack/chart-render-tests.sh

golden: ## regenerate the parent golden after an INTENTIONAL chart change
	UPDATE_GOLDEN=1 hack/chart-render-tests.sh
