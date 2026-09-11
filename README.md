# flake-docker

> Declarative agent sandbox image for NixOS hosts.

## Concept

`flake-docker` keeps two layers deliberately separate:

- a small fixed control plane in the container rootfs (`sh`, `sshd`, `su-exec`, entrypoint logic)
- an agent-managed development environment under `/env`, backed by the host `/nix/store`

The control plane must survive even if the agent breaks `/env/flake.nix`. The mutable toolchain can evolve independently without rebuilding the image.

```text
Host NixOS
├── /nix/store
├── nix daemon
└── Docker
    └── flake-docker
        ├── Alpine rootfs              ← fixed control plane
        ├── /bootstrap/flake.nix       ← initial agent environment seed
        ├── /env/flake.nix             ← persistent, agent managed
        └── /workspace                 ← persistent project state
```

## Canonical image definition

The container image is defined by `image.nix`. There is no Dockerfile.

The image uses a pinned Alpine base and copies statically built control-plane binaries into normal rootfs paths such as `/usr/sbin` and `/sbin`. No Nix store closure is embedded in the image. At runtime, `/nix` is supplied by the NixOS host as a read-only bind mount.

Build the image with:

```bash
nix build .#image
```

Load it into Docker:

```bash
docker load < result
```

The default package is also the image, so this is equivalent:

```bash
nix build
```

## Development shell

The repository dev shell contains tools used to maintain the image definition:

```bash
nix develop
```

In particular it includes `nix-prefetch-docker` for refreshing the pinned Alpine base.

## Agent environment seed

`bootstrap-flake.nix` is copied into the image as `/bootstrap/flake.nix`.

On first start, if `/env/flake.nix` does not exist, the entrypoint copies the bootstrap flake there. After that `/env` is left entirely under user/agent control.

The default seed currently provides:

- Python
- Node.js
- Git
- OpenSSH client tools

The agent can edit `/env/flake.nix` and re-enter the environment with:

```bash
dev
```

or execute directly in the current environment:

```bash
dev rg --version
dev cargo test
```

## Run

Resolve the host Nix binary directory:

```bash
export NIX_DIR=$(dirname "$(readlink -f "$(which nix)")")
```

Basic interactive sandbox:

```bash
docker run --rm -it \
  -v /nix:/nix:ro \
  -v flake-env:/env \
  -v flake-workspace:/workspace \
  -e NIX_DIR="$NIX_DIR" \
  flake-docker:latest
```

The host `/nix` mount provides the actual agent toolchain. The Alpine control plane remains outside `/nix` and does not depend on the agent environment.

## SSH agent access

Generate a client key and persistent container host key on the host:

```bash
mkdir -p .agent-ssh
ssh-keygen -t ed25519 -N '' -f .agent-ssh/client_key
cp .agent-ssh/client_key.pub .agent-ssh/authorized_keys
ssh-keygen -t ed25519 -N '' -f .agent-ssh/ssh_host_ed25519_key
chmod 600 .agent-ssh/client_key .agent-ssh/ssh_host_ed25519_key
```

Start the sandbox with SSH exposed only on host loopback:

```bash
docker run --rm -it \
  -v /nix:/nix:ro \
  -v flake-env:/env \
  -v flake-workspace:/workspace \
  -v "$PWD/.agent-ssh:/run/agent-ssh:ro" \
  -e NIX_DIR="$NIX_DIR" \
  -p 127.0.0.1:2222:2222 \
  flake-docker:latest \
  start-sshd
```

Connect from the host:

```bash
ssh \
  -i .agent-ssh/client_key \
  -p 2222 \
  -o StrictHostKeyChecking=accept-new \
  pn@127.0.0.1
```

SSH sessions are forced through `/usr/local/bin/ssh-session`, start in `/workspace`, and enter `nix develop /env`.

Password login, root login, TCP forwarding, agent forwarding, X11 forwarding, and tunnels are disabled.

## Sharing host files

Host files are never exposed implicitly. Mount only the directories the agent should see:

```bash
-v "$HOME/src/project:/workspace/project"
-v "$HOME/reference:/workspace/reference:ro"
```

This keeps file-access policy in the Docker launch configuration rather than in the agent environment.

## Security boundary

The intended split is:

- rootfs control plane: immutable from the agent's point of view
- `/env`: persistent declarative toolchain controlled by the agent
- `/workspace`: persistent project state
- host `/nix`: read-only store access
- Docker mounts/capabilities/networking: controlled by the human or host configuration

The SSH control plane is intentionally independent from `/env`; breaking the development flake should not remove the recovery path into the container.

Do not expose the Docker socket to the sandbox.

## Refreshing the Alpine base

`image.nix` pins the Alpine base by OCI digest and Nix hash. Refresh both values with:

```bash
nix develop
nix-prefetch-docker \
  --image-name alpine \
  --image-tag <desired-tag> \
  --final-image-name alpine \
  --final-image-tag <desired-tag>
```

Copy the resulting `imageDigest` and `hash` into `image.nix`.

## NixOS integration

The image package is intended to be consumed directly from a NixOS configuration, for example through `virtualisation.oci-containers` with `imageFile = inputs.flake-docker.packages.${pkgs.system}.image`.

That allows `nixos-rebuild` to build/load the image while Docker remains only the runtime.

## Limitations

- currently targets `x86_64-linux`
- expects a NixOS-style host `/nix` store and daemon
- host Nix daemon access remains part of the trust model
- shared store growth can consume host disk space
