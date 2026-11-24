# Give recursive evaluators access to the original Nixpkgs store object.
# A local Nixpkgs checkout still needs to enter the store for the sandbox.
pkgs: input:
if input != null then input.outPath else
let path = toString pkgs.path; in
if builtins.hasContext path then path
else if pkgs.lib.isStorePath path then builtins.appendContext path { ${path}.path = true; }
else builtins.path { path = pkgs.path; }
