# Makefile für den Code Guard: führt die Selbsttest-Suiten
# (tests/*/run.sh) nacheinander aus und endet mit Fehler, wenn eine
# Suite misslingt. rule-coverage prüft, ob jede Regel mindestens
# einen Verstoß-Fall hat. Bei Node < 20 (oder fehlendem Node) wird
# check-browser-audit übersprungen.
SHELL := /bin/bash

.PHONY: test rule-coverage

test:
	@failed=0; \
	for script in tests/*/run.sh; do \
		name=$$(basename $$(dirname $$script)); \
		skip=0; \
		if [ "$$name" = "check-browser-audit" ]; then \
			nodemajor=$$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null); \
			if [ -z "$$nodemajor" ]; then skip=1; elif [ "$$nodemajor" -lt 20 ] 2>/dev/null; then skip=1; else skip=0; fi; \
		fi; \
		if [ $$skip -eq 1 ]; then \
			echo "ÜBERSPRUNGEN $$name: Node < 20"; \
			continue; \
		fi; \
		if bash "$$script"; then \
			echo "OK $$name"; \
		else \
			echo "FEHLER $$name"; \
			failed=1; \
		fi; \
	done; \
	[ $$failed -eq 0 ]

rule-coverage:
	bash tests/rule-coverage.sh --strict
