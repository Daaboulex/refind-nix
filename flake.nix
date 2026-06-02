{
  description = "Declarative rEFInd bootloader for NixOS — typed options, themes, security validation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.3.2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      self,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ inputs.std.flakeModules.base ];

      flake.nixosModules.default = import ./module.nix { inherit self; };
      flake.overlays.default = import ./overlays/default.nix { inherit self; };

      perSystem =
        { system, pkgs, ... }:
        let
          themePkgs = pkgs.extend self.overlays.default;
          throws = x: !(builtins.tryEval (builtins.seq x x)).success;
          mkTest =
            modules:
            nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [ self.nixosModules.default ] ++ modules;
            };
          minimalBase = {
            boot.loader.efi.canTouchEfiVariables = true;
            boot.loader.refind.enable = true;
            fileSystems."/" = {
              device = "/dev/sda1";
              fsType = "ext4";
            };
            boot.loader.efi.efiSysMountPoint = "/boot";
          };
          validConf = ''
            banner background.png
            icons_dir icons
          '';
        in
        {
          packages.refind-theme-minimal = themePkgs.refind-theme-minimal;
          packages.default = themePkgs.refind-theme-minimal;

          # rEFInd's bespoke option-eval, assertion-rejection, and theme-security
          # checks — richer than the generic std module-eval, so they stay.
          checks = {
            eval-defaults =
              let
                testSystem = mkTest [ minimalBase ];
                enabled = builtins.toJSON testSystem.config.boot.loader.refind.enable;
              in
              pkgs.runCommand "eval-defaults" { inherit enabled; } ''
                [[ "$enabled" == "true" ]] || { echo "FAIL: expected enable=true, got $enabled"; exit 1; }
                touch $out
              '';

            eval-all-options =
              let
                testSystem = mkTest [
                  minimalBase
                  {
                    boot.loader.refind = {
                      timeout = 5;
                      maxGenerations = 10;
                      resolution = "1920x1080";
                      hideUI = [ "editor" ];
                      showTools = [ "shutdown" ];
                      bannerScale = "noscale";
                      textOnly = true;
                      scanfor = [ "manual" ];
                      dontScanDirs = [ "EFI/test" ];
                      useGraphicsFor = [ "linux" ];
                      enableMouse = true;
                      enableTouch = true;
                      graceful = true;
                      defaultSelection = "1";
                      extraEntries = [
                        {
                          name = "Windows";
                          loader = ''\\EFI\\Microsoft\\Boot\\bootmgfw.efi'';
                          ostype = "Windows";
                        }
                      ];
                    };
                  }
                ];
                timeout = builtins.toJSON testSystem.config.boot.loader.refind.timeout;
                maxGenerations = builtins.toJSON testSystem.config.boot.loader.refind.maxGenerations;
              in
              pkgs.runCommand "eval-all-options" { inherit timeout maxGenerations; } ''
                [[ "$timeout" == "5" ]] || { echo "FAIL: timeout expected 5, got $timeout"; exit 1; }
                [[ "$maxGenerations" == "10" ]] || { echo "FAIL: maxGenerations expected 10, got $maxGenerations"; exit 1; }
                touch $out
              '';

            eval-extra-entries =
              let
                testSystem = mkTest [
                  minimalBase
                  {
                    boot.loader.refind.extraEntries = [
                      {
                        name = "Windows";
                        loader = ''\\EFI\\Microsoft\\Boot\\bootmgfw.efi'';
                        ostype = "Windows";
                        subEntries = [
                          {
                            name = "Windows (safe mode)";
                            loader = ''\\EFI\\Microsoft\\Boot\\bootmgfw.efi'';
                            options = "/safeboot:network";
                          }
                        ];
                      }
                    ];
                  }
                ];
                entryCount = builtins.toJSON (builtins.length testSystem.config.boot.loader.refind.extraEntries);
              in
              pkgs.runCommand "eval-extra-entries" { inherit entryCount; } ''
                [[ "$entryCount" == "1" ]] || { echo "FAIL: expected 1 entry, got $entryCount"; exit 1; }
                touch $out
              '';

            assert-rejects-systemd-boot =
              let
                testSystem = mkTest [
                  minimalBase
                  { boot.loader.systemd-boot.enable = true; }
                ];
                didThrow = builtins.toJSON (throws testSystem.config.system.build.toplevel);
              in
              pkgs.runCommand "assert-rejects-systemd-boot" { inherit didThrow; } ''
                [[ "$didThrow" == "true" ]] || { echo "FAIL: expected assertion to throw"; exit 1; }
                touch $out
              '';

            assert-rejects-grub =
              let
                testSystem = mkTest [
                  minimalBase
                  {
                    boot.loader.grub.enable = true;
                    boot.loader.grub.device = "/dev/sda";
                  }
                ];
                didThrow = builtins.toJSON (throws testSystem.config.system.build.toplevel);
              in
              pkgs.runCommand "assert-rejects-grub" { inherit didThrow; } ''
                [[ "$didThrow" == "true" ]] || { echo "FAIL: expected assertion to throw"; exit 1; }
                touch $out
              '';

            assert-rejects-removable-with-nvram =
              let
                testSystem = mkTest [
                  {
                    boot.loader.efi.canTouchEfiVariables = true;
                    boot.loader.refind = {
                      enable = true;
                      efiInstallAsRemovable = true;
                    };
                    fileSystems."/" = {
                      device = "/dev/sda1";
                      fsType = "ext4";
                    };
                    boot.loader.efi.efiSysMountPoint = "/boot";
                  }
                ];
                didThrow = builtins.toJSON (throws testSystem.config.system.build.toplevel);
              in
              pkgs.runCommand "assert-rejects-removable-with-nvram" { inherit didThrow; } ''
                [[ "$didThrow" == "true" ]] || { echo "FAIL: expected assertion to throw"; exit 1; }
                touch $out
              '';

            assert-accepts-valid =
              let
                testSystem = mkTest [ minimalBase ];
                didThrow = builtins.toJSON (throws testSystem.config.system.build.toplevel);
              in
              pkgs.runCommand "assert-accepts-valid" { inherit didThrow; } ''
                [[ "$didThrow" == "false" ]] || { echo "FAIL: valid config should not throw"; exit 1; }
                touch $out
              '';

            security-rejects-pe =
              let
                badSrc = themePkgs.runCommand "bad-theme-pe" { } ''
                  mkdir -p $out
                  printf 'MZ\x90\x00' > $out/background.png
                  cat > $out/theme.conf << 'CONF'
                  ${validConf}
                  CONF
                '';
              in
              themePkgs.testers.testBuildFailure (
                themePkgs.mkRefindTheme {
                  name = "test-pe";
                  src = badSrc;
                }
              );

            security-rejects-efi-ext =
              let
                badSrc = themePkgs.runCommand "bad-theme-efi" { } ''
                  mkdir -p $out
                  printf '\x00\x00' > $out/tool.efi
                  cat > $out/theme.conf << 'CONF'
                  ${validConf}
                  CONF
                '';
              in
              themePkgs.testers.testBuildFailure (
                themePkgs.mkRefindTheme {
                  name = "test-efi";
                  src = badSrc;
                }
              );

            security-rejects-oversized =
              let
                badSrc = themePkgs.runCommand "bad-theme-oversized" { } ''
                  mkdir -p $out
                  dd if=/dev/zero of=$out/background.png bs=1M count=6 2>/dev/null
                  cat > $out/theme.conf << 'CONF'
                  ${validConf}
                  CONF
                '';
              in
              themePkgs.testers.testBuildFailure (
                themePkgs.mkRefindTheme {
                  name = "test-oversized";
                  src = badSrc;
                }
              );

            security-rejects-unknown-directive =
              let
                badSrc = themePkgs.runCommand "bad-theme-directive" { } ''
                  mkdir -p $out
                  cat > $out/theme.conf << 'CONF'
                  scanfor internal
                  CONF
                '';
              in
              themePkgs.testers.testBuildFailure (
                themePkgs.mkRefindTheme {
                  name = "test-directive";
                  src = badSrc;
                }
              );

            security-rejects-include =
              let
                badSrc = themePkgs.runCommand "bad-theme-include" { } ''
                  mkdir -p $out
                  cat > $out/theme.conf << 'CONF'
                  include /evil/config.conf
                  CONF
                '';
              in
              themePkgs.testers.testBuildFailure (
                themePkgs.mkRefindTheme {
                  name = "test-include";
                  src = badSrc;
                }
              );

            security-rejects-path-traversal =
              let
                badSrc = themePkgs.runCommand "bad-theme-traversal" { } ''
                  mkdir -p $out
                  cat > $out/theme.conf << 'CONF'
                  banner ../../evil.png
                  CONF
                '';
              in
              themePkgs.testers.testBuildFailure (
                themePkgs.mkRefindTheme {
                  name = "test-traversal";
                  src = badSrc;
                }
              );

            security-rejects-symlink =
              let
                badSrc = themePkgs.runCommand "bad-theme-symlink" { } ''
                  mkdir -p $out
                  touch $out/real.png
                  ln -s $out/real.png $out/evil.png
                  cat > $out/theme.conf << 'CONF'
                  ${validConf}
                  CONF
                '';
              in
              themePkgs.testers.testBuildFailure (
                themePkgs.mkRefindTheme {
                  name = "test-symlink";
                  src = badSrc;
                }
              );
          };
        };
    };
}
