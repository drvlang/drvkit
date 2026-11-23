# drvkit

drvkit supplies the Rust command line, dynamic Nix planner, and flake outputs used by the [drvlang builders](https://drvlang.org/languages/). A language repository pins this repository as a source input and provides its package and test builders.

## CLI

```sh
drvpy build -C . -o result
drvpy test -C . api -- -q
drvpy run -C . api -- --help
```

`build`, `test`, and `run` accept an optional target, `-C PROJECT`, and language options as `--options JSON`. Builds link `result` by default. Tests print the realized check path. Programs receive their arguments and return their own exit status.

The public package and test outputs use floating content addressing. Nix computes their store paths when it realizes them. Use `nix build --no-link --print-out-paths` to obtain a realized path.

For Nix 2.35, run `bash publish-cache.sh [--upstream READABLE-CACHE] WRITABLE-CACHE TARGET...` after a successful build. Supply the same named installables you built. This copies their build traces, intermediate outputs and build inputs. Use `--upstream https://cache.nixos.org` when consumers can also read that cache. The publisher checks which direct build inputs it already serves, then copies the remaining inputs and their closures. The initial upload can include source trees and build tools. [Monorepo CI example](https://drvlang.org/monorepos/)

`bash tests/cache.sh` restores a dynamic build that uses a project-specific build-time input in a fresh store. It checks the payload with a signed file cache, the standard Nixpkgs cache, and zero build slots.

## Flakes

Pass an explicit file set to `lib.mkFlake`. For a uv project laid out under `src/` with tests under `tests/`, its downstream flake can use the following expression.

```nix
drvpy.lib.mkFlake {
  src = drvpy.lib.projectSource {
    root = ./.;
    files = [ ./pyproject.toml ./uv.lock ./src ./tests ];
  };
}
```

Include any files your build backend reads, such as a README referenced in project metadata. A monorepo uses `lib.mkMonorepoFlake`. Use `srcForTarget = { name, target }: ...` to select each program's required files and shared packages. You can pass a `commands` map directly or include a root `drvlang.json` in the filtered source.

```json
{ "commands": { "api": "apps/api", "worker": "apps/worker" } }
```

An explicit `commands` attribute in Nix takes precedence. Use `nix build .#api`, `nix run .#api -- --help`, or `nix flake check`. The lower-level entry points are `lib.mkPackage`, `lib.mkTest`, and `lib.mkApp`. Projects with multiple binaries can select one using the `program` option.

## Benchmarks

`nix run .#bench -- --runs 5` in a consuming builder warms its pinned upstream check, then runs a fresh benchmark derivation for each sample. A unique trial input only changes the benchmark recipe. Times include Nix process startup. Dependencies already in the store stay cached. Use `-- COMMAND ARG ...` to time a separate executable with one warm-up before the measured runs.
