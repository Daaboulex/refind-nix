# refind — declarative rEFInd bootloader module for NixOS.
{
  self,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.boot.loader.refind;
  efi = config.boot.loader.efi;

  refindInstallConfig = pkgs.writeText "refind-install.json" (
    builtins.toJSON {
      nixPath = config.nix.package;
      efiBootMgrPath = pkgs.efibootmgr;
      refindPath = cfg.package;
      efiMountPoint = efi.efiSysMountPoint;
      canTouchEfiVariables = efi.canTouchEfiVariables;
      efiRemovable = cfg.efiInstallAsRemovable;
      maxGenerations = if cfg.maxGenerations == null then 0 else cfg.maxGenerations;
      hostArchitecture = pkgs.stdenv.hostPlatform.parsed.cpu;
      timeout = if config.boot.loader.timeout != null then config.boot.loader.timeout else cfg.timeout;
      extraConfig = cfg.extraConfig;
      extraEntries = map (e: {
        inherit (e)
          name
          loader
          initrd
          options
          volume
          ostype
          graphics
          disabled
          ;
        icon = if e.icon != null then toString e.icon else null;
        subEntries = map (s: {
          inherit (s)
            name
            loader
            initrd
            options
            volume
            ostype
            graphics
            disabled
            ;
          icon = if s.icon != null then toString s.icon else null;
        }) e.subEntries;
      }) cfg.extraEntries;
      additionalFiles = cfg.additionalFiles;
      defaultSelection = cfg.defaultSelection;
      hideUI = cfg.hideUI;
      showTools = cfg.showTools;
      bannerScale = cfg.bannerScale;
      textOnly = cfg.textOnly;
      theme = if cfg.theme != null then toString cfg.theme else null;
      resolution = cfg.resolution;
      scanfor = cfg.scanfor;
      dontScanDirs = cfg.dontScanDirs;
      useGraphicsFor = cfg.useGraphicsFor;
      enableMouse = cfg.enableMouse;
      enableTouch = cfg.enableTouch;
      graceful = cfg.graceful;
    }
  );

  refindInstaller = pkgs.replaceVarsWith {
    src = ../installer/refind-install.py;
    isExecutable = true;
    replacements = {
      python3 = pkgs.python3.withPackages (ps: [ ps.psutil ]);
      configPath = refindInstallConfig;
    };
  };
in
{
  # Disables upstream refind module to prevent option conflicts.
  # Side effect: importing this module removes upstream boot.loader.refind even when enable = false.
  disabledModules = [ "system/boot/loader/refind/refind.nix" ];

  options.boot.loader.refind = {
    enable = lib.mkEnableOption "rEFInd boot manager";

    package = lib.mkPackageOption pkgs "refind" { };

    timeout = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Timeout in seconds before auto-boot.";
    };

    maxGenerations = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 50;
      description = "Maximum generations in boot menu. null = unlimited.";
    };

    defaultSelection = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[^\n\r]+");
      default = null;
      description = "Default boot entry. null = most recent. Only written if set.";
    };

    efiInstallAsRemovable = lib.mkEnableOption null // {
      default = !efi.canTouchEfiVariables;
      defaultText = lib.literalExpression "!config.boot.loader.efi.canTouchEfiVariables";
      description = "Install to EFI/BOOT/bootx64.efi. Required when NVRAM writes fail.";
    };

    theme = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to rEFInd theme directory in the Nix store.";
      example = lib.literalExpression ''"''${pkgs.refind-theme-minimal}"'';
    };

    resolution = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[^\n\r]+");
      default = null;
      description = "Screen resolution (e.g. \"1920x1080\" or \"max\").";
      example = "1920x1080";
    };

    hideUI = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "banner"
          "label"
          "singleuser"
          "safemode"
          "hwtest"
          "arrows"
          "hints"
          "editor"
          "badges"
          "funcs"
          "selection"
          "all"
        ]
      );
      default = [ ];
      description = "UI elements to hide.";
    };

    showTools = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "shell"
          "gptsync"
          "apple_recovery"
          "windows_recovery"
          "mok_tool"
          "fwupdate"
          "memtest"
          "about"
          "exit"
          "shutdown"
          "reboot"
          "firmware"
          "hidden_tags"
          "netboot"
          "bootorder"
          "csr_rotate"
          "install"
        ]
      );
      default = [
        "shutdown"
        "reboot"
        "firmware"
      ];
      description = "Tool entries in the second row. Order controls display order.";
    };

    bannerScale = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "noscale"
          "fillscreen"
        ]
      );
      default = null;
      description = "Banner scaling mode. null = theme or rEFInd default.";
    };

    textOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Text-only mode. Disables all theming.";
    };

    scanfor = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "internal"
          "external"
          "optical"
          "manual"
          "hdbios"
          "biosexternal"
          "cd"
          "firmware"
        ]
      );
      default = [ ];
      description = "Boot entry types to scan for. Empty = rEFInd default.";
    };

    dontScanDirs = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[^\n\r,]+");
      default = [
        "EFI/nixos"
        (if cfg.efiInstallAsRemovable then "efi/boot/kernels" else "efi/refind/kernels")
      ];
      defaultText = lib.literalExpression ''[ "EFI/nixos" (if efiInstallAsRemovable then "efi/boot/kernels" else "efi/refind/kernels") ]'';
      description = "Directories to exclude from boot entry scanning.";
    };

    useGraphicsFor = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "linux"
          "windows"
          "osx"
        ]
      );
      default = [ ];
      description = "OS types to boot in graphics mode. Empty = rEFInd default.";
    };

    enableMouse = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable mouse support in rEFInd.";
    };

    enableTouch = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable touchscreen support in rEFInd.";
    };

    graceful = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Don't fail if the ESP is not mounted. Useful for first installs or removable media.";
    };

    extraEntries = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Menu entry label displayed in rEFInd.";
            };
            loader = lib.mkOption {
              type = lib.types.str;
              description = "EFI binary path (e.g. \\EFI\\Microsoft\\Boot\\bootmgfw.efi).";
            };
            initrd = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "initrd path on the ESP. null = omit.";
            };
            options = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Kernel/loader options string. null = omit.";
            };
            icon = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Path to icon file in the Nix store. null = omit.";
            };
            volume = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Volume label or GUID for the loader. null = omit.";
            };
            ostype = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.enum [
                  "Linux"
                  "Windows"
                  "MacOS"
                ]
              );
              default = null;
              description = "OS type hint for rEFInd icon selection. null = omit.";
            };
            graphics = lib.mkOption {
              type = lib.types.nullOr lib.types.bool;
              default = null;
              description = "Force graphics mode on/off for this entry. null = omit.";
            };
            disabled = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Exclude this entry from the generated config.";
            };
            subEntries = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    name = lib.mkOption {
                      type = lib.types.str;
                      description = "Submenu entry label.";
                    };
                    loader = lib.mkOption {
                      type = lib.types.str;
                      description = "EFI binary path for this submenu entry.";
                    };
                    initrd = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "initrd path for this submenu entry. null = omit.";
                    };
                    options = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Options string for this submenu entry. null = omit.";
                    };
                    icon = lib.mkOption {
                      type = lib.types.nullOr lib.types.path;
                      default = null;
                      description = "Icon path for this submenu entry. null = omit.";
                    };
                    volume = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Volume for this submenu entry. null = omit.";
                    };
                    ostype = lib.mkOption {
                      type = lib.types.nullOr (
                        lib.types.enum [
                          "Linux"
                          "Windows"
                          "MacOS"
                        ]
                      );
                      default = null;
                      description = "OS type for this submenu entry. null = omit.";
                    };
                    graphics = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      default = null;
                      description = "Graphics mode override for this submenu entry. null = omit.";
                    };
                    disabled = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = "Exclude this submenu entry from the generated config.";
                    };
                  };
                }
              );
              default = [ ];
              description = "Submenu entries nested under this entry (one level only).";
            };
          };
        }
      );
      default = [ ];
      description = "Manual boot entries for non-NixOS OSes (Windows, macOS, other Linux). Each becomes a rEFInd menuentry block.";
      example = lib.literalExpression ''
        [
          {
            name = "Windows";
            loader = "\\EFI\\Microsoft\\Boot\\bootmgfw.efi";
            icon = "\\EFI\\refind\\icons\\os_win.png";
            ostype = "Windows";
          }
        ]
      '';
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Raw lines prepended to refind.conf. WARNING: bypasses all validation — can inject include, menuentry, or any rEFInd directive. Only use for directives not covered by typed options.";
    };

    additionalFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Extra files to copy to the ESP rEFInd directory. Keys must be relative paths.";
      example = lib.literalExpression ''{ "tools/memtest.efi" = "''${pkgs.memtest86plus.efi}/BOOTX64.efi"; }'';
    };

    allowCoexistWithSystemdBoot = lib.mkEnableOption null // {
      description = ''
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
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    let
      coexistingWithSystemdBoot =
        config.boot.loader.systemd-boot.enable && cfg.allowCoexistWithSystemdBoot;
    in
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !config.boot.loader.systemd-boot.enable || cfg.allowCoexistWithSystemdBoot;
            message = ''
              refind-nix: rEFInd and systemd-boot are both enabled. Set
              `boot.loader.refind.allowCoexistWithSystemdBoot = true` to
              opt-in to the hybrid chainload pattern (refind acts as OS
              picker; systemd-boot owns the NixOS gen menu).
            '';
          }
          {
            assertion = !config.boot.loader.grub.enable;
            message = "refind-nix: rEFInd and GRUB cannot both be enabled.";
          }
          {
            assertion = pkgs.stdenv.hostPlatform.isEfi;
            message = "refind-nix: rEFInd requires a UEFI platform.";
          }
          {
            assertion = !(cfg.efiInstallAsRemovable && efi.canTouchEfiVariables);
            message = "refind-nix: efiInstallAsRemovable and canTouchEfiVariables cannot both be true.";
          }
        ];

      }

      # Default wiring: refind-nix claims the bootloader install slot via
      # boot.loader.external. Used when refind is the only bootloader.
      (lib.mkIf (!coexistingWithSystemdBoot) {
        system.boot.loader.id = "refind";

        # Override boot.loader.external's mkDefault false — our installer
        # handles initrdSecrets.
        boot.loader.supportsInitrdSecrets = true;

        boot.loader.external = {
          enable = true;
          installHook = refindInstaller;
        };
      })

      # Coexistence wiring: systemd-boot owns `system.build.installBootLoader`
      # (its installer is the canonical NixOS bootloader install path). We
      # hook refind's installer into systemd-boot's `extraInstallCommands`
      # so it runs as a post-step inside the same activation — both
      # bootloader states refresh atomically on every `nixos-rebuild
      # switch`, with no conflict on installBootLoader.
      #
      # `boot.loader.external` is NOT enabled in this mode (it would fight
      # systemd-boot for the install slot). refind-nix's `refind-install.py`
      # runs via systemd-boot's documented post-install hook instead.
      (lib.mkIf coexistingWithSystemdBoot {
        boot.loader.systemd-boot.extraInstallCommands = ''
          ${refindInstaller} "$@"
        '';
      })
    ]
  );
}
