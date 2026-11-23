# Reconstruct already locked inputs in a recursive builder without performing
# any flake resolution or network access there. Preserve Nix string contexts
# so the recursive store can read each pinned source.
flake:
let
  attrs = builtins.mapAttrs;
  renderSet = set: "{ " + builtins.concatStringsSep " " (builtins.attrValues
    (attrs (name: input: "${builtins.toJSON name} = ${render input};") set)) + " }";
  render = input:
    let
      metadata = builtins.intersectAttrs {
        rev = null; shortRev = null; lastModified = null; lastModifiedDate = null;
        narHash = null; revCount = null; dirtyRev = null; dirtyShortRev = null;
      } input;
      source = ''(builtins.fromJSON ${builtins.toJSON (builtins.toJSON metadata)} // {
        outPath = builtins.storePath ${builtins.toJSON (toString input.outPath)};
      })'';
    in if !(input ? inputs) then source else ''
      (let sourceInfo = ${source};
           inputs = ${renderSet input.inputs};
           outputs = (import (sourceInfo.outPath + "/flake.nix")).outputs (inputs // { inherit self; });
           self = outputs // sourceInfo // { inherit inputs outputs sourceInfo; };
       in self)
    '';
in renderSet flake.inputs
