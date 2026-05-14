# refind-nix

<!-- BEGIN generated:badges -->
[![CI](https://github.com/Daaboulex/refind-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Daaboulex/refind-nix/actions/workflows/ci.yml)
[![NixOS unstable](https://img.shields.io/badge/NixOS-unstable-78C0E8?logo=nixos&logoColor=white)](https://nixos.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
<!-- END generated:badges -->

Declarative rEFInd bootloader for NixOS — typed options, first-class theming, security validation.

<!-- BEGIN generated:upstream -->
## Upstream

| | |
|---|---|
| **Project** | Original code (no upstream) |
| **License** | N/A |
| **Tracked** | N/A |
<!-- END generated:upstream -->

## Features

- **Typed NixOS options** for `refind.conf` directives (no raw `extraConfig` needed)
- **First-class theme support** — themes as Nix store derivations with `mkRefindTheme`
- **Security validation** — PE binary detection, image size limits, directive whitelist, symlink rejection
- **Bug fixes** — nixpkgs #452075 (efiRemovable path), #453812 (default_selection override)
- **Safe ESP management** — tmp→fsync→rename writes, orphan file cleanup, syncfs
- **Uses `boot.loader.external`** — the official NixOS external bootloader hook

## Quick Start

```nix
# flake.nix
inputs.refind-nix.url = "github:Daaboulex/refind-nix";

# configuration.nix
{ inputs, ... }: {
  imports = [ inputs.refind-nix.nixosModules.default ];
  nixpkgs.overlays = [ inputs.refind-nix.overlays.default ];

  boot.loader.refind = {
    enable = true;
    theme = pkgs.refind-theme-minimal;
    hideUI = [ "hints" "arrows" "label" "badges" ];
    showTools = [ "shutdown" "reboot" "firmware" ];
    timeout = 5;
    maxGenerations = 10;
  };
}
```

## Custom Themes

Package any rEFInd theme with `mkRefindTheme`:

```nix
boot.loader.refind.theme = pkgs.mkRefindTheme {
  name = "my-theme";
  src = fetchFromGitHub { owner = "..."; repo = "..."; rev = "..."; hash = "..."; };
  description = "My custom rEFInd theme";
};
```

Security checks run automatically: PE binaries, oversized images, path traversal, symlinks, and unknown directives are all rejected at build time.

## Multi-Boot

Define manual boot entries for non-NixOS operating systems:

```nix
boot.loader.refind.extraEntries = [
  {
    name = "Windows";
    loader = "\\EFI\\Microsoft\\Boot\\bootmgfw.efi";
    ostype = "Windows";
  }
  {
    name = "macOS";
    loader = "\\EFI\\Apple\\Boot\\bootmgfw.efi";
    ostype = "MacOS";
    volume = "MacOS";
  }
];
```

Each entry supports: `name`, `loader`, `initrd`, `options`, `icon`, `volume`, `ostype`, `graphics`, `disabled`, and nested `subEntries`.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable rEFInd boot manager |
| `package` | package | pkgs.refind | rEFInd package |
| `timeout` | int | 10 | Boot timeout in seconds |
| `maxGenerations` | int/null | 50 | Max generations in menu |
| `defaultSelection` | str/null | null | Default boot entry |
| `efiInstallAsRemovable` | bool | !canTouchEfiVariables | Install to fallback EFI path |
| `theme` | path/null | null | Theme directory (Nix store path) |
| `hideUI` | list of enum | [] | UI elements to hide |
| `showTools` | list of enum | [shutdown reboot firmware] | Second-row tools |
| `bannerScale` | enum | fillscreen | Banner scaling |
| `textOnly` | bool | false | Text-only mode |
| `extraConfig` | lines | "" | Raw config lines |
| `additionalFiles` | attrsOf path | {} | Extra files for ESP |
| `resolution` | str/null | null | Screen resolution (e.g. "1920x1080") |
| `scanfor` | list of enum | [] | Boot entry types to scan for |
| `dontScanDirs` | list of str | [EFI/nixos ...] | Dirs to exclude from scanning |
| `useGraphicsFor` | list of enum | [] | OS types to boot in graphics mode |
| `enableMouse` | bool | false | Enable mouse support |
| `enableTouch` | bool | false | Enable touchscreen support |
| `graceful` | bool | false | Don't fail if ESP not mounted |
| `extraEntries` | list of submodule | [] | Manual boot entries (Windows, macOS, etc.) |

<!-- BEGIN generated:options -->
<!-- END generated:options -->

## Security

Theme files are validated at build time with 12 security checks:

1. PE binary detection (MZ magic bytes)
2. EFI file extension rejection (case-insensitive)
3. Image file size limit (5 MB)
4. Icons directory extension whitelist (.png, .bmp only)
5. Symlink rejection
6. Theme.conf directive whitelist
7. Include directive rejection
8. Path traversal detection (forward and backslash)
9. Absolute path rejection in directive values
10. Image dimension limits (8192x8192 for PNG/BMP)
11. Fonts directory extension whitelist (.png only)
12. JPEG/ICNS rejection (use PNG instead)

Runtime validation runs during `nixos-rebuild switch` for themes not built with `mkRefindTheme`. The `extraConfig` option bypasses all validation — use only for directives not covered by typed options.

## Known Issues

- **rEFInd 0.14.2 `showtools` regression**: Duplicate tool entries appear. Affects all distributions. Workaround: downgrade to 0.14.0.2 or use `hideUI` to reduce clutter.
- **ESP sizing**: Each NixOS generation copies kernel (~12 MB) + initrd (25-200 MB) to the ESP. With NVIDIA drivers (initrd ~192 MB), a 500 MB ESP holds only 2-3 generations. Set `maxGenerations` accordingly.

<!-- BEGIN generated:options -->
<!-- END generated:options -->

## License

MIT

<!-- BEGIN generated:footer -->
---

*Maintained as part of the [Daaboulex](https://github.com/Daaboulex) NixOS ecosystem.*
<!-- END generated:footer -->
