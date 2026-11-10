SCRIPTS := hooks/commit-msg hooks/install.sh scripts/*.sh tests/*.sh

.PHONY: test lint setup

test:
	./tests/run.sh

lint:
	shellcheck -x $(SCRIPTS)

# Use this repo's own commit-msg hook (run once per clone).
setup:
	git config core.hooksPath hooks
