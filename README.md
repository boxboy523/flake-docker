# flake-docker

> Ultralight Docker container powered by the host's Nix store — no image rebuilds, fully declarative.

## Concept

Traditional Docker containers bundle all dependencies into the image itself — large images, redundant storage, and a rebuild every time you need a new tool.

**flake-docker** takes a different approach:

- The Docker image is a thin Alpine shell (~5MB) with no preinstalled packages
- Packages are served from the host's `/nix/store` via bind mount
- The environment is declared in `flake.nix` — change it and the next container picks it up instantly

```
Host NixOS
├── /nix/store          ← shared read-only with container
├── nix daemon          ← handles package installation
└── Docker
    └── Container (alpine ~5MB)
        ├── /nix        ← mounted from host
        └── /env/flake.nix  ← environment definition
```

## Requirements

- NixOS host with nix daemon running
- Docker

## Usage

### 1. Define your environment

Edit `flake.nix`:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      packages = with nixpkgs.legacyPackages.x86_64-linux; [
        python3
        nodejs
        git
        ripgrep
      ];
    };
  };
}
```

### 2. Build the image

```bash
docker build -t flake-docker .
```

### 3. Run

```bash
export NIX_DIR=$(dirname $(readlink -f $(which nix)))

docker run -it --rm \
  -v /nix:/nix:ro \
  -e NIX_DIR=$NIX_DIR \
  flake-docker
```

### Custom environment via volume

Mount your own `flake.nix` to override the bundled one — no rebuild needed:

```bash
docker run -it --rm \
  -v /nix:/nix:ro \
  -v /path/to/your/flake.nix:/env/flake.nix \
  -e NIX_DIR=$NIX_DIR \
  flake-docker
```

## How it works

The entrypoint locates the nix binary from the mounted store, then drops into a `nix develop` shell defined by `/env/flake.nix`.

```bash
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
```

`NIX_DIR` can be injected at runtime to skip the store scan on startup:

```bash
export NIX_DIR=$(dirname $(readlink -f $(which nix)))
```

## Benefits

- **No image rebuilds** — update `flake.nix`, done
- **Reproducible** — flake inputs pin exact versions
- **Tiny image** — ~5MB, all packages come from the host store
- **No duplication** — shares the host nix store
- **Docker isolation** — filesystem, network, process isolation still apply

## Limitations

- Requires a NixOS host (or any Linux with nix daemon running)
- Not suitable for cloud or multi-host deployments
