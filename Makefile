VENV := .venv
PY := $(VENV)/bin/python
DEPS := $(VENV)/.installed

# Where `make install` puts the fetcher and the shell plugin.
PREFIX := $(HOME)/.local/share/omaview
PLUGIN_DIR := $(HOME)/.config/omarchy/plugins/georgef.omaview

.PHONY: check test install validate

# Model-check every spec against its .cfg. TLC metadata stays out of the repo.
check:
	@set -e; cd specs; for spec in *.tla; do \
		log=/tmp/omaview-tlc/$${spec%.tla}.log; mkdir -p /tmp/omaview-tlc; \
		if tlc -workers auto -metadir /tmp/omaview-tlc/$${spec%.tla} $$spec > $$log 2>&1; \
		then echo "$$spec: ok"; else echo "$$spec: FAILED (see $$log)"; exit 1; fi; \
	done

$(DEPS): pyproject.toml
	python3 -m venv $(VENV)
	$(PY) -m pip install --quiet --disable-pip-version-check -e '.[dev]'
	touch $(DEPS)

# Fixed timezone so the plugin's day boundaries are the same everywhere.
test: $(DEPS)
	$(PY) -m pytest -q
	TZ=America/New_York node --test plugin/tests/

# The fetcher is an editable install, so source changes apply on the next fetch.
install:
	python3 -m venv $(PREFIX)/venv
	$(PREFIX)/venv/bin/python -m pip install --quiet --disable-pip-version-check -e .
	mkdir -p $(PLUGIN_DIR)
	rsync -a --delete --exclude tests plugin/ $(PLUGIN_DIR)/
	omarchy plugin validate $(PLUGIN_DIR)
	omarchy-shell shell rescanPlugins
	omarchy plugin enable georgef.omaview

validate:
	@rm -rf /tmp/omaview-validate/georgef.omaview && mkdir -p /tmp/omaview-validate
	@rsync -a --exclude tests plugin/ /tmp/omaview-validate/georgef.omaview/
	omarchy plugin validate /tmp/omaview-validate/georgef.omaview
