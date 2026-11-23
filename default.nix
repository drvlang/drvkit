{ self, nixpkgs, name, mkPackage, mkTest ? _: _: throw "This builder has no test runner"
, mkApp ? null, selectTarget ? { src, target, ... }: { src = src + ("/" + target); }
, extraChecks ? _: {}, systems ? [ "x86_64-linux" "aarch64-linux" ]
, projectArgs ? args: args }:
let
  inherit (nixpkgs) lib;
  eachSystem = lib.genAttrs systems;
  clean = src:
    let root = toString src;
    in if src ? _isLibCleanSourceWith then src.outPath
    else if lib.isDerivation src then src else lib.cleanSourceWith {
      name = "project-source";
      src = if builtins.isAttrs src then src.outPath else src;
      filter = path: type:
        let rel = lib.removePrefix (root + "/") (toString path);
            base = baseNameOf path;
        in lib.cleanSourceFilter path type &&
          !(type == "directory" && builtins.elem base [ ".venv" ".devenv" ".direnv" ".drvlang" ".gradle" ]) &&
          !(builtins.elem rel [ "target" "result" ]) &&
          !(type == "symlink" && lib.hasPrefix "result-" rel);
    };
  relative = path: let p = lib.removePrefix "./" path;
    in if path == "." then "." else if p == "" || lib.hasPrefix "/" p ||
      lib.any (part: builtins.elem part [ "" "." ".." ]) (lib.splitString "/" p)
    then throw "Expected a project-relative member path, got ${builtins.toJSON path}" else p;
  commandsFor = args:
    let manifest = args.src + "/drvlang.json";
        commands = args.commands or (if builtins.pathExists manifest then
          (builtins.fromJSON (builtins.readFile manifest)).commands else {});
    in if builtins.isAttrs commands then builtins.mapAttrs (_: relative) commands
       else throw "commands must map target names to project-relative paths";
  select = original:
    let args = projectArgs original;
        base = removeAttrs args [ "system" "target" "commands" "srcForTarget" ];
        src = if target != null && target != "" && args ? srcForTarget then
          args.srcForTarget { name = target; target = path; }
          else clean args.src;
        target = args.target or null;
        commands = commandsFor args;
        path = if builtins.hasAttr target commands then commands.${target} else relative target;
    in base // { inherit src; } // lib.optionalAttrs (target != null && target != "") (
      selectTarget { inherit src; target = path; name = target; });
  packageArgs = args: removeAttrs args [ "program" "testArgs" ];
  package = args: mkPackage nixpkgs.legacyPackages.${args.system} (packageArgs (select args));
  test = args: mkTest nixpkgs.legacyPackages.${args.system} (removeAttrs (select args) [ "program" ]);
  app = args:
    let pkgs = nixpkgs.legacyPackages.${args.system};
        selected = select args;
        pkg = mkPackage pkgs (packageArgs selected);
        basename = selected.program or null;
        discover = pkgs.writeShellScript "${name}-run" ''
          shopt -s nullglob
          programs=()
          for candidate in "${pkg}"/bin/*; do
            if [[ -f "$candidate" && -x "$candidate" ]]; then programs+=("$candidate"); fi
          done
          if [[ ''${#programs[@]} != 1 ]]; then
            echo "Select an executable with the 'program' option. Found: ''${programs[*]:-(none)}" >&2
            exit 1
          fi
          exec "''${programs[0]}" "$@"
        '';
    in if mkApp != null then mkApp pkgs selected pkg else {
      type = "app"; program = if basename == null then toString discover
        else if builtins.match "[^/]+" basename == null || builtins.elem basename [ "." ".." ]
        then throw "program must be a basename in bin/" else "${pkg}/bin/${basename}";
    };
  flakeFor = targets: let forTargets = f: eachSystem (system:
    builtins.mapAttrs (_: args: f (args // { inherit system; })) targets);
    in { packages = forTargets package; checks = forTargets test; apps = forTargets app; };
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
      entry = pkgs.writeText "${name}-cli.nix" ''
        { directory, operation, target ? "", options ? "{}", testArgCount ? "0" }:
        let tool = builtins.getFlake "path:${self.outPath}";
            args = builtins.fromJSON options // {
              inherit target;
              system = builtins.currentSystem; src = /. + directory;
            } // (if testArgCount == "0" then {} else { testArgs = builtins.genList
              (i: builtins.getEnv ("DRVLANG_TEST_ARG_" + toString i)) (builtins.fromJSON testArgCount); });
        in if operation == "build" then tool.lib.mkPackage args
           else if operation == "test" then tool.lib.mkTest args
           else let app = tool.lib.mkApp args;
                    pkgs = tool.inputs.nixpkgs.legacyPackages.''${args.system};
                in pkgs.writeShellScript "${name}-run" ("exec " + pkgs.lib.escapeShellArg app.program + " \"$@\"")
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
  apps = eachSystem (system: let app = { type = "app"; program = "${cli system}/bin/${name}"; };
    in { default = app; ${name} = app; });
  checks = eachSystem (system: { cli = cli system; } // extraChecks system);
  lib = {
    projectSource = import ./project-source.nix lib;
    mkPackage = package;
    mkTest = test;
    mkApp = app;
    mkFlake = args: flakeFor { default = args; };
    mkMonorepoFlake = args: let targets = commandsFor args;
      in flakeFor (if targets == {} then throw "Set commands or add a drvlang.json containing a commands map"
        else builtins.mapAttrs (name: _: args // { target = name; }) targets);
  };
}
