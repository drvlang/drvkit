let
  nixpkgs = builtins.getFlake "github:NixOS/nixpkgs/8c50a710ddca43d7a530fb805ad55bde8d0141c5";
  inherit (nixpkgs) lib;
  root = /. + builtins.getEnv "DRVKIT_TEST_ROOT";
  tools = import ../. {
    name = "source-test"; self = {}; inherit nixpkgs;
    toolSource = {
      root = root + "/tool";
      files = [ (root + "/tool/builder.nix") ];
      benchmarkFiles = [ (root + "/tool/benchmark.nix") ];
    };
    mkPackage = _: args: args.src;
    mkTest = _: args: args.src;
    selectTarget = { src, ... }: { inherit src; };
  };
  selected = tools.lib.projectSource { inherit root; files = [ (root + "/member/file")
    (root + "/member/local-link") (root + "/member/hidden-link") ]; };
  read = import ../source-reader.nix lib;
  # A normal file lookup, directory listing, or member projection must work
  # even if materializing the parent would fail.
  view = read (selected // { outPath = throw "copied the parent source"; });
  member = view.subdirectory "member";
  links = read selected;
  args = { system = builtins.currentSystem; src = root; };
  callback = args // { commands.member = "member"; target = "member"; srcForTarget = _: root; };
in
assert view.readDir "." == { member = "directory"; };
assert builtins.attrNames (view.readDir "./member") == [ "file" "hidden-link" "local-link" ];
assert view.readFile "member/file" == builtins.readFile (root + "/member/file");
assert !view.exists "hidden/file" && !view.exists "member/private" && !view.exists "member/missing";
assert builtins.readFile (member + "/file") == view.readFile "member/file";
assert !builtins.pathExists (member + "/private");
assert links.readFile "member/local-link" == view.readFile "member/file";
assert (links.readDir "member")."hidden-link" == "symlink" && !(links.exists "member/hidden-link/file");
{
  cli = tools.packages.${builtins.currentSystem}.default.drvPath;
  bench = tools.packages.${builtins.currentSystem}.bench.drvPath;
  package = toString (tools.lib.mkPackage args);
  check = toString (tools.lib.mkTest callback);
}
