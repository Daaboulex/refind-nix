# Development

## What is packaged

| | |
|---|---|
| Project | Extends the nixpkgs rEFInd installer (`nixos/modules/system/boot/loader/refind/refind-install.py`), installs `pkgs.refind`, and packages the themes [EvanPurkhiser/rEFInd-minimal](https://github.com/EvanPurkhiser/rEFInd-minimal) and [bobafetthotmail/refind-theme-regular](https://github.com/bobafetthotmail/refind-theme-regular) |
| License | See the License section of the [README](../README.md) |
| Tracked | Nothing is tracked. The two themes are pinned to fixed revisions |

`.github/update.json` declares no upstream. A theme moves only when its `rev`
and `hash` are changed in `themes/minimal.nix` or `themes/regular.nix`. The
flake follows the `nixos-unstable` branch of nixpkgs, and `pkgs.refind` comes
from whatever nixpkgs the consumer passes in.

## Layout

- `module.nix` declares every option under `boot.loader.refind` with its type,
  default and description, and wires the installer into the system.
- `installer/refind-install.py` is the installer that runs at
  `nixos-rebuild switch`.
- `lib/mkRefindTheme.nix` builds a theme and runs the 12 security checks.
- `themes/` holds the two packaged themes.
- `overlay.nix` exposes `mkRefindTheme`, `refind-themes`,
  `refind-theme-minimal` and `refind-theme-regular`.

The flake exports `nixosModules.default`, `overlays.default` and, per system,
`packages.refind-theme-minimal`, `packages.refind-theme-regular` and
`packages.default`, which is the minimal theme.

## Checks

```bash
nix flake check --no-eval-cache
```

The checks are declared in `flake.nix`: eval tests, assertion tests and
security unit tests.

- `eval-*` evaluate a system with the module and read the result, several of
  them from the installer's own JSON config rather than from the option tree.
- `assert-*` prove a conflicting configuration is refused and a valid one is
  accepted.
- `wiring-chains-after-external-installer` proves the chained install script
  calls both the external installer and the rEFInd one, and aborts when either
  fails.
- `theme-*` prove the packaged themes point at the deployed `themes/active`
  directory, and that the regular theme ships the files its `theme.conf` names.
- `installer-entry-paths-resolve-from-esp-root` runs the installer's entry
  generation against a made-up ESP.
- `security-rejects-*` each build a bad theme and expect `mkRefindTheme` to
  fail.

None of the checks boots a machine.

## Tooling and CI

The dev shell and the hooks come from `inputs.std.flakeModules.base`, the
nix-packaging-standard. `.envrc` loads the flake through direnv. Run
`direnv allow` once per clone.

`.github/workflows/ci.yml` runs the standard's `package-ci.yml` on every push
to `main` or `master`, on every pull request and on demand.
`.github/workflows/maintenance.yml` runs the standard's
`package-maintenance.yml` on a schedule.
