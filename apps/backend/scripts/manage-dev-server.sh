#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_BIN_DIR="$SCRIPT_DIR/../node_modules/.bin"
NODEMON_PATTERN="[n]ode $PROJECT_BIN_DIR/nodemon .*server\\.js"

find_backend_nodemon_pids() {
  pgrep -f "$NODEMON_PATTERN" || true
}

print_usage() {
  printf '%s\n' "Usage: ./scripts/manage-dev-server.sh <status|stop|restart>"
}

command_name="${1:-}"

case "$command_name" in
  status)
    pids="$(find_backend_nodemon_pids)"
    if [ -z "$pids" ]; then
      printf '%s\n' "Backend dev server is not running."
      exit 1
    fi

    printf '%s\n' "Backend dev server is running via nodemon (PID(s): $(printf '%s' "$pids" | tr '\n' ' ' | sed 's/[[:space:]]*$//'))."
    ;;

  stop)
    pids="$(find_backend_nodemon_pids)"
    if [ -z "$pids" ]; then
      printf '%s\n' "Backend dev server is not running."
      exit 0
    fi

    for pid in $pids; do
      kill "$pid"
    done

    printf '%s\n' "Stopped backend dev server PID(s): $(printf '%s' "$pids" | tr '\n' ' ' | sed 's/[[:space:]]*$//')."
    ;;

  restart)
    "$0" stop || true
    exec "$SCRIPT_DIR/run-with-project-node.sh" nodemon server.js
    ;;

  *)
    print_usage >&2
    exit 1
    ;;
esac
