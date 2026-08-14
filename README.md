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

The selected workflow sequence is installed buffer-locally only in that file:

```text
PLAN TODO WIP REVIEW HOLD | DONE CANCELLED
```

Other Org files and global TODO settings are not modified.

## Commands

- `M-x codex-ide-org-link-current-heading` chooses a thread from the global
  Codex inventory and links the current heading.
- `M-x codex-ide-org-unlink-current-heading` removes both link properties after
  confirmation.
- `M-x codex-ide-org-open-thread-at-point` opens the linked Codex thread.
- `M-x codex-ide-org-goto-thread-task` chooses a global thread and jumps to its
  linked task.
- `M-x codex-ide-org-create-thread-task` explicitly creates a new task for an
  unlinked global thread.

Link changes are saved by default. Set `codex-ide-org-save-after-change` to nil
to leave link and unlink changes unsaved. Explicit task creation always creates
and saves the configured file. Missing links report an error; duplicate links
offer an explicit heading choice when navigating and are never silently
collapsed.

## Development

The adjacent `emacs-codex-ide` checkout is used automatically for local tests:

```sh
make check
```

The package uses only stock Emacs, Org, and Codex IDE. Additional Org query or
dashboard packages are deliberately not required.

## License

MIT
