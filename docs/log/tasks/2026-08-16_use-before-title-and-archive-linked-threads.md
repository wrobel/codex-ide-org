# Use before-title workflow labels and manage linked thread archives

## Task

Adapt the Org companion package to the new generic before-title status slot and
make the base package's archive operations usable from linked Org headings.

## Approach

- Registered the workflow provider through the before-title hook.
- Kept workflow labels compact so Org tags, priority, effort, and other metadata
  can later use either generic title slot.
- Added explicit archive and unarchive commands at linked Org headings and
  verified that they never mutate Org TODO state.
- Updated ERT coverage and README guidance.

## Result

- Workflow values now appear before the Codex title without a redundant
  `Workflow:` prefix.
- Linked Codex threads can be archived or restored from Org while Org remains
  the sole owner of planning state.
- `make check` passes with all 33 tests.

## Relevant files

- [Org integration](../../../codex-ide-org.el)
- [ERT tests](../../../tests/codex-ide-org-tests.el)
- [User documentation](../../../README.md)
