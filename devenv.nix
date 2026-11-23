{ pkgs, ... }: {
  languages.rust.enable = true;
  packages = [ pkgs.nix ];
}
