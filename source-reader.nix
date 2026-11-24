# Inspect a lib.sources view without first importing its entire outPath.
# Following a symlink needs the actual projection: its destination may be hidden.
lib: src:
let
  filtered = src ? _isLibCleanSourceWith;
  original = toString (src.origSrc or src);
  materialized = rel: toString src + (if rel == "" then "" else "/" + rel);
  resolve = rel:
    let
      parts = builtins.filter (p: p != "" && p != ".") (lib.splitString "/" rel);
      walk = parent: rest:
        if rest == [] then { path = parent; filterChildren = true; }
        else let
          path = parent + "/" + builtins.head rest;
          type = builtins.readFileType path;
          remaining = builtins.tail rest;
        in if !builtins.pathExists path || !src.filter path type then null
           else if type == "symlink" then projected
           else if remaining != [] && type != "directory" then null
           else walk path remaining;
      projected = { path = materialized rel; filterChildren = false; };
    in if !filtered || builtins.elem ".." parts then projected else walk original parts;
  required = rel: let item = resolve rel;
    in if item == null then throw "Missing file in selected project source: ${rel}" else item;
in {
  # Roots backed by derivation outputs must be inspected in the build.
  generated = lib.isDerivation src || lib.any (dep: dep ? outputs || dep ? allOutputs)
    (builtins.attrValues (builtins.getContext original));
  subdirectory = rel: let item = required rel; in lib.cleanSourceWith {
    name = "project-source";
    src = item.path;
    filter = if item.filterChildren then src.filter else null;
  };
  exists = rel: let item = resolve rel; in item != null && builtins.pathExists item.path;
  readFile = rel: builtins.readFile (required rel).path;
  readDir = rel: let item = required rel; entries = builtins.readDir item.path;
    in if item.filterChildren then lib.filterAttrs (name: type: src.filter (item.path + "/" + name) type) entries
       else entries;
}
