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

- **22 typed NixOS options** for `refind.conf` directives (no raw `extraConfig` needed)
- **First-class theme support** — themes as Nix store derivations with `mkRefindTheme`
- **12 security checks** — PE binary detection, image dimension limits, directive whitelist, symlink rejection, and more
- **Typed multi-boot entries** — `extraEntries` submodule for Windows, macOS, Linux
- **Bug fixes** — nixpkgs #452075 (efiRemovable path), #453812 (default_selection override)
- **Safe ESP management** — fsync + directory fsync, atomic writes, orphan file cleanup, file locking
- **initrdSecrets support** — bootspec RFC compliant, LUKS key injection into initrd
- **15 flake checks** — eval tests, assertion tests, security unit tests

## Quick Start

### 1. Add the flake input

```nix
# flake.nix
inputs.refind-nix = {
  url = "github:Daaboulex/refind-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Import the module and overlay

```nix
# In your host configuration
{ inputs, pkgs, ... }: {
  imports = [ inputs.refind-nix.nixosModules.default ];
  nixpkgs.overlays = [ inputs.refind-nix.overlays.default ];
```

### 3. Disable your current bootloader and enable rEFInd

```nix
  # Disable systemd-boot (required — rEFInd asserts no conflicts)
  boot.loader.systemd-boot.enable = false;
  # Or if using GRUB: boot.loader.grub.enable = false;

  boot.loader.efi.canTouchEfiVariables = true;

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

### Migration from systemd-boot

Switching bootloaders is safe when done carefully:

1. **Build without activating first**: `nixos-rebuild build` — verifies the config evaluates and builds. Nothing changes on disk.
2. **Check ESP space**: `df -h /boot` — ensure at least 100 MB free.
3. **Keep a fallback**: your previous bootloader's EFI files are NOT deleted. rEFInd only writes to its own directory (`/EFI/refind/` or `/EFI/boot/`).
4. **Firmware boot menu**: if rEFInd fails, use your firmware's boot menu (F12, DEL, or Option/Alt on Mac) to select the old bootloader entry.
5. **Switch**: `sudo nixos-rebuild switch` — installs rEFInd and updates NVRAM.
6. **Reboot and verify**.

**For Apple hardware**: set `efiInstallAsRemovable = true` — Apple firmware is unreliable with custom NVRAM entries. This installs to the firmware fallback path which always works.

## Multi-Boot

rEFInd auto-discovers other operating systems on all drives. For explicit control, define manual boot entries:

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

## Custom Themes

Package any rEFInd theme with `mkRefindTheme`:

```nix
boot.loader.refind.theme = pkgs.mkRefindTheme {
  name = "my-theme";
  src = fetchFromGitHub { owner = "..."; repo = "..."; rev = "..."; hash = "..."; };
  description = "My custom rEFInd theme";
};
```

12 security checks run automatically at build time. Themes using JPEG or ICNS images must convert to PNG.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable rEFInd boot manager |
| `package` | package | pkgs.refind | rEFInd package |
| `timeout` | int | 10 | Boot timeout in seconds |
| `maxGenerations` | positive int/null | 50 | Max generations in menu (null = unlimited) |
| `defaultSelection` | str/null | null | Default boot entry |
| `efiInstallAsRemovable` | bool | !canTouchEfiVariables | Install to fallback EFI path (recommended for Mac) |
| `theme` | path/null | null | Theme directory (Nix store path) |
| `resolution` | str/null | null | Screen resolution (e.g. "1920x1080" or "max") |
| `hideUI` | list of enum | [] | UI elements to hide |
| `showTools` | list of enum | [shutdown reboot firmware] | Second-row tools |
| `bannerScale` | enum/null | null | Banner scaling (null = theme default) |
| `textOnly` | bool | false | Text-only mode |
| `scanfor` | list of enum | [] | Boot entry types to scan for |
| `dontScanDirs` | list of str | [EFI/nixos ...] | Dirs to exclude from scanning |
| `useGraphicsFor` | list of enum | [] | OS types to boot in graphics mode |
| `enableMouse` | bool | false | Enable mouse support |
| `enableTouch` | bool | false | Enable touchscreen support |
| `graceful` | bool | false | Don't fail if ESP not mounted |
| `extraEntries` | list of submodule | [] | Manual boot entries (Windows, macOS, etc.) |
| `extraConfig` | lines | "" | Raw config lines (bypasses validation) |
| `additionalFiles` | attrsOf path | {} | Extra files for ESP |

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

## License

MIT

<!-- BEGIN generated:footer -->
---

*Maintained as part of the [Daaboulex](https://github.com/Daaboulex) NixOS ecosystem.*
<!-- END generated:footer -->
