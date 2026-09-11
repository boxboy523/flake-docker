# flake-docker

> Ultralight Docker container powered by the host's Nix store — no image rebuilds, fully declarative.

## Concept

Traditional Docker containers bundle all dependencies into the image itself — large images, redundant storage, and a rebuild every time you need a new tool.

**flake-docker** takes a different approach:

- The Docker image is a thin Alpine shell with a small fixed control plane
- Packages are served from the host's `/nix/store`
- The environment is declared in `/env/flake.nix`
- `/env` can be persistent, so humans or agents can evolve their own toolchain without rebuilding the image
- `/workspace` is kept separate from the environment definition
- optional SSH access is provided by the image-level control plane, not by `/env`

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

## SSH agent access

SSH is an optional transport for external agents. The SSH server is installed in the image so access does not depend on the mutable `/env` toolchain.

Generate a client key and persistent container host key on the host:

```bash
mkdir -p .agent-ssh
ssh-keygen -t ed25519 -N '' -f .agent-ssh/client_key
cp .agent-ssh/client_key.pub .agent-ssh/authorized_keys
ssh-keygen -t ed25519 -N '' -f .agent-ssh/ssh_host_ed25519_key
chmod 600 .agent-ssh/client_key .agent-ssh/ssh_host_ed25519_key
```

Start the sandbox with SSH published only on host loopback:

```bash
docker run --rm -it \
  -v /nix:/nix:ro \
  -v flake-env:/env \
  -v flake-workspace:/workspace \
  -v "$PWD/.agent-ssh:/run/agent-ssh:ro" \
  -e NIX_DIR="$NIX_DIR" \
  -p 127.0.0.1:2222:2222 \
  flake-docker start-sshd
```

Connect from the host:

```bash
ssh \
  -i .agent-ssh/client_key \
  -p 2222 \
  -o StrictHostKeyChecking=accept-new \
  pn@127.0.0.1
```

Remote commands are also supported:

```bash
ssh -i .agent-ssh/client_key -p 2222 pn@127.0.0.1 'pwd && git status'
```

SSH sessions start in `/workspace` inside `nix develop /env`. Password login, root login, TCP forwarding, agent forwarding, X11 forwarding, and tunnels are disabled.

Host directories that should be visible to an agent should be explicitly bind-mounted by the human operating Docker. SSH itself does not expose arbitrary host files.

## Agent guide

`SKILL.md` documents the sandbox layout and expected agent workflow. A copy is also installed in the image at:

```text
/etc/flake-docker/SKILL.md
```

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
        openssh
        ripgrep
      ];
    };
  };
}
```

## Agent sandbox use

The image can be used as a persistent development sandbox for an AI agent:

- keep host policy, Docker configuration, SSH keys, and the image outside the agent's control
- give the agent write access to `/env`, `/workspace`, and only explicitly mounted host paths
- let it evolve its toolchain by editing the flake
- keep the host's Nix user untrusted
- avoid exposing the Docker socket inside the sandbox
- publish SSH only to loopback unless remote network access is explicitly intended
- add container-level capability, memory, CPU, and network restrictions as appropriate

The security boundary belongs in the container launch policy and mounted resources, not in `flake.nix`.

## How it works

The entrypoint locates the Nix binary from the mounted store, initializes `/env/flake.nix` from `/bootstrap/flake.nix` only when necessary, then runs ordinary commands as `pn` inside `nix develop /env`.

`start-sshd` is a special image-level command that starts the fixed OpenSSH server. Authenticated SSH sessions are forced through `/usr/local/bin/ssh-session`, which enters `/workspace` and the current `/env` environment.

`NIX_DIR` can be injected at runtime to skip the store scan on startup:

```bash
export NIX_DIR=$(dirname $(readlink -f $(which nix)))
```

## Benefits

- **No image rebuilds** — update the persistent flake instead
- **Self-managed toolchain** — the environment can evolve from inside the sandbox
- **Declarative state** — toolchain changes remain inspectable and reproducible
- **Small image** — development packages come from the host Nix store
- **No duplication** — shares the host store
- **Separated state** — toolchain, workspace, SSH identity, and container rootfs have distinct lifecycles

## Limitations

- Requires a NixOS host (or another Linux host with a compatible Nix daemon/store setup)
- Host Nix daemon access should be treated as part of the trust model
- Shared store growth can consume host disk space
