#!/usr/bin/env bash
set -euo pipefail
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export DRVKIT_TEST_ROOT="$scratch"
mkdir -p "$scratch"/{member/{node_modules,__pycache__,.pnpm-store},hidden,target,tool}
touch "$scratch"/tool/{flake.nix,flake.lock,builder.nix,benchmark.nix,README.md}
printf 'input' > "$scratch/member/file"
printf 'excluded' > "$scratch/member/private"
printf 'hidden' > "$scratch/hidden/file"
ln -s file "$scratch/member/local-link"
ln -s ../hidden "$scratch/member/hidden-link"

cd "$(dirname "$0")"
check() { nix eval --impure --json --file project-source.nix; }
before=$(check)
for dir in "$scratch"/member/{node_modules,__pycache__,.pnpm-store} "$scratch/target"; do
  printf 'generated' > "$dir/cache"
done
[[ $(check) == "$before" ]]
printf 'edited' > "$scratch/member/file"
[[ $(check) != "$before" ]]
tools() { check | jq -c '[.cli,.bench]'; }
original=$(tools)
echo 'documentation' >> "$scratch/tool/README.md"
[[ $(tools) == "$original" ]]
echo '# benchmark' >> "$scratch/tool/benchmark.nix"
edited=$(tools)
[[ $(jq -r '.[0]' <<< "$edited") == "$(jq -r '.[0]' <<< "$original")" ]]
[[ $(jq -r '.[1]' <<< "$edited") != "$(jq -r '.[1]' <<< "$original")" ]]
echo '# builder' >> "$scratch/tool/builder.nix"
[[ $(tools | jq -r '.[0]') != "$(jq -r '.[0]' <<< "$original")" ]]
