# themes — all bundled rEFInd themes.
{ callPackage }:

{
  minimal = callPackage ./minimal.nix { };
  regular = callPackage ./regular.nix { };
}
