# Add project-local Org pilot

## Task

Change the Codex/Org pilot from a global task register to project-local task
files, keep the global view optional, and fix the missing workflow annotation
observed after creating a task.

## Approach

- Added a configurable task-file resolver with a stock Emacs `project.el`
  implementation.
- Made interactive thread selection project-scoped by default.
- Resolved status annotations and actions against each row's working directory.
- Kept global annotations opt-in to avoid reading task files across every
  project during the initial pilot.
- Added focused ERT coverage and ran the complete package check.

## Result

- The pilot can store tasks in `<project>/.codex-ide/tasks.org` without creating
  files merely by loading the package.
- A newly created project task immediately resolves to `Workflow: TODO` in the
  project status view.
- Project indexes remain separate and the previous single-file configuration
  remains supported.
- Global aggregation is explicitly deferred; users can still opt into global
  thread selection and annotations.
- `make check` passes all 29 ERT tests plus the structural Lisp check.

## Notable observations

- Codex archive state remains independent of Org workflow state.
- The existing global status view is deliberately not used as the first pilot
  surface because it exhausts the complete non-archived thread inventory.

## Relevant files

- [Package implementation](../../../codex-ide-org.el)
- [ERT tests](../../../tests/codex-ide-org-tests.el)
- [README](../../../README.md)
