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

mkdir -p /run/flake-docker
printf '%s\n' "$NIX_DIR" > /run/flake-docker/nix-dir

if [ ! -e /env/flake.nix ]; then
  cp /bootstrap/flake.nix /env/flake.nix
fi

# /env is intentionally agent-managed. The entrypoint runs as root so the
# initial seed would otherwise become root-owned and read-only to pn. Also
# repair volumes created by older images that already contain such a seed.
chown pn:pn /env/flake.nix

if [ "$#" -eq 0 ]; then
  set -- sh
fi

if [ "$1" = "start-sshd" ]; then
  exec /usr/local/bin/start-sshd
fi

exec su-exec pn nix develop /env --command "$@"
