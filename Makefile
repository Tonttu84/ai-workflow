SCRIPTS := hooks/commit-msg hooks/pre-push hooks/check-commits hooks/check-walkthrough hooks/install.sh scripts/*.sh tests/*.sh

# The first Python 3.10 or later (the pinned pytest needs it) of $PYTHON,
# python and python3 (on some systems python is Python 2); empty when
# there is none.
PY := $(shell for p in "$$PYTHON" python python3; do [ -n "$$p" ] && "$$p" -c 'import sys; sys.exit(sys.version_info < (3, 10))' > /dev/null 2>&1 && { echo "$$p"; break; }; done)

.PHONY: test lint setup python

test: python
	$(PY) -m pytest tests -q
	$(PY) scripts/decisions.py check --base origin/main
	./tests/run.sh

lint:
	shellcheck -x $(SCRIPTS)

# Use this repo's own commit-msg hook and install the pinned test
# dependencies (run once per clone): into the virtualenv when one is
# active, else with --user.
setup: python
	git config core.hooksPath hooks
	@user=--user; \
	if "$(PY)" -c 'import sys; sys.exit(sys.prefix == sys.base_prefix)'; then user=; fi; \
	echo "$(PY) -m pip install $$user -r requirements-dev.txt"; \
	"$(PY)" -m pip install $$user -r requirements-dev.txt || { \
	  echo "make setup: pip could not install requirements-dev.txt. On a Python that is externally managed (PEP 668), make a virtualenv (python3 -m venv .venv, activate it, then make setup again) or install your distribution's pytest (python3-pytest)." >&2; \
	  exit 1; }

python:
	@[ -n "$(PY)" ] || { echo "make: needs Python 3.10 or later: set PYTHON, or put python or python3 on PATH" >&2; exit 2; }
