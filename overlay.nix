# overlays — expose mkRefindTheme and bundled themes via pkgs.
{ self }:
final: prev: {
  mkRefindTheme = final.callPackage ./lib/mkRefindTheme.nix { };
  refind-themes = final.callPackage ./themes { };
  refind-theme-minimal = final.refind-themes.minimal;
}
