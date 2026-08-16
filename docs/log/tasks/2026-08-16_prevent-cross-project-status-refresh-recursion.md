# Prevent cross-project status refresh recursion

## Task

Fix a deep Lisp recursion failure when project-scoped Codex status buffers for
different project task files coexist, including a project without a task file.

## Approach

- Traced status annotation reads through the package's single-project Org
  index and its index-updated hook.
- Distinguished silent index switches needed for reads from rebuilds caused by
  actual data changes.
- Added a two-project regression test that verifies lazy index switches retain
  correct links without emitting status refresh notifications.

## Result

- Reading annotations for one project no longer recursively refreshes status
  buffers for every other project.
- Explicit rebuilds and task-file saves retain their existing notification
  behavior.

## Relevant files

- [Org integration](../../../codex-ide-org.el)
- [Regression tests](../../../tests/codex-ide-org-tests.el)
- [User documentation](../../../README.md)
