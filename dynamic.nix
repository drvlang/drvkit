# Instantiate the lock-derived graph inside a recursive builder. The evaluator
# that imports the consumer's flake only sees the planner and its dynamic edge.
{ pkgs }:
{ name, expression, prepare ? "", copyDerivation ? null }:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  forward = import ./forward.nix { inherit system; inherit (pkgs) bash coreutils; };
  planner = builtins.derivation {
    # Keep the planner output distinct from the recipe nix-instantiate
    # registers inside the sandbox, even when Nix rebuilds a known output.
    name = "${name}-plan.drv";
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
      exit 0
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
    passAsFile = [ "expression" "wrapper" ];
    inherit expression;
    wrapper = ''
      (import ${./forward.nix} {
        system = ${builtins.toJSON system};
        bash = builtins.storePath "${pkgs.bash}";
        coreutils = builtins.storePath "${pkgs.coreutils}";
      }) {
        name = ${builtins.toJSON "${name}-result"};
        target = import ./result.nix;
      }
    '';
  };
  result = forward {
    inherit name;
    target = builtins.outputOf planner.outPath "out";
  };
in result // { inherit planner; passthru = { inherit planner; }; }
