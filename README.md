# drvkit

Shared Rust command line and Nix flake interface for drvlang builders. Language repositories supply a builder and any language-specific checks. Their flakes pin drvkit as a source input.

A packaged tool runs `build [-C PROJECT] [-o RESULT | --no-link]` and prints the resulting Nix store path. Downstream flakes can call `lib.mkPackage { system, src, ... }` or `lib.mkFlake { src, ... }`. Source arguments can be filtered further by the caller.
