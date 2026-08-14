# codex-ide-org

Optional Org workflow data for
[emacs-codex-ide](https://github.com/wrobel/emacs-codex-ide).

The package keeps two kinds of status separate:

- Codex IDE owns technical session state such as running, idle, approval, and
  stored.
- Org owns the explicit workflow state such as `PLAN`, `TODO`, `WIP`, `REVIEW`,
  `HOLD`, `DONE`, and `CANCELLED`.

## Current scope

The first implementation provides only the work-package-4 data model and
index. It does not yet create, link, unlink, or navigate tasks.

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

## Development

The adjacent `emacs-codex-ide` checkout is used automatically for local tests:

```sh
make check
```

The package uses only stock Emacs, Org, and Codex IDE. Additional Org query or
dashboard packages are deliberately not required.

## License

MIT
