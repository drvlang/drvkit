{ system ? builtins.currentSystem }:
let
  pkgs = (builtins.getFlake "github:NixOS/nixpkgs/8c50a710ddca43d7a530fb805ad55bde8d0141c5").legacyPackages.${system};
  dynamic = import ../dynamic.nix { inherit pkgs; };
  message = pkgs.runCommand "drvkit-cache-test-build-input" {} ''
    echo cache-ok > "$out"
  '';
  payload = pkgs.runCommand "drvkit-cache-test-intermediate" { __contentAddressed = true; } ''
    cat ${message} > "$out"
  '';
in dynamic {
  name = "drvkit-test-cache";
  expression = ''
    let
      bash = builtins.storePath "${pkgs.bash}";
      message = builtins.storePath "${payload}";
    in builtins.derivation {
      name = "drvkit-test-payload";
      system = "${system}";
      builder = "''${bash}/bin/bash";
      args = [ "-ec" "read -r message < ''${message}; echo $message > $out" ];
      __contentAddressed = true;
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
    }
  '';
}
