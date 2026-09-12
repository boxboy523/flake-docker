#!/bin/bash
# flake-docker shell initialization for Hermes' Docker terminal backend.
# Hermes sources this file while building its persistent bash environment snapshot.

if [ ! -r /run/flake-docker/nix-dir ]; then
  echo "flake-docker: /run/flake-docker/nix-dir is unavailable" >&2
  return 1 2>/dev/null || exit 1
fi

NIX_DIR=$(cat /run/flake-docker/nix-dir)
export PATH="$NIX_DIR:$PATH"
unset NIX_DIR

eval "$(nix print-dev-env /env)"
