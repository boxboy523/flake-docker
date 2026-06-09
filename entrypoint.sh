#!/bin/sh
export HOME=/home/pn

if [ -z "$NIX_DIR" ]; then
  CACHE=/home/pn/.nix-bin-path
  if [ -f "$CACHE" ]; then
    NIX_DIR=$(cat "$CACHE")
  else
    NIX_BIN=$(find /nix/store -name "nix" -type f -path "*/bin/nix" 2>/dev/null | head -1)
    NIX_DIR=$(dirname "$NIX_BIN")
    echo "$NIX_DIR" > "$CACHE"
  fi
fi

export PATH="$NIX_DIR:$PATH"
exec nix develop /env --command bash
