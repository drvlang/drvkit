# Instantiate the lock-derived graph inside a recursive builder. The evaluator
# that imports the consumer's flake only sees the planner and its dynamic edge.
{ pkgs }:
{ name, expression, prepare ? "", copyDerivation ? null }:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  # Keep stdout/stderr open until the process exits. Some Nix daemons clean
  # up a builder when its log pipes close, before coreutils ln has exited.
  link = pkgs.runCommand "drvkit-symlink" {
    nativeBuildInputs = [ pkgs.rustc pkgs.stdenv.cc ];
  } ''
    rustc --edition=2021 -C opt-level=s ${./src/symlink.rs} -o drvkit-symlink
    install -m 0555 drvkit-symlink "$out"
  '';
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
    allowSubstitutes = false;
    passAsFile = [ "expression" "wrapper" ];
    inherit expression;
    wrapper = ''
      let link = builtins.storePath "${link}";
      in builtins.derivation {
        name = ${builtins.toJSON "${name}-result"};
        system = ${builtins.toJSON system};
        builder = link;
        args = [ (import ./result.nix) ];
        preferLocalBuild = true;
        allowSubstitutes = false;
      }
    '';
  };
  result = builtins.derivation {
    inherit name system;
    builder = link;
    args = [ (builtins.outputOf planner.outPath "out") ];
    preferLocalBuild = true;
    allowSubstitutes = false;
  };
in result // { inherit planner; passthru = { inherit planner; }; }
