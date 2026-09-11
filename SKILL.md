# flake-docker agent sandbox

Use this container as a persistent, declarative development sandbox.

## State layout

- `/env`: persistent toolchain definition. Edit `/env/flake.nix` and `/env/flake.lock` as needed.
- `/workspace`: persistent project files and repositories.
- container rootfs: disposable. Do not rely on changes outside the persistent paths.

## Toolchain workflow

The current shell was created from `/env/flake.nix`. If you change the flake, use `dev` to enter the updated environment or run a command in it:

```sh
dev
dev rg --version
dev cargo test
```

Prefer adding required tools to `/env/flake.nix` instead of installing mutable system packages. Keep the environment reproducible with `flake.lock`.

## Project workflow

Work under `/workspace`. Clone or create repositories there unless another writable project volume is explicitly mounted.

Do not expect host files, credentials, Docker sockets, or other host resources to be available unless they were explicitly exposed by the container launch policy.

## Host integration

Remote control and pairing belong outside this container. A host-side controller may expose a narrow IPC bridge into the sandbox when needed.

Use only documented bridge commands or sockets. Do not assume arbitrary host execution, Docker control, or unrestricted editor access is permitted.

## Security boundary

You may modify `/env` and `/workspace`. Treat the image, host configuration, mounts, capabilities, IPC bridges, and container launch policy as outside your control.

If host editor integration is available, use only its documented bridge or socket API. Do not assume arbitrary host execution is permitted.
