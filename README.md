# refind-nix

A NixOS module that installs and configures the rEFInd boot manager from typed
options. It is for a UEFI machine where you want rEFInd's settings, menu
entries and theme declared in your configuration. It extends the rEFInd
installer in nixpkgs, installs `pkgs.refind` and packages two themes.

It supports x86_64 and aarch64 machines. The checks in this repository evaluate
the module, build both themes and run the installer's menu generation against a
made-up ESP. None of them boots a machine.

## Install

Add the flake:

```nix
inputs.refind-nix = {
  url = "github:Daaboulex/refind-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Then import the module and the overlay, and switch rEFInd on:

```nix
{ inputs, pkgs, ... }:
{
  imports = [ inputs.refind-nix.nixosModules.default ];
  nixpkgs.overlays = [ inputs.refind-nix.overlays.default ];

  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.loader.refind = {
    enable = true;
    theme = pkgs.refind-theme-minimal;
  };
}
```

The module refuses a configuration that also enables systemd-boot or GRUB, so
turn yours off. For GRUB that is `boot.loader.grub.enable = false`. Importing
the module replaces the rEFInd module in nixpkgs, even while `enable` is false.

## Switching from another boot loader

Switching boot loaders is safe when done carefully:

1. Run `nixos-rebuild build`. It proves the configuration evaluates and builds,
   and changes nothing on disk.
2. Run `df -h /boot` and make sure the ESP has at least 100 MB free.
3. Run `sudo nixos-rebuild switch`. It installs rEFInd and updates NVRAM.
4. Reboot and verify.

With the configuration above rEFInd goes to `/EFI/refind` on the ESP. The
installer removes files only inside that directory, so your previous boot
loader's files stay as a fallback.

On Apple hardware set `efiInstallAsRemovable = true`. Apple firmware is
unreliable with custom NVRAM entries, and this installs rEFInd to the firmware
fallback path, `/EFI/boot`, which that firmware loads reliably. There it
replaces the fallback loader and removes the other files in that directory. It
cannot be combined with `boot.loader.efi.canTouchEfiVariables = true`.

## Options you are likely to set

| Under `boot.loader.refind` | What it is for |
|---|---|
| `theme` | A theme directory in the Nix store, such as `pkgs.refind-theme-minimal` |
| `timeout` | Seconds the menu waits. Follows `boot.loader.timeout` unless set |
| `maxGenerations` | How many NixOS generations the menu lists. 50 unless set |
| `hideUI` | Interface elements to hide, such as `hints`, `arrows`, `label`, `badges` |
| `showTools` | Tools in the second row, such as `shutdown`, `reboot`, `firmware` |

Every option, with its type and default: [docs/OPTIONS.md](docs/OPTIONS.md).

## Other operating systems

rEFInd finds other operating systems on all drives by itself. For explicit
control, define the entries:

```nix
boot.loader.refind.extraEntries = [
  {
    name = "Windows";
    loader = "\\EFI\\Microsoft\\Boot\\bootmgfw.efi";
    ostype = "Windows";
  }
];
```

## Themes

The overlay provides `pkgs.refind-theme-minimal` and
`pkgs.refind-theme-regular`. Package any other theme with `mkRefindTheme`:

```nix
boot.loader.refind.theme = pkgs.mkRefindTheme {
  name = "my-theme";
  src = pkgs.fetchFromGitHub { owner = "..."; repo = "..."; rev = "..."; hash = "..."; };
  description = "My custom rEFInd theme";
};
```

The build runs 12 security checks on the theme and fails when one does not
pass. A theme that uses JPEG or ICNS images must convert them to PNG. A theme's
own `hideui` and `showtools` lines are dropped on the way to the ESP, because
those two are set through `hideUI` and `showTools`.

## Next to systemd-boot

`allowCoexistWithSystemdBoot` lets both boot loaders be enabled, and
`shareSystemdBootKernels` gives them one set of kernels on the ESP. See
[docs/DESIGN.md](docs/DESIGN.md#sharing-kernels-with-systemd-boot).

## Known limits

- rEFInd 0.14.2 shows duplicate tool entries. This affects all distributions.
  Downgrade rEFInd to 0.14.0.2, or use `hideUI` to reduce clutter.
- Each NixOS generation copies a kernel (about 12 MB) and an initrd (25 to
  200 MB) to the ESP. With NVIDIA drivers the initrd is about 192 MB, so a
  500 MB ESP holds only 2 or 3 generations. Set `maxGenerations` accordingly.
- `extraConfig` bypasses all validation. Use it only for what no option covers.
- A sub-entry of `extraEntries` writes only its `name`, `loader`, `initrd` and
  `options`. Its `icon`, `volume`, `ostype` and `graphics` are ignored.

## When something does not work

If rEFInd fails, use your firmware's boot menu (F12, DEL, or Option/Alt on a
Mac) to select the old boot loader's entry.

## More

- [docs/DESIGN.md](docs/DESIGN.md): how it writes to the ESP, the theme checks
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): what is packaged, the flake checks
- [SECURITY.md](SECURITY.md): how to report a vulnerability

## License

The packaging in this repository is MIT, see [LICENSE](LICENSE). `refind-theme-regular` declares GPL-3.0-only. `refind-theme-minimal` declares no licence and takes the `mkRefindTheme` default, MIT. rEFInd itself comes from nixpkgs, which declares it GPL-3.0-or-later.
