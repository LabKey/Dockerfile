#!/usr/bin/env bash

if [ -n "${DEBUG:-}" ]; then
  set -x
fi

# bash strict mode
set -euo pipefail

function main() {

  RETRIES=0

  until curl -v -k -L --fail "https://localhost:${HOST_PORT:-8443}"; do
    RETRIES=$(( RETRIES + 1 ))

    if [ "$RETRIES" -ge 5 ]; then
      exit 1
    fi

    sleep 10
  done

}

main
