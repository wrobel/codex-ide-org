# Add direct workflow classification in status lists

## Task

Allow active and archived Codex IDE status rows to be classified directly,
including rows that do not yet have a linked Org task.

## Approach

- Added a reversible package-owned status-buffer minor mode with a `C-t`
  classification command.
- Mapped a second key to each configured standard workflow state.
- Reused linked tasks and created project-local tasks automatically for
  unlinked rows without opening the Org file.
- Added ERT coverage for archived and active rows, key dispatch, invalid input,
  and integration lifecycle behavior.

## Result

- Both Codex status list types support fast two-key workflow classification.
- `UNLINKED` rows become linked and classified in one operation while point
  remains in the status list.
- The integration remains removable through the existing unregister command.
- `make check` passes with all 39 tests.

## Relevant files

- [Org integration](../../../codex-ide-org.el)
- [ERT tests](../../../tests/codex-ide-org-tests.el)
- [User documentation](../../../README.md)
