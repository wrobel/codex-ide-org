# codex-ide-org

Optional Org workflow data for
[emacs-codex-ide](https://github.com/wrobel/emacs-codex-ide).

The package keeps two kinds of status separate:

- Codex IDE owns technical session state such as running, idle, approval, and
  stored.
- Org owns the explicit workflow state such as `PLAN`, `TODO`, `WIP`, `REVIEW`,
  `HOLD`, `DONE`, and `CANCELLED`.

## Data model

The package provides an explicit data model and navigation commands. It never
matches Org tasks heuristically by title or directory.

Linked headings use:

```org
* WIP Add an Org adapter
:PROPERTIES:
:CODEX_THREAD_ID: 019ffa85-41fa-7d92-8276-a269726a2310
:CODEX_CWD: /Users/gunnar/user
:END:
```

`CODEX_THREAD_ID` is canonical. `CODEX_CWD` is only a snapshot and never part
of identity. Duplicate thread IDs remain visible as conflicts; absent IDs are
reported as missing links.

The default file is:

```emacs-lisp
(locate-user-emacs-file "codex-ide/tasks.org")
```

Loading the package does not create that file. Configure another location
before loading when needed:

```emacs-lisp
(setq codex-ide-org-file "/path/to/codex-tasks.org")
(require 'codex-ide-org)
```

For a project-local pilot, resolve one file below each Emacs project root:

```emacs-lisp
(setq codex-ide-org-file-function #'codex-ide-org-project-file
      codex-ide-org-project-file-name "project/tasks.org")
```

Only an explicit task-creation command creates the project file. The package
does not scan every project to build a global Org register. Interactive thread
selection is project-scoped by default; set `codex-ide-org-thread-list-scope`
to `global` to opt back into the complete Codex inventory.

Override individual projects centrally when their layout differs:

```emacs-lisp
(setq codex-ide-org-project-file-alist
      '(("/path/to/special-project/\\'" . "planning/codex-tasks.org")
        ("/path/to/other-project/\\'" . "/absolute/path/tasks.org")))
```

The first matching project-root regular expression wins. Relative file names
are resolved below that project root. For completely custom lookup rules,
replace `codex-ide-org-file-function` with a user-defined function.

The selected workflow sequence is installed buffer-locally only in that file:

```text
PLAN TODO WIP REVIEW HOLD | DONE CANCELLED
```

Other Org files and global TODO settings are not modified.

## Commands

- `M-x codex-ide-org-link-current-heading` chooses a thread from the current
  project and links the current heading.
- `M-x codex-ide-org-unlink-current-heading` removes both link properties after
  confirmation.
- `M-x codex-ide-org-open-thread-at-point` opens the linked Codex thread.
- `M-x codex-ide-org-archive-thread-at-point` archives the linked Codex thread
  without changing its Org workflow state.
- `M-x codex-ide-org-unarchive-thread-at-point` restores the linked Codex
  thread, again without changing Org workflow.
- `M-x codex-ide-org-goto-thread-task` chooses a project thread and jumps to its
  linked task.
- `M-x codex-ide-org-create-thread-task` explicitly creates a new task for an
  unlinked project thread.

Link changes are saved by default. Set `codex-ide-org-save-after-change` to nil
to leave link and unlink changes unsaved. Explicit task creation always creates
and saves the configured file. Missing links report an error; duplicate links
offer an explicit heading choice when navigating and are never silently
collapsed.

## Status integration

Work package 6 adds an optional status-view adapter. Register it explicitly:

```emacs-lisp
(codex-ide-org-register-status-integration)
```

Every row in `M-x codex-ide-status` then shows its compact Org state,
`UNLINKED`, or `DUPLICATE` before the Codex title. The existing technical state
remains unchanged. Other Org-backed metadata can independently use the generic
before- or after-title hooks. On a session row, press `a` to choose an available
Org action:

- go to the linked task;
- set the Org workflow state explicitly;
- create a task when the thread is unlinked.

For repeated classification, stay in either the active or archived status
list and press `C-t`, followed by one workflow key:

- `p` PLAN, `t` TODO, `w` WIP, `r` REVIEW;
- `h` HOLD, `d` DONE, `c` CANCELLED.

For `UNLINKED` rows this creates and saves the project task first, then applies
the selected workflow. Linked tasks are updated in place, and the status list
remains selected. Customize `codex-ide-org-status-workflow-keys` to change the
second-key assignments.

Disable the adapter without changing any Org data:

```emacs-lisp
(codex-ide-org-unregister-status-integration)
```

Codex session events may refresh the display, but no technical state ever
changes an Org workflow keyword. Profile-level activation is intentionally
separate. Global status annotations are disabled by default because resolving
them can read one task file per project; set
`codex-ide-org-annotate-global-status` to non-nil to opt in.

Project status buffers may coexist. Switching the package's lightweight index
between their task files is a silent read operation and does not recursively
refresh every other open status buffer; actual saves and explicit index
rebuilds still notify status views.

In Codex status buffers, `A` is the base package's standalone archive toggle.
Use `M-x codex-ide-status-archived` to find project-local archived sessions and
unarchive them. These operations deliberately do not derive or update Org TODO
keywords.

## Development

The adjacent `emacs-codex-ide` checkout is used automatically for local tests:

```sh
make check
```

The package uses only stock Emacs, Org, and Codex IDE. Additional Org query or
dashboard packages are deliberately not required.

## License

MIT
