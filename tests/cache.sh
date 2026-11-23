#!/usr/bin/env bash
# Test a signed build trace on a runner with no build slots or warm outputs.
set -euo pipefail
umask 077
scratch=$(mktemp -d)
cleanup() {
  find "$scratch" -type d -exec chmod u+w {} +
  rm -r "$scratch"
}
trap cleanup EXIT
cache="file://$scratch/cache"
fresh="local?root=$scratch/runner"
nix key generate-secret --key-name drvkit-test > "$scratch/key"
public=$(nix key convert-secret-to-public < "$scratch/key")
recipe=$(nix-instantiate "$(dirname "$0")/cache.nix" --option allow-import-from-derivation false)
expected=$(nix build --no-link --print-out-paths "$recipe^out")
nix store build-trace info --recursive --json "$recipe^out" |
  jq -r '.[] | select(.value) | "/nix/store/" + .value.outPath' |
  nix copy --to "$cache?secret-key=$scratch/key" --stdin "$recipe^out"

# Seed only the expression and its input recipes. A new runner must obtain
# every output from the signed project cache or the usual Nixpkgs cache.
nix copy --to "$fresh" "$recipe"
actual=$(nix build --store "$fresh" -j0 --option builders "" \
  --option always-allow-substitutes false --option allow-import-from-derivation false \
  --option substituters "$cache https://cache.nixos.org" --option extra-trusted-public-keys "$public" \
  --no-link --print-out-paths "$recipe^out" 2>"$scratch/restore.log") || { cat "$scratch/restore.log" >&2; exit 1; }
if grep -q "^building '" "$scratch/restore.log"; then cat "$scratch/restore.log" >&2; exit 1; fi
[[ "$actual" == "$expected" ]]
target=$actual
while [[ -L "$scratch/runner$target" ]]; do target=$(readlink "$scratch/runner$target"); done
[[ $(cat "$scratch/runner$target") == cache-ok ]]
