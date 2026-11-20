# The Omarchy version: the Python fetcher and the shell plugin.
# The specs are shared and checked from the repository root (make check).
VENV := .venv
PY := $(VENV)/bin/python
DEPS := $(VENV)/.installed

# Where `make install` puts the fetcher and the shell plugin.
PREFIX := $(HOME)/.local/share/crossroads
PLUGIN_DIR := $(HOME)/.config/omarchy/plugins/georgef.crossroads

.PHONY: test install validate

$(DEPS): pyproject.toml
	python3 -m venv $(VENV)
	$(PY) -m pip install --quiet --disable-pip-version-check -e '.[dev]'
	touch $(DEPS)

# Fixed timezone so the plugin's day boundaries are the same everywhere.
test: $(DEPS)
	$(PY) -m pytest -q
	TZ=America/New_York node --test plugin/tests/*.test.js

# The fetcher is an editable install, so source changes apply on the next fetch.
install:
	python3 -m venv $(PREFIX)/venv
	$(PREFIX)/venv/bin/python -m pip install --quiet --disable-pip-version-check -e .
	mkdir -p $(PLUGIN_DIR)
	rsync -a --delete --exclude tests plugin/ $(PLUGIN_DIR)/
	omarchy plugin validate $(PLUGIN_DIR)
	omarchy-shell shell rescanPlugins
	@# A new plugin is only known after a shell restart, so a first install can't enable it yet.
	@omarchy plugin enable georgef.crossroads || echo "First install: run omarchy restart shell, then omarchy plugin enable georgef.crossroads"

validate:
	@rm -rf /tmp/crossroads-validate/georgef.crossroads && mkdir -p /tmp/crossroads-validate
	@rsync -a --exclude tests plugin/ /tmp/crossroads-validate/georgef.crossroads/
	omarchy plugin validate /tmp/crossroads-validate/georgef.crossroads
