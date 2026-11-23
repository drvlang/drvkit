# Instantiate the lock-derived graph inside a recursive builder. The evaluator
# that imports the consumer's flake only sees the planner and its dynamic edge.
{ pkgs }:
{ name, expression, prepare ? "", copyDerivation ? null }:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  forward = target: [ "-eu" "-c" ''${pkgs.coreutils}/bin/ln -s "$1" "$out"'' "forward" target ];
  planner = builtins.derivation {
    name = "${name}-result.drv";
    inherit system;
    builder = pkgs.runtimeShell;
    args = [ "-eu" "-c" ''
      cd "$TMPDIR"
      ${prepare}
      cp "$expressionPath" ./result.nix
      cp "$wrapperPath" ./forward.nix
      drv=$(${pkgs.nix}/bin/nix-instantiate ./forward.nix)
      ${if copyDerivation == null then ''cp "$drv" "$out"''
        else ''${copyDerivation} internal-copy-derivation "$drv" "$out"''}
    '' ];
    PATH = pkgs.lib.makeBinPath [ pkgs.coreutils ];
    NIX_CONFIG = ''
      extra-experimental-features = nix-command ca-derivations dynamic-derivations recursive-nix
      allow-import-from-derivation = false
    '';
    __contentAddressed = true;
    outputHashMode = "text";
    outputHashAlgo = "sha256";
    requiredSystemFeatures = [ "recursive-nix" ];
    preferLocalBuild = true;
    allowSubstitutes = false;
    passAsFile = [ "expression" "wrapper" ];
    inherit expression;
    wrapper = ''
      let coreutils = builtins.storePath "${pkgs.coreutils}";
      in builtins.derivation {
        name = ${builtins.toJSON "${name}-result"};
        system = ${builtins.toJSON system};
        builder = "''${coreutils}/bin/ln";
        args = [ "-s" (import ./result.nix) (builtins.placeholder "out") ];
        preferLocalBuild = true;
        allowSubstitutes = false;
      }
    '';
  };
  result = builtins.derivation {
    inherit name system;
    builder = pkgs.runtimeShell;
    args = forward (builtins.outputOf planner.outPath "out");
    preferLocalBuild = true;
    allowSubstitutes = false;
  };
in result // { inherit planner; passthru = { inherit planner; }; }
