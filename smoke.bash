#!/usr/bin/env bash

if [ -n "${DEBUG:-}" ]; then
  set -x
fi

# bash strict mode
set -euo pipefail

function main() {
  RETRIES=0

  until curl -k -L --fail "https://localhost:${HOST_PORT:-8443}"; do
    RETRIES=$(( RETRIES + 1 ))

    if [ "$RETRIES" -ge 5 ]; then
      docker logs
      exit 1
    fi

    docker ps -a

    sleep 30
  done

}

main
