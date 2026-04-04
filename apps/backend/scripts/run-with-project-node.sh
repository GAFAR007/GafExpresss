#!/bin/sh

set -eu

TARGET_MAJOR="22"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_BIN_DIR="$SCRIPT_DIR/../node_modules/.bin"

if [ -d "$PROJECT_BIN_DIR" ]; then
  PATH="$PROJECT_BIN_DIR:$PATH"
  export PATH
fi

if [ "${1:-}" = "nodemon" ]; then
  shift
  set -- nodemon --no-update-notifier "$@"
fi

current_major=""
if command -v node >/dev/null 2>&1; then
  current_major="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || printf '')"
fi

if [ "$current_major" = "$TARGET_MAJOR" ]; then
  exec "$@"
fi

for candidate in \
  "/opt/homebrew/opt/node@22/bin" \
  "/usr/local/opt/node@22/bin"
do
  if [ -x "$candidate/node" ]; then
    PATH="$candidate:$PATH"
    export PATH
    exec "$@"
  fi
done

printf '%s\n' "Project requires Node $TARGET_MAJOR. Install node@22 or add it to PATH." >&2
exit 1
