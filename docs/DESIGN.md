# Design

Why the module is built the way it is. The [README](../README.md) says how to
use it.

## What it adds to the nixpkgs installer

`installer/refind-install.py` extends the rEFInd installer in nixpkgs,
`nixos/modules/system/boot/loader/refind/refind-install.py`. The module
disables the nixpkgs module `system/boot/loader/refind/refind.nix`, so the two
never declare the same options. The side effect is that importing this module
removes the nixpkgs `boot.loader.refind` options even while `enable` is false.

What it adds:

- Typed NixOS options for `refind.conf` directives, so no raw `extraConfig` is
  needed for them.
- Themes as Nix store derivations, built with `mkRefindTheme`.
- 12 security checks on a theme: PE binary detection, image dimension limits, a
  directive whitelist, symlink rejection and more. The full list is below.
- Typed multi-boot entries: the `extraEntries` submodule, for Windows, macOS
  and Linux. Each entry supports `name`, `loader`, `initrd`, `options`, `icon`,
  `volume`, `ostype`, `graphics`, `disabled` and nested `subEntries`. A
  sub-entry is written with its `name`, `loader`, `initrd` and `options` only.
- Two bug fixes, nixpkgs #452075 and #453812, described below.
- Safe ESP management: fsync and directory fsync, atomic writes, orphan file
  cleanup and file locking.
- initrdSecrets support: bootspec RFC compliant, LUKS key injection into the
  initrd.
- Signing with sbctl, a mode with no generated NixOS entries for unified kernel
  images, and an opt-out from NVRAM management.
- Flake checks: eval tests, assertion tests and security unit tests. See
  [DEVELOPMENT.md](DEVELOPMENT.md).

## The two nixpkgs fixes

nixpkgs #452075 concerns the `efiRemovable` path. Here the installer uses one
base directory in both layouts, `efi/boot` when `efiInstallAsRemovable` is set
and `efi/refind` otherwise, and puts the rEFInd binary in the same directory as
its config.

nixpkgs #453812 concerns the `default_selection` override. Here
`default_selection` is written only when `defaultSelection` is set.

## Writing to the ESP

The installer takes an exclusive lock, `.refind-install.lock` at the root of
the ESP, so two installs cannot run at once. Kernels, initrds, the rEFInd
binary and additional files are copied to a `.tmp` name, synced, renamed into
place, and their directory synced. `refind.conf` is written the same way. A
theme is copied beside the active one and swapped in by rename. At the end the
whole ESP filesystem is synced.

Files in rEFInd's directory that this run did not write are removed. A second
pass removes orphaned files from the four directories the installer manages,
`kernels`, `themes`, `icons` and `fonts`, and then removes those directories
when they are empty. `vars/` is never swept, because it holds rEFInd's own
runtime state.

rEFInd resolves a menu entry's path from the root of the volume, never from its
own directory. So every generated `loader` and `initrd` path is written from
the ESP root, and the installer checks that each one names an existing file
before it writes `refind.conf`.

`refind.conf` must be ASCII. rEFInd widens the bytes of its config straight to
UTF-16, so anything else would render as garbage, and the installer refuses it.

When the installer manages NVRAM, it replaces a `rEFInd` boot entry only when
that entry points at this ESP. A same-named entry on another disk is left
alone. The new entry is created before the old one is deleted, and it takes the
old one's place in the boot order.

With `secureBoot.enable` the installer checks that sbctl and its keys are there
before it touches the ESP, and fails if they are not. It then signs the rEFInd
binary and any additional file ending in `.efi`. `secureBoot.pkiBundle` is
a string, never a Nix path, because a path literal would copy the private
Secure Boot keys into the world-readable Nix store.

## Who runs the installer

There are three wirings, chosen by the two coexistence options alone. Reading
`boot.loader.systemd-boot.enable` to choose one would create a cycle in the
module merge, so the assertions read it instead.

- Alone, the module claims the install slot through `boot.loader.external` and
  declares that it supports initrd secrets.
- With `allowCoexistWithSystemdBoot`, systemd-boot keeps the install slot and
  the rEFInd installer runs from its `extraInstallCommands`, so one
  `nixos-rebuild switch` refreshes both. When rEFInd sits at the fallback path,
  systemd-boot is made graceful, because bootctl reports rEFInd there as
  another boot loader and a non-graceful update aborts on every systemd-boot
  version change.
- With `allowCoexistWithExternalInstaller`, `boot.loader.external.installHook`
  holds a single program, so `system.build.installBootLoader` becomes a script
  that runs the external hook first and the rEFInd installer second. A failure
  in either fails the switch.

## Sharing kernels with systemd-boot

`allowCoexistWithSystemdBoot` allows rEFInd and systemd-boot to be enabled at
once. It is off by default so an accidental double install shows up. The
typical case is a Mac: rEFInd is installed as the firmware fallback with
`efiInstallAsRemovable = true`, and an `extraEntries` entry chainloads
`/EFI/systemd/systemd-bootx64.efi`, so systemd-boot keeps the menu of NixOS
generations. The option requires `boot.loader.systemd-boot.enable`.

Running both boot loaders normally means two copies of every kernel and initrd
on the ESP. `shareSystemdBootKernels` points rEFInd's generation entries at the
copies systemd-boot already wrote to `/EFI/nixos`, so only one set exists:

```nix
boot.loader.refind = {
  allowCoexistWithSystemdBoot = true;
  shareSystemdBootKernels = true;
  maxGenerations = 3;
  extraDontScanDirs = [ "EFI/systemd" ];
};
```

`maxGenerations` must not exceed `configurationLimit`. `extraDontScanDirs`
hides systemd-boot from the scan, since you already chainload it through
`extraEntries` and rEFInd would otherwise list it a second time.

`shareSystemdBootKernels` needs `allowCoexistWithSystemdBoot`, because only
that mode guarantees systemd-boot's installer runs first. It reads the names
systemd-boot gives its copies under `/EFI/nixos`, a directory hardcoded in the
nixpkgs systemd-boot module.

The installer refuses to write `refind.conf` if any generated path does not
resolve, so a change to the naming systemd-boot uses surfaces at
`nixos-rebuild switch` rather than at boot.

`maxGenerations` must be set and no larger than systemd-boot's
`configurationLimit`, or rEFInd would list generations whose kernels
systemd-boot has already pruned. An XBOOTLDR partition is refused, since
systemd-boot puts the kernels there and not on the ESP. A generation with
`boot.initrd.secrets` still gets its own initrd copy, because that file is
modified after it is written.

## Themes on the ESP

rEFInd's own `icons/` and `fonts/` are installed next to the binary whatever
theme is picked. Without them rEFInd finds no icons directory and forces
`textonly`, and any icon a theme omits has nothing to fall back to.

A theme's own `hideui` and `showtools` lines are dropped on the way to the ESP.
rEFInd combines `hideui` flags with OR, so a theme hiding entry labels could
never be overridden by `hideUI`. Those two options are the module's to set.

Every theme is deployed to `themes/active`. rEFInd resolves the paths in
`theme.conf` against the directory of its own binary, and upstream themes point
at their own install name, so `mkRefindTheme` repoints `banner`, `icons_dir`,
`selection_big`, `selection_small` and `font` at `themes/active`. Otherwise the
banner, icons and selection images would silently never load.

`refind.conf` includes the theme before the module's own directives, so the
theme provides defaults and the options override them.

`mkRefindTheme` installs `theme.conf`, `background.png`, `selection_big.png`,
`selection_small.png`, `icons/` and `fonts/` from the source, and nothing else.

## Theme validation

Theme files are validated at build time by `mkRefindTheme`, with 12 security
checks:

1. PE binary detection (MZ magic bytes)
2. EFI file extension rejection (case-insensitive)
3. Image file size limit (5 MB), a LogoFAIL mitigation
4. Icons directory extension whitelist (.png, .bmp only)
5. Symlink rejection
6. Theme.conf directive whitelist
7. Include directive rejection
8. Path traversal detection (forward and backslash)
9. Absolute path rejection in directive values
10. Image dimension limits (8192x8192 for PNG/BMP), because rEFInd multiplies
    width by height unprotected
11. Fonts directory extension whitelist (.png only)
12. JPEG/ICNS rejection (use PNG instead), since their dimensions are not
    validated

Runtime validation runs during `nixos-rebuild switch`, for themes not built
with `mkRefindTheme`. The installer runs it on every theme it deploys. It
covers five of the checks: symlinks, `.efi` files, JPEG and ICNS files, PE
binaries and files over 5 MB.

The `extraConfig` option bypasses all validation. Use it only for directives
not covered by typed options.
