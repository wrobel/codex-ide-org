EMACS ?= emacs

.PHONY: test check

test:
	@EMACS_EXECUTABLE="$(EMACS)" bin/run-tests.sh

check: test
	@$(EMACS) -Q --batch -L . -L ../emacs-codex-ide \
		--eval '(progn (load-file "codex-ide-org.el") (check-parens) (message "codex-ide-org check passed"))'
