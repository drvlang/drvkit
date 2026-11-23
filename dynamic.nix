# Instantiate the lock-derived graph inside a recursive builder. The evaluator
# that imports the consumer's flake only sees the planner and its dynamic edge.
{ pkgs }:
{ name, expression, prepare ? "", copyDerivation ? null }:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  # Keep stdout/stderr open until the process exits. Some Nix daemons clean
  # up a builder when its log pipes close, before coreutils ln has exited.
  link = pkgs.runCommand "drvkit-symlink" {
    __contentAddressed = true;
    nativeBuildInputs = [ pkgs.rustc pkgs.stdenv.cc ];
  } ''
    rustc --edition=2021 -C opt-level=s ${./src/symlink.rs} -o drvkit-symlink
    install -m 0555 drvkit-symlink "$out"
  '';
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
    allowSubstitutes = false;
    passAsFile = [ "expression" "wrapper" ];
    inherit expression;
    wrapper = ''
      let link = builtins.storePath "${link}";
      in builtins.derivation {
        name = ${builtins.toJSON "${name}-result"};
        system = ${builtins.toJSON system};
        builder = link;
        # A floating output lets Nix realize this same recipe under the
        # planner's basename without embedding a name-dependent output path.
        __contentAddressed = true;
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        args = [ (import ./result.nix) ];
        preferLocalBuild = true;
      }
    '';
  };
  result = builtins.derivation {
    inherit name system;
    __contentAddressed = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    builder = link;
    args = [ (builtins.outputOf planner.outPath "out") ];
    preferLocalBuild = true;
  };
in result // { inherit planner; passthru = { inherit planner; }; }
