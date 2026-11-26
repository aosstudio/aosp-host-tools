PYTHON ?= python3
BUILD_JOBS ?= 8
GROUPS := bootstrap generators java
export PYTHON

.PHONY: check fetch build verify $(addprefix build-,$(GROUPS)) $(addprefix verify-,$(GROUPS))

check:
	shellcheck scripts/*.sh
	$(PYTHON) -m ruff format --check scripts
	$(PYTHON) -m ruff check scripts
	$(PYTHON) -m mypy --strict scripts/*.py

fetch:
	$(PYTHON) scripts/inputs.py $(GROUPS)

build: build-bootstrap
	$(MAKE) build-generators build-java

verify: verify-bootstrap verify-generators verify-java

$(addprefix build-,$(GROUPS)): build-%:
	bash scripts/build.sh '$*' '$(BUILD_JOBS)'

$(addprefix verify-,$(GROUPS)): verify-%:
	bash scripts/verify.sh '$*'
