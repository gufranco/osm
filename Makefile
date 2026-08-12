SHELL := /bin/bash
ARTIFACT := dist/osm
SOURCES := lib build.sh install.sh scripts/coverage.sh scripts/set-version.sh
TESTS := test
COVERAGE_DIR := coverage
COVERAGE_MIN := 91

.PHONY: help build fmt fmt-check lint test cover check clean install

help:
	@echo "targets:"
	@echo "  build      concatenate lib/*.sh into $(ARTIFACT)"
	@echo "  fmt        format shell sources with shfmt"
	@echo "  fmt-check  fail when formatting is not applied"
	@echo "  lint       shellcheck at zero warnings"
	@echo "  test       build, then run the bats suite"
	@echo "  cover      run the suite under kcov and enforce $(COVERAGE_MIN)% coverage"
	@echo "  check      fmt-check, lint, test, cover"
	@echo "  install    copy $(ARTIFACT) into a directory on PATH"

build:
	@bash build.sh

fmt:
	shfmt -w -i 2 $(SOURCES) $(TESTS)

fmt-check:
	shfmt -d -i 2 $(SOURCES) $(TESTS)

lint: build
	shellcheck --severity=style --shell=sh -e SC3043 $(ARTIFACT)
	shellcheck --severity=style --shell=bash build.sh install.sh scripts/coverage.sh scripts/set-version.sh scripts/update-formula.sh scripts/publish-formula.sh
	shellcheck --severity=style --shell=bash completions/osm.bash
	shellcheck --severity=style --shell=bash -e SC2154 $(TESTS)/*.bats $(TESTS)/helpers/*.bash

test: build
	bats --print-output-on-failure $(TESTS)

cover: build
	@bash scripts/coverage.sh $(COVERAGE_MIN)

check: fmt-check lint test cover

clean:
	rm -rf $(COVERAGE_DIR) dist $(TESTS)/tmp

install: build
	@bash install.sh
