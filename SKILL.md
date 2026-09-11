# flake-docker agent sandbox

Use this container as a persistent, declarative development sandbox.

## State layout

- `/env`: persistent toolchain definition. Edit `/env/flake.nix` and `/env/flake.lock` as needed.
- `/workspace`: persistent project files and repositories.
- other paths: available only when explicitly mounted by the container operator.
- container rootfs: disposable. Do not rely on changes outside persistent or mounted paths.

## Toolchain workflow

SSH and ordinary sessions normally enter the environment defined by `/env/flake.nix`. If you change the flake, use `dev` to enter the updated environment or run a command in it:

```sh
dev
dev rg --version
dev cargo test
```

Prefer adding required development tools to `/env/flake.nix` instead of installing mutable system packages. Keep the environment reproducible with `flake.lock`.

## Recovery mode

If `nix develop /env` cannot construct the environment, SSH falls back to the fixed Alpine control-plane shell instead of locking you out.

Recovery mode is explicit:

```sh
echo "$FLAKE_DOCKER_RECOVERY"
# 1

echo "$FLAKE_DOCKER_RECOVERY_REASON"
# env-unavailable
```

The prompt is also prefixed with `[flake-docker recovery]` for interactive sessions.

When recovery mode is active, inspect and repair `/env/flake.nix` or `/env/flake.lock`, then test the repaired environment with:

```sh
dev
```

or reconnect over SSH. Recovery mode is still inside the same Docker sandbox and runs as `pn`; it does not grant host or Docker privileges.

## Project workflow

Work under `/workspace`. Clone or create repositories there unless another writable project volume is explicitly mounted.

Do not expect host files, credentials, Docker sockets, or other host resources to be available unless they were explicitly exposed by the container launch policy.

## Host integration

SSH is only the transport into this sandbox. It does not grant Docker or host-shell access.

Host directories are visible only when the container operator explicitly bind-mounts them. Treat those mount boundaries and permissions as authoritative.

## Security boundary

You may modify `/env`, `/workspace`, and any explicitly writable mounts. Treat the image, SSH configuration and keys, host configuration, mounts, capabilities, and container launch policy as outside your control.

Do not attempt to access host resources that were not explicitly mounted or otherwise provided to the sandbox.
