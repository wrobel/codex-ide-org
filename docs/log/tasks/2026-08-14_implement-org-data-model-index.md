# Implement Org data model and index

## Task

Create the standalone `codex-ide-org` companion package and implement work
package 4: the Org property model, thread index, and explicit missing and
duplicate link states.

## Approach and tools

- Created a focused stock-Emacs package repository adjacent to
  `emacs-codex-ide`.
- Used `CODEX_THREAD_ID` as canonical identity and `CODEX_CWD` only as a
  directory snapshot.
- Built an in-memory index of thread IDs to live Org heading markers.
- Applied the agreed workflow sequence buffer-locally only to the configured
  Codex task file.
- Rebuild the index on package load, explicit request, configured-file change,
  and save of the configured Org file.
- Added ERT coverage with isolated temporary Org files.

## Results and observations

- Missing, unique, and duplicate links have distinct public states.
- Duplicate entries retain every marker and cannot be mistaken for a unique
  link.
- Parent or planning headings without a thread ID remain valid and are not
  treated as malformed session tasks.
- Loading or rebuilding the package does not create the configured task file.
- The workflow is configured only in the selected task buffer; the global Org
  TODO sequence remains unchanged.
- `make check` passes all 8 ERT tests and the batch load/parenthesis check.
- Linking, unlinking, navigation, and task creation remain scoped to later work
  packages.

## Relevant files

- [Package implementation](../../../codex-ide-org.el)
- [ERT tests](../../../tests/codex-ide-org-tests.el)
- [README](../../../README.md)
