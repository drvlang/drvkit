let
  input = builtins.getFlake "github:NixOS/nixpkgs/8c50a710ddca43d7a530fb805ad55bde8d0141c5";
  pkgs = input.legacyPackages.${builtins.currentSystem};
  source = import ../nixpkgs-source.nix;
  pinned = source pkgs input;
  local = source { inherit (pkgs) lib; path = ./.; } null;
  stored = source { inherit (pkgs) lib; path = /. + builtins.unsafeDiscardStringContext local; } null;
  tools = import ../. {
    name = "source-test"; self = {}; nixpkgs = input;
    mkPackage = _: args: args.src;
  };
  selected = tools.lib.projectSource { root = ./.; files = [ ./cache.nix ]; };
in
assert pinned == input.outPath;
assert builtins.getContext pinned == { ${builtins.unsafeDiscardStringContext pinned}.path = true; };
assert stored == local && builtins.getContext stored == builtins.getContext local;
assert local != toString ./. && builtins.getContext local == { ${builtins.unsafeDiscardStringContext local}.path = true; };
assert builtins.readFile (local + "/nixpkgs-source.nix") == builtins.readFile ./nixpkgs-source.nix;
assert (tools.lib.mkPackage { system = builtins.currentSystem; src = selected; }).origSrc == ./.;
true
