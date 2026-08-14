# AGENTS.md

## Scope

`codex-ide-org` is an optional companion package for `emacs-codex-ide`. Keep
Org workflow state separate from Codex technical session state and do not add
Org dependencies to the base package.

## Development

- Keep the package compatible with stock Emacs, Org, and Codex IDE.
- Do not add `org-ql`, dashboard packages, or other external dependencies
  without an explicit decision.
- Add ERT coverage for every data-model, indexing, linking, or navigation
  change.
- Run `make check` after non-trivial changes.
- Do not create the configured Org task file merely by loading the package.
- Do not commit unless the user explicitly requests it.
