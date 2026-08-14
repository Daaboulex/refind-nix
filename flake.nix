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
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.25.0";
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
      flake.overlays.default = import ./overlay.nix { inherit self; };

      perSystem =
        { system, pkgs, ... }:
        let
          themePkgs = pkgs.extend self.overlays.default;
          throws = x: !(builtins.tryEval (builtins.seq x x)).success;
          mkTest =
            modules:
            nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                self.nixosModules.default
                { system.stateVersion = nixpkgs.lib.trivial.release; }
              ]
              ++ modules;
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
          externalInstallerBase = {
            boot.loader.external = {
              enable = true;
              installHook = "${pkgs.writeShellScript "fake-external-install" "echo external-installer-ran"}";
            };
          };
          # Follows the real install path — the bootloader hook the system
          # would run — to the installer's own config, so a check sees what
          # the installer sees rather than what the option tree claims.
          installerConfigOf =
            testSystem: name:
            pkgs.runCommand name { hook = testSystem.config.system.build.installBootLoader; } ''
              json=""
              for candidate in "$hook" $(grep -oE '/nix/store/[a-z0-9]{32}-[^"'"'"' )]*' "$hook" | sort -u); do
                [ -f "$candidate" ] || continue
                found=$(grep -oE '/nix/store/[a-z0-9]{32}-refind-install\.json' "$candidate" | head -1 || true)
                if [ -n "$found" ]; then json="$found"; break; fi
              done
              [ -n "$json" ] || { echo "FAIL: install hook $hook does not reach a refind-install.json"; exit 1; }
              cp "$json" $out
            '';
          # Names the assertion that fired, not merely that something threw —
          # an unconfigured test system throws for its own reasons.
          failedAssertionsOf =
            testSystem:
            builtins.concatStringsSep "\n" (
              map (a: a.message) (builtins.filter (a: !a.assertion) testSystem.config.assertions)
            );
          validConf = ''
            banner background.png
            icons_dir icons
          '';
        in
        {
          packages.refind-theme-minimal = themePkgs.refind-theme-minimal;
          packages.refind-theme-regular = themePkgs.refind-theme-regular;
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

            eval-uki-native-installer-config =
              let
                testSystem = mkTest [
                  minimalBase
                  externalInstallerBase
                  {
                    boot.loader.refind = {
                      allowCoexistWithExternalInstaller = true;
                      generateNixosEntries = false;
                      manageNvram = false;
                      secureBoot.enable = true;
                    };
                  }
                ];
              in
              pkgs.runCommand "eval-uki-native-installer-config"
                { json = installerConfigOf testSystem "uki-native-install-json"; }
                ''
                  grep -q '"generateNixosEntries":false' "$json" || { echo "FAIL: generation entries still generated"; cat "$json"; exit 1; }
                  grep -q '"manageNvram":false' "$json" || { echo "FAIL: installer would still rewrite NVRAM"; exit 1; }
                  grep -q '"pkiBundle":"/var/lib/sbctl"' "$json" || { echo "FAIL: sbctl PKI bundle not wired"; exit 1; }
                  grep -q '"sbctlPath":"/nix/store/' "$json" || { echo "FAIL: sbctl package not wired"; exit 1; }
                  touch $out
                '';

            eval-timeout-is-refind-own =
              let
                testSystem = mkTest [
                  minimalBase
                  {
                    boot.loader.timeout = 30;
                    boot.loader.refind.timeout = 5;
                  }
                ];
              in
              pkgs.runCommand "eval-timeout-is-refind-own"
                { json = installerConfigOf testSystem "timeout-install-json"; }
                ''
                  grep -q '"timeout":5' "$json" || { echo "FAIL: boot.loader.timeout overrode the explicit rEFInd timeout"; cat "$json"; exit 1; }
                  touch $out
                '';

            eval-timeout-follows-loader-default =
              let
                testSystem = mkTest [
                  minimalBase
                  { boot.loader.timeout = 30; }
                ];
              in
              pkgs.runCommand "eval-timeout-follows-loader-default"
                { json = installerConfigOf testSystem "timeout-default-install-json"; }
                ''
                  grep -q '"timeout":30' "$json" || { echo "FAIL: unset rEFInd timeout must follow boot.loader.timeout"; cat "$json"; exit 1; }
                  touch $out
                '';

            eval-default-installer-config =
              let
                testSystem = mkTest [ minimalBase ];
              in
              pkgs.runCommand "eval-default-installer-config"
                { json = installerConfigOf testSystem "default-install-json"; }
                ''
                  grep -q '"generateNixosEntries":true' "$json" || { echo "FAIL: default must still generate generation entries"; exit 1; }
                  grep -q '"manageNvram":true' "$json" || { echo "FAIL: default must still manage NVRAM"; exit 1; }
                  grep -q '"sign":null' "$json" || { echo "FAIL: signing must be off by default"; exit 1; }
                  touch $out
                '';

            wiring-chains-after-external-installer =
              let
                testSystem = mkTest [
                  minimalBase
                  externalInstallerBase
                  { boot.loader.refind.allowCoexistWithExternalInstaller = true; }
                ];
              in
              pkgs.runCommand "wiring-chains-after-external-installer"
                { hook = testSystem.config.system.build.installBootLoader; }
                ''
                  grep -q 'fake-external-install' "$hook" || { echo "FAIL: external installer not chained — it would never run"; cat "$hook"; exit 1; }
                  grep -q 'refind-install' "$hook" || { echo "FAIL: rEFInd installer not chained — it would never run"; cat "$hook"; exit 1; }
                  grep -q '^set -eu' "$hook" || { echo "FAIL: chained install does not abort on a failing installer"; exit 1; }
                  touch $out
                '';

            assert-rejects-sdboot-coexist-without-sdboot =
              let
                testSystem = mkTest [
                  minimalBase
                  { boot.loader.refind.allowCoexistWithSystemdBoot = true; }
                ];
              in
              pkgs.runCommand "assert-rejects-sdboot-coexist-without-sdboot"
                {
                  failed = failedAssertionsOf testSystem;
                }
                ''
                  grep -q 'systemd-boot.enable. is false' <<< "$failed" || { echo "FAIL: the silent no-op guard did not fire — rEFInd would never install. Failing assertions: $failed"; exit 1; }
                  touch $out
                '';

            assert-rejects-external-coexist-without-external =
              let
                testSystem = mkTest [
                  minimalBase
                  { boot.loader.refind.allowCoexistWithExternalInstaller = true; }
                ];
              in
              pkgs.runCommand "assert-rejects-external-coexist-without-external"
                {
                  failed = failedAssertionsOf testSystem;
                }
                ''
                  grep -q 'requires an external bootloader installer' <<< "$failed" || { echo "FAIL: coexistence with a missing external installer accepted. Failing assertions: $failed"; exit 1; }
                  touch $out
                '';

            assert-rejects-lanzaboote-without-coexist =
              let
                testSystem = mkTest [
                  minimalBase
                  (
                    { lib, ... }:
                    {
                      options.boot.lanzaboote.enable = lib.mkEnableOption "lanzaboote stand-in";
                      config.boot.lanzaboote.enable = true;
                    }
                  )
                ];
              in
              pkgs.runCommand "assert-rejects-lanzaboote-without-coexist"
                {
                  failed = failedAssertionsOf testSystem;
                }
                ''
                  grep -q 'lanzaboote is enabled' <<< "$failed" || { echo "FAIL: lanzaboote install-slot conflict accepted. Failing assertions: $failed"; exit 1; }
                  touch $out
                '';

            theme-paths-point-at-deployed-dir =
              pkgs.runCommand "theme-paths-point-at-deployed-dir"
                {
                  minimal = themePkgs.refind-theme-minimal;
                  regular = themePkgs.refind-theme-regular;
                }
                ''
                  for theme in "$minimal" "$regular"; do
                    while read -r directive value; do
                      case "$value" in
                        themes/active/*) ;;
                        *) echo "FAIL: $theme theme.conf $directive points at $value, not the deployed themes/active dir"; exit 1 ;;
                      esac
                    done < <(grep -E '^[[:space:]]*(banner|icons_dir|selection_big|selection_small|font)[[:space:]]' "$theme/theme.conf")
                  done
                  touch $out
                '';

            theme-regular-selection-present =
              pkgs.runCommand "theme-regular-selection-present" { regular = themePkgs.refind-theme-regular; }
                ''
                  while read -r directive value; do
                    target="$regular/''${value#themes/active/}"
                    [ -e "$target" ] || { echo "FAIL: theme.conf $directive references $value, which the theme does not ship"; exit 1; }
                  done < <(grep -E '^[[:space:]]*(banner|icons_dir|selection_big|selection_small|font)[[:space:]]' "$regular/theme.conf")
                  [ -f "$regular/icons/os_nixos.png" ] || { echo "FAIL: NixOS icon missing"; exit 1; }
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
