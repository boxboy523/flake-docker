# flake-docker agent sandbox

Use this container as a persistent, declarative development sandbox.

## State layout

- `/env`: persistent toolchain definition. Edit `/env/flake.nix` and `/env/flake.lock` as needed.
- `/workspace`: persistent project files and repositories.
- `/state`: persistent agent/runtime state such as Remote Desktop Commander pairing and npm cache.
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

## Remote Desktop Commander

Start the remote agent with:

```sh
remote-desktop
```

Its persistent runtime state is stored under `/state`. The launcher uses the Node/npm toolchain from the current `/env` and pins Desktop Commander to a known version.

## Security boundary

You may modify `/env`, `/workspace`, and `/state`. Treat the image, host configuration, mounts, capabilities, and container launch policy as outside your control.

If host editor integration is available, use only its documented bridge or socket API. Do not assume arbitrary host execution is permitted.
