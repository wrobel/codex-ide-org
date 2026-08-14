# Implement workflow status annotations and actions

## Task

Implement work package 6 in `codex-ide-org`: display the separate Org workflow
state in global Codex session rows and offer context-sensitive workflow
actions.

## Approach and tools

- Used the public annotation and action registry from `emacs-codex-ide`.
- Rendered a labelled workflow value independently of technical session state.
- Registered separate actions for navigation, explicit task creation, and
  manual Org TODO changes.
- Added symmetric registration and unregistration without deleting Org data.
- Added ERT coverage for annotations, action predicates, workflow transitions,
  and technical-event separation.

## Results and observations

- Linked rows show their Org keyword; missing and duplicate links are visibly
  distinguished.
- Available actions depend on link state and use the explicit work-package-5
  commands.
- Technical Codex status is neither read as nor mapped to an Org workflow.
- Status refresh after index changes does not mutate task state.
- Profile activation remains deliberately scoped to work package 7.
- `make check` passes all 25 ERT tests and the batch load/parenthesis check.
- Checkdoc and byte compilation complete without warnings on Emacs 30.2.

## Relevant files

- [Package implementation](../../../codex-ide-org.el)
- [ERT tests](../../../tests/codex-ide-org-tests.el)
- [Status integration documentation](../../../README.md)
