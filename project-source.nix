# Keep project-relative paths intact while hashing only the requested files.
lib:
{ root, files }:
let
  selected = lib.fileset.toSource { inherit root; fileset = lib.fileset.unions files; };
in lib.cleanSourceWith {
  name = "project-source";
  src = selected;
  filter = import ./project-filter.nix lib root;
}
