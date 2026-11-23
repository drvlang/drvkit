# drvkit

drvkit supplies the Rust command line, dynamic Nix planner, and flake outputs used by the [drvlang builders](https://drvlang.org/languages/). A language repository pins this repository as a source input and provides its package and test builders.

## CLI

```sh
drvpy build -C . -o result
drvpy test -C . api -- -q
drvpy run -C . api -- --help
```

`build`, `test`, and `run` accept an optional target, `-C PROJECT`, and language options as `--options JSON`. Builds link `result` by default. Tests print the realized check path. Programs receive their arguments and return their own exit status.

## Flakes

Single projects use `lib.mkFlake { src = ./.; }`. Monorepos use `lib.mkMonorepoFlake { src = ./.; }` with a root `drvlang.json` like this.

```json
{ "commands": { "api": "apps/api", "worker": "apps/worker" } }
```

An explicit `commands` attribute in Nix takes precedence. Use `nix build .#api`, `nix run .#api -- --help`, or `nix flake check`. The lower-level entry points are `lib.mkPackage`, `lib.mkTest`, and `lib.mkApp`. Projects with multiple binaries can select one using the `program` option.

## Benchmarks

`nix run .#bench -- --runs 5` in a consuming builder realizes its pinned upstream check, finds the derivation Nix actually built, and rebuilds that check for each sample. Times include Nix process startup. Dependencies already in the store stay cached. Use `-- COMMAND ARG ...` to time a separate executable with one warm-up before the measured runs.
