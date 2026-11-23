# Keep project-relative paths intact while hashing only the requested files.
lib:
{ root, files }:
let
  selected = lib.fileset.toSource { inherit root; fileset = lib.fileset.unions files; };
  ignoredDirectories = [ ".git" ".direnv" ".devenv" ".venv" ".gradle" "__pycache__" ".pnpm-store" "node_modules" ];
in lib.cleanSourceWith {
  name = "project-source";
  src = selected;
  filter = path: type:
    let name = baseNameOf path;
        atRoot = dirOf (toString path) == toString root;
    in !(type == "directory" && (builtins.elem name ignoredDirectories || (atRoot && name == "target")))
      && !(atRoot && type == "symlink" && (name == "result" || lib.hasPrefix "result-" name));
}
