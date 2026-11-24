lib: root: path: type:
let name = baseNameOf path;
    atRoot = dirOf path == toString root;
in !(type == "directory" && (builtins.elem name [
  ".git" ".direnv" ".devenv" ".drvlang" ".venv" ".gradle" "__pycache__" ".pnpm-store" "node_modules"
] || (atRoot && name == "target")))
  && !(atRoot && type == "symlink" && (name == "result" || lib.hasPrefix "result-" name))
