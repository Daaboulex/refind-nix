# Options

Every option the modules of this flake declare. This file is generated from the module sources: change a description there, then run `nix run .#std-write-option-reference`.

## NixOS module

### `boot.loader.refind.enable`

Whether to enable rEFInd boot manager.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.package`

The refind package to use.

Type: `package`. Default: `pkgs.refind`.

### `boot.loader.refind.additionalFiles`

Extra files to copy to the ESP rEFInd directory. Keys must be relative paths.

Type: `attribute set of absolute path`. Default: `{ }`. Example: `{ "tools/memtest.efi" = "${pkgs.memtest86plus.efi}/BOOTX64.efi"; }`.

### `boot.loader.refind.allowCoexistWithExternalInstaller`

Install rEFInd after an external bootloader installer that owns
`boot.loader.external` — lanzaboote being the common case.

`boot.loader.external.installHook` holds a single program, so both
installers cannot claim it. With this set, rEFInd chains instead:
`system.build.installBootLoader` becomes a script that runs the
external hook first and the rEFInd installer second, so one
`nixos-rebuild switch` refreshes both and a failure in either
fails the switch.

Pair with `generateNixosEntries = false`: lanzaboote's signed
unified kernel images are what rEFInd should list.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.allowCoexistWithSystemdBoot`

Allow rEFInd and systemd-boot to be enabled simultaneously.

The typical use case is a Mac (where Apple firmware reliably loads
the EFI fallback path at `/EFI/BOOT/BOOTx64.EFI` but ignores
BootOrder): install rEFInd as the firmware fallback
(`efiInstallAsRemovable = true`) so it always loads first, and add
an `extraEntries` chainload to `/EFI/systemd/systemd-bootx64.efi`
so rEFInd delegates NixOS generation selection to systemd-boot.
systemd-boot continues to enumerate NixOS gens declaratively
on every `nixos-rebuild switch`.

Disabled by default to surface accidental dual-install. Opt in
explicitly when you understand the chainload setup.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.bannerScale`

Banner scaling mode. null = theme or rEFInd default.

Type: `null or one of "noscale", "fillscreen"`. Default: `null`.

### `boot.loader.refind.defaultSelection`

Default boot entry. null = most recent. Only written if set.

Type: `null or string matching the pattern [^\n\r]+`. Default: `null`.

### `boot.loader.refind.dontScanDirs`

Directories to exclude from boot entry scanning.

Type: `list of string matching the pattern [^\n\r,]+`. Default: `[ "EFI/nixos" ] ++ lib.optional generateNixosEntries (if efiInstallAsRemovable then "efi/boot/kernels" else "efi/refind/kernels")`.

### `boot.loader.refind.efiInstallAsRemovable`

Install to EFI/BOOT/bootx64.efi. Required when NVRAM writes fail. With `allowCoexistWithSystemdBoot`, systemd-boot is made graceful (mkDefault), because bootctl reports rEFInd at that path as another boot loader and a non-graceful update aborts on every systemd-boot version change.

Type: `boolean`. Default: `!config.boot.loader.efi.canTouchEfiVariables`.

### `boot.loader.refind.enableMouse`

Enable mouse support in rEFInd.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.enableTouch`

Enable touchscreen support in rEFInd.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.extraConfig`

Raw lines prepended to refind.conf. WARNING: bypasses all validation — can inject include, menuentry, or any rEFInd directive. Only use for directives not covered by typed options.

Type: `strings concatenated with "\n"`. Default: `""`.

### `boot.loader.refind.extraDontScanDirs`

Directories appended to `dontScanDirs`, keeping its computed default.

Use this to hide a loader you already reach through `extraEntries`;
rEFInd otherwise finds it by scanning and lists it a second time.

Type: `list of string matching the pattern [^\n\r,]+`. Default: `[ ]`.

Example:

```nix
[
  "EFI/systemd"
]
```

### `boot.loader.refind.extraEntries`

Manual boot entries for non-NixOS OSes (Windows, macOS, other Linux). Each becomes a rEFInd menuentry block.

Type: `list of (submodule)`. Default: `[ ]`.

Example:

```nix
[
  {
    name = "Windows";
    loader = "\\EFI\\Microsoft\\Boot\\bootmgfw.efi";
    icon = "\\EFI\\refind\\icons\\os_win.png";
    ostype = "Windows";
  }
]
```

### `boot.loader.refind.extraEntries.*.disabled`

Exclude this entry from the generated config.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.extraEntries.*.graphics`

Force graphics mode on/off for this entry. null = omit.

Type: `null or boolean`. Default: `null`.

### `boot.loader.refind.extraEntries.*.icon`

Path to icon file in the Nix store. null = omit.

Type: `null or absolute path`. Default: `null`.

### `boot.loader.refind.extraEntries.*.initrd`

initrd path on the ESP. null = omit.

Type: `null or string matching the pattern [^\n\r]+`. Default: `null`.

### `boot.loader.refind.extraEntries.*.loader`

EFI binary path (e.g. \EFI\Microsoft\Boot\bootmgfw.efi).

Type: `string matching the pattern [^\n\r]+`.

### `boot.loader.refind.extraEntries.*.name`

Menu entry label displayed in rEFInd.

Type: `string matching the pattern [^\n\r]+`.

### `boot.loader.refind.extraEntries.*.options`

Kernel/loader options string. null = omit.

Type: `null or string matching the pattern [^\n\r]+`. Default: `null`.

### `boot.loader.refind.extraEntries.*.ostype`

OS type hint for rEFInd icon selection. null = omit.

Type: `null or one of "Linux", "Windows", "MacOS"`. Default: `null`.

### `boot.loader.refind.extraEntries.*.subEntries`

Submenu entries nested under this entry (one level only).

Type: `list of (submodule)`. Default: `[ ]`.

### `boot.loader.refind.extraEntries.*.subEntries.*.disabled`

Exclude this submenu entry from the generated config.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.extraEntries.*.subEntries.*.graphics`

Graphics mode override for this submenu entry. null = omit.

Type: `null or boolean`. Default: `null`.

### `boot.loader.refind.extraEntries.*.subEntries.*.icon`

Icon path for this submenu entry. null = omit.

Type: `null or absolute path`. Default: `null`.

### `boot.loader.refind.extraEntries.*.subEntries.*.initrd`

initrd path for this submenu entry. null = omit.

Type: `null or string matching the pattern [^\n\r]+`. Default: `null`.

### `boot.loader.refind.extraEntries.*.subEntries.*.loader`

EFI binary path for this submenu entry.

Type: `string matching the pattern [^\n\r]+`.

### `boot.loader.refind.extraEntries.*.subEntries.*.name`

Submenu entry label.

Type: `string matching the pattern [^\n\r]+`.

### `boot.loader.refind.extraEntries.*.subEntries.*.options`

Options string for this submenu entry. null = omit.

Type: `null or string matching the pattern [^\n\r]+`. Default: `null`.

### `boot.loader.refind.extraEntries.*.subEntries.*.ostype`

OS type for this submenu entry. null = omit.

Type: `null or one of "Linux", "Windows", "MacOS"`. Default: `null`.

### `boot.loader.refind.extraEntries.*.subEntries.*.volume`

Volume for this submenu entry. null = omit.

Type: `null or string matching the pattern [^\n\r]+`. Default: `null`.

### `boot.loader.refind.extraEntries.*.volume`

Volume label or GUID for the loader. null = omit.

Type: `null or string matching the pattern [^\n\r]+`. Default: `null`.

### `boot.loader.refind.generateNixosEntries`

Generate a menuentry per NixOS generation, copying each kernel and
initrd to the ESP.

Set false for UKI-native setups (lanzaboote, systemd-ukify): the
signed unified kernel images already on the ESP are found by
rEFInd's own directory scan, so copied kernels would be redundant
and — under Secure Boot — unsigned and unbootable. rEFInd then
installs only its binary, config and theme; existing copied kernels
are removed on the next install.

Type: `boolean`. Default: `true`.

### `boot.loader.refind.graceful`

Don't fail if the ESP is not mounted. Useful for first installs or removable media.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.hideUI`

UI elements to hide.

Type: `list of (one of "banner", "label", "singleuser", "safemode", "hwtest", "arrows", "hints", "editor", "badges", "funcs", "selection", "all")`. Default: `[ ]`.

### `boot.loader.refind.manageNvram`

Let the installer create, replace and reorder rEFInd's NVRAM boot
entry (requires boot.loader.efi.canTouchEfiVariables).

Set false to own the boot entry yourself — for instance while
migrating rEFInd between ESPs, where the existing entry is the
rollback path and must survive the switch.

Type: `boolean`. Default: `true`.

### `boot.loader.refind.maxGenerations`

Maximum generations in boot menu. null = unlimited. Ignored when generateNixosEntries is false.

Type: `null or (positive integer, meaning >0)`. Default: `50`.

### `boot.loader.refind.resolution`

Screen resolution (e.g. "1920x1080" or "max").

Type: `null or string matching the pattern [^\n\r]+`. Default: `null`. Example: `"1920x1080"`.

### `boot.loader.refind.scanfor`

Boot entry types to scan for. Empty = rEFInd default.

Type: `list of (one of "internal", "external", "optical", "manual", "hdbios", "biosexternal", "cd", "firmware")`. Default: `[ ]`.

### `boot.loader.refind.secureBoot.enable`

Whether to enable signing the installed rEFInd binary with sbctl.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.secureBoot.pkiBundle`

Absolute path to the sbctl PKI bundle holding keys/ and GUID.

A string, never a Nix path: a path literal would copy the private
Secure Boot keys into the world-readable Nix store.

Type: `string matching the pattern /.+`. Default: `"/var/lib/sbctl"`.

### `boot.loader.refind.secureBoot.sbctlPackage`

The sbctl package to use.

Type: `package`. Default: `pkgs.sbctl`.

### `boot.loader.refind.shareSystemdBootKernels`

Point the generated menu entries at the kernels systemd-boot already
copied to `/EFI/nixos`, instead of keeping a second copy of every
kernel and initrd under rEFInd's own directory.

Halves ESP use when both boot loaders are installed. Requires
`allowCoexistWithSystemdBoot`, because rEFInd's installer runs after
systemd-boot's and reads what it wrote. The install fails if a path
does not resolve, so a change to the naming scheme upstream surfaces
at `nixos-rebuild switch` rather than at boot.

Generations with `boot.initrd.secrets` still get their own initrd
copy, since that file is modified after it is written.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.showTools`

Tool entries in the second row. Order controls display order.

Type: `list of (one of "shell", "gptsync", "apple_recovery", "windows_recovery", "mok_tool", "fwupdate", "memtest", "about", "exit", "shutdown", "reboot", "firmware", "hidden_tags", "netboot", "bootorder", "csr_rotate", "install")`.

Default:

```nix
[
  "shutdown"
  "reboot"
  "firmware"
]
```

### `boot.loader.refind.textOnly`

Text-only mode. Disables all theming.

Type: `boolean`. Default: `false`.

### `boot.loader.refind.theme`

Path to rEFInd theme directory in the Nix store.

Type: `null or absolute path`. Default: `null`. Example: `"${pkgs.refind-theme-minimal}"`.

### `boot.loader.refind.timeout`

Seconds the rEFInd menu waits before booting its default entry.

Follows the system-wide `boot.loader.timeout` unless set here, so a
chainloaded second menu can carry its own timeout.

Type: `signed integer`. Default: `config.boot.loader.timeout, or 10 when that is null`.

### `boot.loader.refind.useGraphicsFor`

OS types to boot in graphics mode. Empty = rEFInd default.

Type: `list of (one of "linux", "windows", "osx")`. Default: `[ ]`.
