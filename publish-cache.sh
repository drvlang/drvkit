#!/usr/bin/env bash
# Publish the build traces and inputs a fresh runner needs for named CA targets.
set -euo pipefail

upstream=
if [[ ${1:-} == --upstream && $# -ge 2 ]]; then
  upstream=$2
  shift 2
fi
if [[ $# -lt 2 ]]; then
  echo 'Usage: bash publish-cache.sh [--upstream READABLE-CACHE] WRITABLE-CACHE TARGET...' >&2
  exit 2
fi
cache=$1
shift
scratch=$(mktemp -d)
trap 'rm -r -- "$scratch"' EXIT
store=$(nix eval --raw --expr builtins.storeDir)
nix store build-trace info --recursive --json "$@" > "$scratch/traces"
if ! jq -e 'type == "array" and any(.[]; .key.drvPath and .value.outPath)
    and all(.[]; .opaquePath or (.key.drvPath and .value.outPath))' "$scratch/traces" >/dev/null; then
  echo 'Expected Nix 2.35 build traces. Pass built flake targets or .drv^out installables.' >&2
  exit 1
fi
jq -r --arg store "$store/" '.[] | select(.key) | $store + .key.drvPath' \
  "$scratch/traces" | sort -u > "$scratch/recipes"

# A resolved CA recipe refers to its actual build inputs, including ordinary
# setup hooks and fixed-output downloads absent from the final runtime closure.
xargs nix-store --query --references < "$scratch/recipes" | sort -u > "$scratch/inputs"
if [[ -n $upstream && -s $scratch/inputs ]]; then
  xargs nix-store --store "$upstream" --check-validity --print-invalid \
    < "$scratch/inputs" > "$scratch/missing"
  mv "$scratch/missing" "$scratch/inputs"
fi
jq -r --arg store "$store/" '.[] | select(.value) | $store + .value.outPath' \
  "$scratch/traces" >> "$scratch/inputs"
# Preserve the named installables so Nix also publishes their recipe-to-output
# mappings. Copying only the realized store paths loses these mappings.
sort -u "$scratch/inputs" | nix copy --to "$cache" --stdin "$@"
