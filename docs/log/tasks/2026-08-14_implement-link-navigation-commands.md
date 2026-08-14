# Implement explicit link and navigation commands

## Task

Implement work package 5 in `codex-ide-org`: explicit linking and unlinking,
navigation between Org tasks and Codex threads, and deliberate task creation
for an unlinked global thread.

## Approach and tools

- Used the public global-thread and open-thread APIs from `emacs-codex-ide`.
- Kept the thread ID canonical and treated the stored directory only as a
  snapshot.
- Added interactive commands backed by smaller testable functions.
- Required confirmation before unlinking or replacing an existing link.
- Added ERT coverage with temporary Org files and mocked Codex inventory APIs.

## Results and observations

- Links are never inferred from task titles or working directories.
- One thread cannot be newly linked to a second heading.
- Missing links produce clear errors and duplicate links require an explicit
  heading choice during navigation.
- Only the explicit task-creation command can create the configured task file.
- Workflow annotations are notified after persisted link changes without
  coupling Org status to technical session events.
- `make check` passes all 19 ERT tests and the batch load/parenthesis check.
- Byte compilation completes without warnings on Emacs 30.2.

## Relevant files

- [Package implementation](../../../codex-ide-org.el)
- [ERT tests](../../../tests/codex-ide-org-tests.el)
- [Command documentation](../../../README.md)
