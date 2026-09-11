# flake-docker

> Ultralight Docker container powered by the host's Nix store — no image rebuilds, fully declarative.

## Concept

Traditional Docker containers bundle all dependencies into the image itself — large images, redundant storage, and a rebuild every time you need a new tool.

**flake-docker** takes a different approach:

- The Docker image is a thin Alpine shell with no fixed toolchain
- Packages are served from the host's `/nix/store`
- The environment is declared in `/env/flake.nix`
- `/env` can be persistent, so humans or agents can evolve their own toolchain without rebuilding the image
- `/workspace` is kept separate from the environment definition

```text
Host NixOS
├── /nix/store
├── nix daemon
└── Docker
    └── Container
        ├── /bootstrap/flake.nix  ← immutable seed
        ├── /env/flake.nix        ← persistent, user/agent managed
        └── /workspace            ← persistent project state
```

## Requirements

- NixOS host with nix daemon running
- Docker

## Build

```bash
docker build -t flake-docker .
```

## Run

```bash
export NIX_DIR=$(dirname $(readlink -f $(which nix)))

docker run -it --rm \
  -v /nix:/nix:ro \
  -e NIX_DIR=$NIX_DIR \
  flake-docker
```

With no persistent `/env`, the bundled `flake.nix` is copied in at startup.

## Persistent self-managed environment

Use named volumes when the environment itself should survive container recreation:

```bash
docker run -it --rm \
  -v /nix:/nix:ro \
  -v flake-env:/env \
  -v flake-workspace:/workspace \
  -e NIX_DIR=$NIX_DIR \
  flake-docker
```

On the first run, `/bootstrap/flake.nix` seeds `/env/flake.nix`. After that, `/env` is left untouched.

This means the container can add or remove packages by editing `/env/flake.nix`, then enter the updated environment with:

```bash
dev
```

Or run one command in the updated environment:

```bash
dev rg --version
dev cargo test
```

The environment definition is persistent and declarative rather than hidden in a mutable container image.

## Agent guide

`SKILL.md` documents the sandbox layout and expected agent workflow. A copy is also installed in the image at:

```text
/etc/flake-docker/SKILL.md
```

## Host-side control plane

Remote control, pairing, and authentication should live outside this container. A host-side controller can expose a narrow IPC bridge into the sandbox when remote agent access is needed.

Keep the controller itself restricted and avoid giving it direct Docker socket access. Prefer a dedicated Unix socket or similarly constrained bridge that only targets this sandbox.

Editor integration can follow the same pattern: expose a small read-mostly RPC surface instead of arbitrary host-side evaluation.

## Non-interactive commands

Arguments are forwarded through `nix develop`, so the same image works for interactive and agent-driven use:

```bash
docker run --rm \
  -v /nix:/nix:ro \
  -v flake-env:/env \
  -v flake-workspace:/workspace \
  -e NIX_DIR=$NIX_DIR \
  flake-docker python --version
```

## Custom bootstrap environment

The repository `flake.nix` is only the seed used when `/env/flake.nix` does not exist. Change it to define the initial environment for newly-created volumes.

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

## Agent sandbox use

The image can be used as a persistent development sandbox for an AI agent:

- keep host policy, Docker configuration, remote control, and the image outside the agent's control
- give the agent write access to `/env` and `/workspace`
- let it evolve its toolchain by editing the flake
- keep the host's Nix user untrusted
- avoid exposing the Docker socket inside the sandbox
- add container-level capability, memory, CPU, and network restrictions as appropriate
- expose host functionality only through narrow, documented IPC bridges

The security boundary belongs in the container launch policy and bridge policy, not in `flake.nix`.

## How it works

The entrypoint locates the Nix binary from the mounted store, initializes `/env/flake.nix` from `/bootstrap/flake.nix` only when necessary, then runs the requested command inside `nix develop /env`.

`NIX_DIR` can be injected at runtime to skip the store scan on startup:

```bash
export NIX_DIR=$(dirname $(readlink -f $(which nix)))
```

## Benefits

- **No image rebuilds** — update the persistent flake instead
- **Self-managed toolchain** — the environment can evolve from inside the sandbox
- **Declarative state** — toolchain changes remain inspectable and reproducible
- **Tiny image** — packages come from the host Nix store
- **No duplication** — shares the host store
- **Separated state** — toolchain, workspace, and container rootfs have distinct lifecycles

## Limitations

- Requires a NixOS host (or another Linux host with a compatible Nix daemon/store setup)
- Host Nix daemon access should be treated as part of the trust model
- Shared store growth can consume host disk space
