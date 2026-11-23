{ self, nixpkgs, name, mkPackage, extraChecks ? _: {} }:
let
  inherit (nixpkgs) lib;
  eachSystem = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
  # Keep checkout metadata and common top-level build products out of source inputs.
  clean = src:
    let root = toString src;
    in lib.cleanSourceWith {
      name = "project-source";
      src = if builtins.isAttrs src then src.outPath else src;
      filter = path: type:
        let rel = lib.removePrefix (root + "/") (toString path);
        in lib.cleanSourceFilter path type &&
          !(builtins.elem rel [ ".venv" ".devenv" ".direnv" "target" ".gradle" ".drvlang" ]) &&
          !(type == "symlink" && (rel == "result" || lib.hasPrefix "result-" rel));
    };
  build = { system, src, ... }@args:
    mkPackage nixpkgs.legacyPackages.${system}
      ((removeAttrs args [ "system" ]) // { src = clean src; });
  bench = system:
    let pkgs = nixpkgs.legacyPackages.${system};
    in pkgs.runCommand "drvbench" {
      nativeBuildInputs = [ pkgs.rustc pkgs.stdenv.cc pkgs.makeWrapper ];
      meta.mainProgram = "drvbench";
    } ''
      mkdir -p "$out/bin"
      rustc --edition=2021 -C opt-level=s ${./src/bench.rs} -o "$out/bin/drvbench"
      wrapProgram "$out/bin/drvbench" --set DRVLANG_BENCH "path:${self.outPath}#checks.${system}.benchmark" \
        --prefix PATH : ${lib.makeBinPath [ pkgs.nix ]}
    '';
  cli = system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      entry = pkgs.writeText "${name}-build.nix" ''
        { directory, options ? "{}" }:
        let tool = builtins.getFlake "path:${self.outPath}";
        in tool.lib.mkPackage ((builtins.fromJSON options) // {
          system = builtins.currentSystem; src = /. + directory;
        })
      '';
    in pkgs.runCommand name {
      nativeBuildInputs = [ pkgs.rustc pkgs.stdenv.cc pkgs.makeWrapper ];
      meta.mainProgram = name;
    } ''
      mkdir -p "$out/bin"
      rustc --edition=2021 -C opt-level=s ${./src/main.rs} -o "$out/bin/${name}"
      wrapProgram "$out/bin/${name}" --set DRVLANG_TOOL ${name} --set DRVLANG_ENTRY ${entry} \
        --prefix PATH : ${lib.makeBinPath [ pkgs.nix ]}
    '';
in {
  packages = eachSystem (system: { ${name} = cli system; default = cli system; bench = bench system; });
  checks = eachSystem (system: { cli = cli system; } // extraChecks system);
  lib.mkPackage = build;
  lib.mkFlake = args: let packages = eachSystem (system: { default = build (args // { inherit system; }); });
    in { inherit packages; checks = packages; };
}
