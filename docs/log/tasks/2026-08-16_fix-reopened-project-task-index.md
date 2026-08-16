# Fix reopened project task index

## Task

Fix the project status view losing an existing Org workflow after the task
buffer was closed, prevent accidental duplicate task creation, and add
project-specific task-file path configuration.

## Approach

- Reproduced the issue using the real project task file and a focused ERT case.
- Traced the failure to dead Org markers retained after killing the task
  buffer while the index still considered the file current.
- Rebuild the file index when its task buffer is no longer live.
- Force task creation to re-read the target file before writing.
- Added a project-root regular-expression alist for per-project path overrides.

## Result

- Reopening `codex-ide-status` after closing the Org buffer still resolves the
  existing workflow and offers navigation/state actions instead of creation.
- An existing on-disk link cannot be duplicated by a stale in-memory index.
- `codex-ide-org-project-file-name` controls the normal relative path and
  `codex-ide-org-project-file-alist` can override individual project roots.
- All 32 ERT tests and the package structural check pass.

## Relevant files

- [Package implementation](../../../codex-ide-org.el)
- [Regression tests](../../../tests/codex-ide-org-tests.el)
- [Configuration examples](../../../README.md)
