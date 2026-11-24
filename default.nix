{ self, nixpkgs, name, mkPackage, mkTest ? _: _: throw "This builder has no test runner"
, mkApp ? null, selectTarget ? { src, target, ... }: { src = src + ("/" + target); }
, extraChecks ? _: {}, systems ? [ "x86_64-linux" "aarch64-linux" ]
, toolSource ? null, projectArgs ? args: args }:
let
  inherit (nixpkgs) lib;
  eachSystem = lib.genAttrs systems;
  ca = drv: drv.overrideAttrs { __contentAddressed = true; allowSubstitutes = true; };
  # Flake entry points are evaluated again by the installed commands.
  entrySource = benchmark: if toolSource == null then self.outPath else
    let inherit (toolSource) root;
    in lib.fileset.toSource {
      inherit root;
      fileset = lib.fileset.unions ([ (root + "/flake.nix") (root + "/flake.lock") ]
        ++ toolSource.files ++ lib.optionals benchmark toolSource.benchmarkFiles);
    };
  projectFilter = import ./project-filter.nix lib;
  clean = src:
    if src ? _isLibCleanSourceWith || lib.isDerivation src then src
    else let root = if builtins.isAttrs src then src.outPath else src;
         in lib.cleanSourceWith {
           name = "project-source"; src = root;
           filter = path: type: lib.cleanSourceFilter path type
             && projectFilter root path type
             && !(dirOf path == toString root && builtins.elem (baseNameOf path) [ "result" "target" ]);
         };
  relative = path: let p = lib.removePrefix "./" path;
    in if path == "." then "." else if p == "" || lib.hasPrefix "/" p ||
      lib.any (part: builtins.elem part [ "" "." ".." ]) (lib.splitString "/" p)
    then throw "Expected a project-relative member path, got ${builtins.toJSON path}" else p;
  commandsFor = args:
    let source = import ./source-reader.nix lib args.src;
        commands = args.commands or (if source.exists "drvlang.json" then
          (builtins.fromJSON (source.readFile "drvlang.json")).commands else {});
    in if builtins.isAttrs commands then builtins.mapAttrs (_: relative) commands
       else throw "commands must map target names to project-relative paths";
  select = original:
    let args = projectArgs original;
        base = removeAttrs args [ "system" "target" "commands" "srcForTarget" ];
        src = if target != null && target != "" && args ? srcForTarget then
          let selected = args.srcForTarget { name = target; target = path; };
          in if builtins.isPath selected then lib.cleanSourceWith {
            name = "project-source"; src = selected; filter = projectFilter selected;
          } else selected
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
        discover = ca (pkgs.writeShellScript "${name}-run" ''
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
        '');
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
        # Each trial runs the benchmark itself, even if its CA output is
        # already in the store. Its dependency graph stays warm.
        entry = ca (pkgs.writeText "drvbench.nix" ''
          { trial }: ((builtins.getFlake "path:${entrySource true}").checks.${system}.benchmark).overrideAttrs {
            drvlangBenchTrial = trial;
            allowSubstitutes = false;
          }
        '');
    in pkgs.runCommand "drvbench" {
      __contentAddressed = true;
      nativeBuildInputs = [ pkgs.rustc pkgs.stdenv.cc pkgs.makeWrapper ];
      meta.mainProgram = "drvbench";
    } ''
      mkdir -p "$out/bin"
      rustc --edition=2021 -C opt-level=s ${./src/bench.rs} -o "$out/bin/drvbench"
      wrapProgram "$out/bin/drvbench" --set DRVLANG_BENCH_ENTRY ${entry} \
        --prefix PATH : ${lib.makeBinPath [ pkgs.nix ]}
    '';
  cli = system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      entry = ca (pkgs.writeText "${name}-cli.nix" ''
        { directory, operation, target ? "", options ? "{}", testArgCount ? "0" }:
        let tool = builtins.getFlake "path:${entrySource false}";
            args = builtins.fromJSON options // {
              inherit target;
              system = builtins.currentSystem; src = /. + directory;
            } // (if testArgCount == "0" then {} else { testArgs = builtins.genList
              (i: builtins.getEnv ("DRVLANG_TEST_ARG_" + toString i)) (builtins.fromJSON testArgCount); });
        in if operation == "build" then tool.lib.mkPackage args
           else if operation == "test" then tool.lib.mkTest args
           else let app = tool.lib.mkApp args;
                    pkgs = tool.inputs.nixpkgs.legacyPackages.''${args.system};
                in (pkgs.writeShellScript "${name}-run" ("exec " + pkgs.lib.escapeShellArg app.program + " \"$@\"")).overrideAttrs { __contentAddressed = true; allowSubstitutes = true; }
      '');
    in pkgs.runCommand name {
      __contentAddressed = true;
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
