# mkRefindTheme — factory for rEFInd theme derivations with security validation.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

{
  name,
  src,
  version ? "unstable",
  variant ? null,
  themeDir ? ".",
  description ? "rEFInd theme",
  license ? lib.licenses.mit,
  maintainers ? [ ],
}:

stdenvNoCC.mkDerivation {
  pname = "refind-theme-${name}${lib.optionalString (variant != null) "-${variant}"}";
  inherit version src;

  dontBuild = true;
  dontFixup = false;

  installPhase = ''
    runHook preInstall

    srcDir=${lib.escapeShellArg themeDir}
    ${lib.optionalString (variant != null) "srcDir=${lib.escapeShellArg variant}"}

    if [ ! -f "$srcDir/theme.conf" ]; then
      echo "ERROR: theme.conf not found in $srcDir" >&2
      exit 1
    fi

    install -d $out
    cp "$srcDir/theme.conf" $out/

    for f in background.png selection_big.png selection_small.png; do
      [ -f "$srcDir/$f" ] && cp "$srcDir/$f" $out/
    done
    [ -d "$srcDir/icons" ] && cp -r "$srcDir/icons" $out/
    [ -d "$srcDir/fonts" ] && cp -r "$srcDir/fonts" $out/

    runHook postInstall
  '';

  fixupPhase = ''
    # SECURITY 1: reject PE binaries (MZ magic 0x4d5a)
    while IFS= read -r f; do
      if [ "$(head -c 2 "$f" 2>/dev/null | od -An -tx1 | tr -d ' ')" = "4d5a" ]; then
        echo "SECURITY: PE binary detected: $f" >&2
        exit 1
      fi
    done < <(find $out -type f)

    # SECURITY 2: reject .efi extensions (case-insensitive for FAT32).
    # Scan the SOURCE, not the whitelisted $out — a .efi outside the install
    # whitelist would otherwise be filtered out and never rejected.
    if find "$srcDir" -iname '*.efi' | grep -q .; then
      echo "SECURITY: EFI file extension in theme" >&2
      exit 1
    fi

    # SECURITY 3: size limits on ALL image types (LogoFAIL mitigation)
    if find $out \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.bmp' -o -name '*.icns' \) -size +5M | grep -q .; then
      echo "SECURITY: image file > 5MB detected" >&2
      exit 1
    fi

    # SECURITY 4: icons/ extension whitelist — only .png and .bmp
    if [ -d "$out/icons" ]; then
      if find "$out/icons" -type f ! \( -name '*.png' -o -name '*.bmp' \) | grep -q .; then
        echo "SECURITY: non-image file in icons/" >&2
        exit 1
      fi
    fi

    # SECURITY 5: reject symlinks. Scan the SOURCE, not the whitelisted $out —
    # a symlink outside the install whitelist would otherwise be filtered out.
    if find "$srcDir" -type l | grep -q .; then
      echo "SECURITY: symlink in theme" >&2
      exit 1
    fi

    # SECURITY 6: theme.conf directive whitelist
    ALLOWED='banner|banner_scale|icons_dir|selection_big|selection_small|font|hideui|showtools|textonly|use_graphics_for|big_icon_size|small_icon_size|icon_delay|resolution'
    if grep -vE "^\s*$|^\s*#|^\s*(''${ALLOWED})\b" "$out/theme.conf" | grep -q .; then
      echo "SECURITY: unknown directive in theme.conf:" >&2
      grep -vE "^\s*$|^\s*#|^\s*(''${ALLOWED})\b" "$out/theme.conf" >&2
      exit 1
    fi

    # SECURITY 7: reject include (path traversal)
    if grep -qiE '^\s*include\b' "$out/theme.conf"; then
      echo "SECURITY: include directive in theme.conf" >&2
      exit 1
    fi

    # SECURITY 8: reject path traversal in directive values (forward and backslash)
    if grep -E '\.\.[\\/]' "$out/theme.conf" | grep -q .; then
      echo "SECURITY: path traversal in directive value" >&2
      exit 1
    fi

    # SECURITY 9: reject absolute paths in directive values (ESP-relative escape)
    if grep -E '^\s*(banner|icons_dir|selection_big|selection_small|font)\s+/' "$out/theme.conf" | grep -q .; then
      echo "SECURITY: absolute path in directive value" >&2
      exit 1
    fi

    # SECURITY 10: reject images with excessive dimensions (integer overflow mitigation)
    # rEFInd's LodePNG/load_bmp.c have unprotected width*height multiplication.
    # Cap at 8192x8192 to prevent integer overflow in 32-bit allocation math.
    while IFS= read -r img; do
      w=$(od -An -N4 -j16 -tu4 --endian=big "$img" 2>/dev/null | tr -d ' ')
      h=$(od -An -N4 -j20 -tu4 --endian=big "$img" 2>/dev/null | tr -d ' ')
      if [ -z "$w" ] || [ -z "$h" ]; then
        echo "SECURITY: malformed PNG (cannot read dimensions): $img" >&2
        exit 1
      fi
      if [ "$w" -gt 8192 ] || [ "$h" -gt 8192 ]; then
        echo "SECURITY: PNG dimensions exceed 8192px: $img ($w x $h)" >&2
        exit 1
      fi
    done < <(find $out \( -name '*.png' -o -name '*.PNG' \) -type f)
    while IFS= read -r img; do
      # Read DIB header size to determine field widths
      hdr_size=$(od -An -N4 -j14 -tu4 --endian=little "$img" 2>/dev/null | tr -d ' ')
      if [ -z "$hdr_size" ]; then
        echo "SECURITY: malformed BMP (cannot read header): $img" >&2
        exit 1
      fi
      if [ "$hdr_size" -eq 12 ]; then
        # BITMAPCOREHEADER: 16-bit width at offset 18, height at offset 20
        w=$(od -An -N2 -j18 -tu2 --endian=little "$img" 2>/dev/null | tr -d ' ')
        h=$(od -An -N2 -j20 -tu2 --endian=little "$img" 2>/dev/null | tr -d ' ')
      else
        # BITMAPINFOHEADER or later: 32-bit fields
        w=$(od -An -N4 -j18 -tu4 --endian=little "$img" 2>/dev/null | tr -d ' ')
        h=$(od -An -N4 -j22 -tu4 --endian=little "$img" 2>/dev/null | tr -d ' ')
        if [ -n "$h" ] && [ "$h" -gt 2147483647 ]; then
          h=$((4294967296 - h))
        fi
      fi
      if [ -z "$w" ] || [ -z "$h" ]; then
        echo "SECURITY: malformed BMP (cannot read dimensions): $img" >&2
        exit 1
      fi
      if [ "$w" -gt 8192 ] || [ "$h" -gt 8192 ]; then
        echo "SECURITY: BMP dimensions exceed 8192px: $img ($w x $h)" >&2
        exit 1
      fi
    done < <(find $out \( -name '*.bmp' -o -name '*.BMP' \) -type f)

    # SECURITY 11: fonts/ extension whitelist — only .png allowed
    if [ -d "$out/fonts" ]; then
      if find "$out/fonts" -type f ! -name '*.png' | grep -q .; then
        echo "SECURITY: non-PNG file in fonts/" >&2
        exit 1
      fi
    fi

    # SECURITY 12: reject JPEG/ICNS (no dimension validation — use PNG instead)
    if find $out \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.icns' \) -type f | grep -q .; then
      echo "SECURITY: JPEG/ICNS not allowed in themes (convert to PNG)" >&2
      exit 1
    fi
  '';

  meta = {
    inherit description license maintainers;
    platforms = lib.platforms.linux;
  };
}
