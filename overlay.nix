# overlays — expose mkRefindTheme and bundled themes via pkgs.
{ self }:
final: _prev: {
  mkRefindTheme = final.callPackage ./lib/mkRefindTheme.nix { };
  refind-themes = final.callPackage ./themes { };
  refind-theme-minimal = final.refind-themes.minimal;
  refind-theme-regular = final.refind-themes.regular;
}
