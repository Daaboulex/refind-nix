# regular — rEFInd-theme-regular, one icon size and one font selected.
{
  lib,
  mkRefindTheme,
  fetchFromGitHub,
  runCommand,
  writeText,
  iconSize ? "256-96",
  font ? "source-code-pro-extralight-14.png",
  variant ? "dark",
}:

let
  bigIconSize = lib.head (lib.splitString "-" iconSize);
  smallIconSize = lib.last (lib.splitString "-" iconSize);
  suffix = lib.optionalString (variant != "light") "_${variant}";

  src = fetchFromGitHub {
    owner = "bobafetthotmail";
    repo = "refind-theme-regular";
    rev = "ed76f1e6d1bfe790ea7333fe5886fa7af126475d";
    hash = "sha256-Qo3/Y1ga1/+joasXilr56lBnc1WUjd1Kubv647pt/qQ=";
  };

  themeConf = writeText "theme.conf" ''
    icons_dir themes/active/icons
    big_icon_size ${bigIconSize}
    small_icon_size ${smallIconSize}
    banner themes/active/icons/bg${suffix}.png
    selection_big themes/active/icons/selection${suffix}-big.png
    selection_small themes/active/icons/selection${suffix}-small.png
    font themes/active/fonts/${font}
  '';

  selected = runCommand "refind-theme-regular-${iconSize}-${variant}" { } ''
    install -d $out/icons $out/fonts
    cp ${src}/icons/${iconSize}/*.png $out/icons/
    cp ${src}/fonts/${font} $out/fonts/
    cp ${themeConf} $out/theme.conf

    for required in \
      icons/bg${suffix}.png \
      icons/selection${suffix}-big.png \
      icons/selection${suffix}-small.png \
      fonts/${font}
    do
      if [ ! -f "$out/$required" ]; then
        echo "refind-theme-regular: $required missing for iconSize=${iconSize} variant=${variant}" >&2
        exit 1
      fi
    done
  '';
in
mkRefindTheme {
  name = "regular";
  version = "unstable-2026-08-01";
  src = selected;
  description = "Regular rEFInd theme (Munlik), ${iconSize} icons, ${variant} variant";
  license = lib.licenses.gpl3Only;
}
