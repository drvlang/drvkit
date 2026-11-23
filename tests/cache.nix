{ system ? builtins.currentSystem }:
let
  pkgs = (builtins.getFlake "github:NixOS/nixpkgs/8c50a710ddca43d7a530fb805ad55bde8d0141c5").legacyPackages.${system};
  dynamic = import ../dynamic.nix { inherit pkgs; };
in dynamic {
  name = "drvkit-test-cache";
  expression = ''
    let bash = builtins.storePath "${pkgs.bash}";
    in builtins.derivation {
      name = "drvkit-test-payload";
      system = "${system}";
      builder = "''${bash}/bin/bash";
      args = [ "-ec" "echo cache-ok > $out" ];
      __contentAddressed = true;
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
    }
  '';
}
