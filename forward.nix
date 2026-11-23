{ system, bash, coreutils }:
{ name, target }:
builtins.derivation {
  inherit name system;
  __contentAddressed = true;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  builder = "${bash}/bin/bash";
  # The parent shell must retain the log pipes until ln exits. Making exit
  # explicit prevents the shell from replacing itself with the last command.
  args = [ "-eu" "-c" ''
    ${coreutils}/bin/ln -s -- "$1" "$out"
    exit 0
  '' "drvkit-forward" target ];
  preferLocalBuild = true;
}
