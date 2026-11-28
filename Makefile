# Shared checks. Each platform folder has its own Makefile for its tests and install.
PLATFORMS := omarchy macos
# The TLC command; CI points this at a pinned tla2tools.jar.
TLC ?= tlc

.PHONY: check test

# Model-check every spec against its .cfg. TLC metadata stays out of the repo.
check:
	@set -e; cd specs; for spec in *.tla; do \
		log=/tmp/crossroads-tlc/$${spec%.tla}.log; mkdir -p /tmp/crossroads-tlc; \
		if $(TLC) -workers auto -metadir /tmp/crossroads-tlc/$${spec%.tla} $$spec > $$log 2>&1; \
		then echo "$$spec: ok"; else echo "$$spec: FAILED (see $$log)"; exit 1; fi; \
	done

test:
	@set -e; for platform in $(PLATFORMS); do $(MAKE) -C $$platform test; done
