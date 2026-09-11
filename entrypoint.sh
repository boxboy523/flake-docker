#!/bin/sh
set -eu

export HOME=/home/pn

if [ -z "${NIX_DIR:-}" ]; then
  CACHE="$HOME/.nix-bin-path"
  if [ -f "$CACHE" ]; then
    NIX_DIR=$(cat "$CACHE")
  else
    NIX_BIN=$(find /nix/store -name nix -type f -path '*/bin/nix' 2>/dev/null | head -1)
    NIX_DIR=$(dirname "$NIX_BIN")
    echo "$NIX_DIR" > "$CACHE"
  fi
fi

export PATH="$NIX_DIR:$PATH"

if [ ! -e /env/flake.nix ]; then
  cp /bootstrap/flake.nix /env/flake.nix
fi

if [ "$#" -eq 0 ]; then
  set -- sh
fi

if [ "$1" = "start-sshd" ]; then
  exec /usr/local/bin/start-sshd
fi

exec su-exec pn nix develop /env --command "$@"
