#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_IDE_DIR="${CODEX_IDE_DIR:-$ROOT_DIR/../emacs-codex-ide}"
EMACS_EXECUTABLE="${EMACS_EXECUTABLE:-emacs}"

args=(-Q --batch -L "$ROOT_DIR" -L "$ROOT_DIR/tests")
if [[ -d "$CODEX_IDE_DIR" ]]; then
  args+=(-L "$CODEX_IDE_DIR")
fi

while IFS= read -r test_file; do
  args+=(-l "$test_file")
done < <(find "$ROOT_DIR/tests" -maxdepth 1 -type f -name '*-tests.el' | sort)

exec "$EMACS_EXECUTABLE" "${args[@]}" -f ert-run-tests-batch-and-exit
