#!@python3@/bin/python3 -B
#
# refind-install.py — extended nixpkgs rEFInd installer.
# Base: nixpkgs/nixos/modules/system/boot/loader/refind/refind-install.py
# Extensions: theme deployment, dont_scan_dirs, #452075 fix, #453812 fix, orphan scan.

from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import ctypes
import ctypes.util
import fcntl
import json
import os
import psutil
import re
import shutil
import subprocess
import sys


SUBPROCESS_TIMEOUT = 30

libc_name = ctypes.util.find_library('c')
if not libc_name:
    libc_name = 'libc.so.6'
libc = ctypes.CDLL(libc_name, use_errno=True)

refind_dir = None
install_config = None


def load_config() -> dict:
    try:
        with open('@configPath@', 'r') as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f'refind-install: failed to load config: {e}', file=sys.stderr)
        sys.exit(1)


def config(*path: str) -> Optional[Any]:
    result = install_config
    try:
        for component in path:
            result = result[component]
    except KeyError:
        raise KeyError(f'refind config missing key: {".".join(path)}')
    return result


def sanitize_refind_value(s: str) -> str:
    """Remove characters that break rEFInd config syntax (no escape mechanism exists)."""
    return s.replace('"', '').replace('\n', '').replace('\r', '')


def get_system_path(profile: str = 'system', gen: Optional[int] = None, spec: Optional[str] = None) -> str:
    basename = f'{profile}-{gen}-link' if gen is not None else profile
    profiles_dir = '/nix/var/nix/profiles'
    if profile == 'system':
        result = os.path.join(profiles_dir, basename)
    else:
        result = os.path.join(profiles_dir, 'system-profiles', basename)

    if spec is not None:
        result = os.path.join(result, 'specialisation', spec)

    return result


def get_profiles() -> List[str]:
    profiles_dir = '/nix/var/nix/profiles/system-profiles/'
    dirs = os.listdir(profiles_dir) if os.path.isdir(profiles_dir) else []
    return [path for path in dirs if not path.endswith('-link')]


def get_gens(profile: str = 'system') -> List[int]:
    nix_env = os.path.join(config('nixPath'), 'bin', 'nix-env')
    output = subprocess.check_output([
        nix_env, '--list-generations',
        '-p', get_system_path(profile),
        '--option', 'build-users-group', '',
    ], universal_newlines=True, timeout=SUBPROCESS_TIMEOUT)

    gen_lines = output.splitlines()
    gen_nums = [int(line.split()[0]) for line in gen_lines]

    max_gens = config('maxGenerations')
    if max_gens > 0:
        return gen_nums[-max_gens:]
    return gen_nums


paths = {}


def get_copied_path_uri(path: str, target: str) -> str:
    package_id = os.path.basename(os.path.dirname(path))
    suffix = os.path.basename(path)
    dest_file = f'{package_id}-{suffix}'
    dest_path = os.path.join(refind_dir, target, dest_file)

    if not os.path.exists(dest_path):
        copy_file(path, dest_path)
    else:
        paths[dest_path] = True

    if target:
        return os.path.join(target, dest_file)
    return dest_file


def get_kernel_uri(kernel_path: str) -> str:
    return get_copied_path_uri(kernel_path, "kernels")


def get_kernel_dest_path(kernel_path: str) -> str:
    package_id = os.path.basename(os.path.dirname(kernel_path))
    suffix = os.path.basename(kernel_path)
    return os.path.join(refind_dir, 'kernels', f'{package_id}-{suffix}')


@dataclass
class BootSpec:
    system: str
    init: str
    kernel: str
    kernelParams: List[str]
    label: str
    toplevel: str
    specialisations: Dict[str, "BootSpec"]
    initrd: str | None = None
    initrdSecrets: str | None = None


def bootjson_to_bootspec(bootjson: dict) -> BootSpec:
    specialisations = bootjson.get('org.nixos.specialisation.v1', {})
    specialisations = {k: bootjson_to_bootspec(v) for k, v in specialisations.items()}
    return BootSpec(
        **bootjson['org.nixos.bootspec.v1'],
        specialisations=specialisations,
    )


def config_entry(is_sub: bool, bootspec: BootSpec, label: str) -> str:
    label = sanitize_refind_value(label)
    entry = ""
    if is_sub:
        entry += 'sub'

    entry += f'menuentry "{label}" {{\n'
    entry += '  loader ' + get_kernel_uri(bootspec.kernel) + '\n'

    if bootspec.initrd:
        if bootspec.initrdSecrets:
            if not bootspec.initrdSecrets.startswith('/nix/store/'):
                print(f'error: initrdSecrets path outside Nix store: {bootspec.initrdSecrets}', file=sys.stderr)
                return ""
            initrd_dest = get_kernel_dest_path(bootspec.initrd)
            copy_file(bootspec.initrd, initrd_dest)
            try:
                subprocess.check_output(
                    [bootspec.initrdSecrets, initrd_dest],
                    stderr=subprocess.STDOUT,
                    timeout=SUBPROCESS_TIMEOUT,
                )
            except subprocess.CalledProcessError as e:
                print(f'warning: initrdSecrets failed for entry', file=sys.stderr)
                return ""
            initrd_uri = os.path.join('kernels', os.path.basename(initrd_dest))
        else:
            initrd_uri = get_kernel_uri(bootspec.initrd)
        entry += '  initrd ' + initrd_uri + '\n'

    safe_init = sanitize_refind_value(bootspec.init)
    safe_params = [sanitize_refind_value(p) for p in bootspec.kernelParams]
    entry += '  options "' + ' '.join(['init=' + safe_init] + safe_params).strip() + '"\n'
    entry += '}\n'
    return entry


def generate_config_entry(profile: str, gen: int, group_name: str) -> str:
    boot_json_path = os.path.join(get_system_path(profile, gen), 'boot.json')

    if not os.path.exists(boot_json_path):
        print(f"warning: generation {gen} has no boot.json, skipping")
        return ""

    with open(boot_json_path, 'r') as f:
        boot_json = json.load(f)
    boot_spec = bootjson_to_bootspec(boot_json)

    specialisation_list = list(boot_spec.specialisations.items())
    entry = ""

    if len(specialisation_list) > 0:
        default_entry = config_entry(True, boot_spec, 'Default')
        spec_entries = ""
        for spec, spec_boot_spec in specialisation_list:
            spec_entries += config_entry(True, spec_boot_spec, spec)

        if not default_entry and not spec_entries:
            print(f"warning: all entries for generation {gen} failed, skipping")
            return ""

        safe_group = sanitize_refind_value(group_name)
        entry += f'menuentry "NixOS {safe_group} Generation {gen}" {{\n'
        entry += default_entry
        entry += spec_entries
        entry += '}\n'
    else:
        entry = config_entry(False, boot_spec, f'NixOS {group_name} Generation {gen}')
    return entry


def generate_extra_entries() -> str:
    entries = config('extraEntries')
    result = ""
    for entry in entries:
        if entry.get('disabled', False):
            continue
        name = sanitize_refind_value(entry['name'])
        result += f'menuentry "{name}" {{\n'
        result += f'  loader {entry["loader"]}\n'
        if entry.get('volume'):
            result += f'  volume {entry["volume"]}\n'
        if entry.get('icon'):
            result += f'  icon {entry["icon"]}\n'
        if entry.get('ostype'):
            result += f'  ostype {entry["ostype"]}\n'
        if entry.get('graphics') is not None:
            result += f'  graphics {"on" if entry["graphics"] else "off"}\n'
        if entry.get('initrd'):
            result += f'  initrd {entry["initrd"]}\n'
        if entry.get('options'):
            result += f'  options "{sanitize_refind_value(entry["options"])}"\n'
        for sub in entry.get('subEntries', []):
            if sub.get('disabled', False):
                continue
            sub_name = sanitize_refind_value(sub['name'])
            result += f'  submenuentry "{sub_name}" {{\n'
            if sub.get('loader'):
                result += f'    loader {sub["loader"]}\n'
            if sub.get('initrd'):
                result += f'    initrd {sub["initrd"]}\n'
            if sub.get('options'):
                result += f'    options "{sanitize_refind_value(sub["options"])}"\n'
            result += '  }\n'
        result += '}\n\n'
    return result


def find_disk_device(part: str) -> str:
    part = os.path.realpath(part)
    part = part.removeprefix('/dev/')
    disk = os.path.realpath(os.path.join('/sys', 'class', 'block', part))
    disk = os.path.dirname(disk)
    return os.path.join('/dev', os.path.basename(disk))


def find_mounted_device(path: str) -> str:
    path = os.path.abspath(path)

    while not os.path.ismount(path):
        path = os.path.dirname(path)

    devices = [x for x in psutil.disk_partitions() if x.mountpoint == path]

    if len(devices) != 1:
        raise RuntimeError(
            f'Expected 1 device at {path}, found {len(devices)}: '
            f'{[d.device for d in devices]}'
        )
    return devices[0].device


def fsync_directory(path: str) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def copy_file(from_path: str, to_path: str):
    dirname = os.path.dirname(to_path)

    if not os.path.exists(dirname):
        os.makedirs(dirname)

    shutil.copyfile(from_path, to_path + ".tmp")
    fd = os.open(to_path + ".tmp", os.O_RDONLY)
    os.fsync(fd)
    os.close(fd)
    os.rename(to_path + ".tmp", to_path)
    fsync_directory(dirname)

    paths[to_path] = True


def validate_theme(theme_dir: str) -> None:
    """Runtime safety checks for themes not built with mkRefindTheme."""
    for dirpath, _, filenames in os.walk(theme_dir):
        for f in filenames:
            full = os.path.join(dirpath, f)
            if os.path.islink(full):
                raise RuntimeError(f"theme contains symlink: {full}")
            lower = f.lower()
            if lower.endswith('.efi'):
                raise RuntimeError(f"theme contains EFI file: {full}")
            if lower.endswith(('.jpg', '.jpeg', '.icns')):
                raise RuntimeError(f"theme contains JPEG/ICNS (use PNG): {full}")
            try:
                with open(full, 'rb') as fh:
                    if fh.read(2) == b'MZ':
                        raise RuntimeError(f"theme contains PE binary: {full}")
            except OSError:
                pass
            if os.path.getsize(full) > 5 * 1024 * 1024:
                raise RuntimeError(f"theme file exceeds 5MB: {full}")


def install_theme(theme_store_path: str) -> None:
    validate_theme(theme_store_path)
    themes_dir = os.path.join(refind_dir, 'themes')
    active_dir = os.path.join(themes_dir, 'active')
    active_new = os.path.join(themes_dir, 'active.new')
    active_old = os.path.join(themes_dir, 'active.old')

    if not os.path.exists(themes_dir):
        os.makedirs(themes_dir)

    if os.path.exists(active_new):
        shutil.rmtree(active_new)

    shutil.copytree(theme_store_path, active_new)

    for dirpath, _, filenames in os.walk(active_new):
        for f in filenames:
            paths[os.path.join(dirpath, f)] = True

    # Safe swap: old->backup, new->active, then cleanup backup
    if os.path.exists(active_old):
        shutil.rmtree(active_old)

    if os.path.exists(active_dir):
        os.rename(active_dir, active_old)

    os.rename(active_new, active_dir)
    fsync_directory(themes_dir)

    if os.path.exists(active_old):
        shutil.rmtree(active_old)

    for dirpath, _, filenames in os.walk(active_dir):
        for f in filenames:
            paths[os.path.join(dirpath, f)] = True


def validate_path_within(dest: str, base: str) -> None:
    dest = os.path.normpath(dest)
    base = os.path.normpath(base)
    if not (dest.startswith(base + os.sep) or dest == base):
        raise RuntimeError(
            f"path escapes target directory: {dest} is outside {base}"
        )


def install_bootloader() -> None:
    global refind_dir

    efi_mount = str(config('efiMountPoint'))
    if not os.path.ismount(efi_mount):
        if config('graceful'):
            print(f"warning: ESP not mounted at {efi_mount}, skipping installation", file=sys.stderr)
            return
        raise RuntimeError(f"ESP not mounted at {efi_mount}")

    # Exclusive lock prevents concurrent installs from corrupting ESP
    lock_path = os.path.join(efi_mount, '.refind-install.lock')
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)

    # FIX #452075: use same base dir for both efiRemovable and normal mode
    if config('efiRemovable'):
        refind_dir = os.path.join(efi_mount, 'efi', 'boot')
    else:
        refind_dir = os.path.join(efi_mount, 'efi', 'refind')

    if not os.path.exists(refind_dir):
        os.makedirs(refind_dir)
    else:
        for dir, dirs, files in os.walk(refind_dir, topdown=True):
            for file in files:
                paths[os.path.join(dir, file)] = False

    kernels_dir = os.path.join(refind_dir, 'kernels')
    if os.path.exists(kernels_dir):
        for dir, dirs, files in os.walk(kernels_dir, topdown=True):
            for file in files:
                paths[os.path.join(dir, file)] = False

    profiles = [('system', get_gens())]

    for profile in get_profiles():
        profiles += [(profile, get_gens(profile))]

    timeout = config('timeout')

    theme = config('theme')
    if theme:
        install_theme(theme)

    extra_config = str(config('extraConfig')).strip()
    config_file = "# refind.conf — generated by refind-nix\n"

    if extra_config:
        config_file += extra_config + '\n\n'

    # Theme include BEFORE module directives — theme provides defaults, options override
    if theme:
        config_file += 'include themes/active/theme.conf\n\n'

    config_file += f'timeout {timeout}\n'

    resolution = config('resolution')
    if resolution:
        config_file += f'resolution {sanitize_refind_value(resolution)}\n'

    banner_scale = config('bannerScale')
    if banner_scale:
        config_file += f'banner_scale {banner_scale}\n'

    text_only = config('textOnly')
    if text_only:
        config_file += 'textonly true\n'

    hide_ui = config('hideUI')
    if hide_ui:
        config_file += f'hideui {",".join(hide_ui)}\n'

    show_tools = config('showTools')
    if show_tools:
        config_file += f'showtools {",".join(show_tools)}\n'

    scanfor = config('scanfor')
    if scanfor:
        config_file += f'scanfor {",".join(scanfor)}\n'

    use_graphics_for = config('useGraphicsFor')
    if use_graphics_for:
        config_file += f'use_graphics_for {",".join(use_graphics_for)}\n'

    if config('enableMouse'):
        config_file += 'enable_mouse\n'

    if config('enableTouch'):
        config_file += 'enable_touch\n'

    dont_scan_dirs = config('dontScanDirs')
    if dont_scan_dirs:
        config_file += f'dont_scan_dirs {",".join(dont_scan_dirs)}\n'

    # FIX #453812: only write default_selection if explicitly set
    default_selection = config('defaultSelection')
    if default_selection:
        config_file += f'default_selection {sanitize_refind_value(default_selection)}\n'

    config_file += '\n# NixOS boot entries start here\n'

    for (profile, gens) in profiles:
        group_name = 'default profile' if profile == 'system' else f"profile '{profile}'"

        for gen in sorted(gens, key=lambda x: x, reverse=True):
            config_file += generate_config_entry(profile, gen, group_name)

    config_file += '\n# NixOS boot entries end here\n'

    extra = generate_extra_entries()
    if extra:
        config_file += '\n# Manual boot entries\n'
        config_file += extra

    config_file_path = os.path.join(refind_dir, 'refind.conf')
    config_content = config_file.strip()

    with open(f"{config_file_path}.tmp", 'w') as file:
        file.truncate()
        file.write(config_content)
        file.flush()
        os.fsync(file.fileno())
    os.rename(f"{config_file_path}.tmp", config_file_path)
    fsync_directory(os.path.dirname(config_file_path))

    paths[config_file_path] = True

    for dest_rel, source_path in config('additionalFiles').items():
        dest_path = os.path.normpath(os.path.join(refind_dir, dest_rel))
        validate_path_within(dest_path, refind_dir)
        copy_file(source_path, dest_path)

    cpu_family = config('hostArchitecture', 'family')
    if cpu_family == 'x86':
        if config('hostArchitecture', 'bits') == 32:
            boot_file = 'BOOTIA32.EFI'
            efi_file = 'refind_ia32.efi'
        elif config('hostArchitecture', 'bits') == 64:
            boot_file = 'BOOTX64.EFI'
            efi_file = 'refind_x64.efi'
        else:
            raise Exception(f'Unsupported x86 variant: {config("hostArchitecture", "bits")} bits')
    elif cpu_family == 'arm':
        if config('hostArchitecture', 'arch') == 'armv8-a' and config('hostArchitecture', 'bits') == 64:
            boot_file = 'BOOTAA64.EFI'
            efi_file = 'refind_aa64.efi'
        else:
            raise Exception(f'Unsupported CPU arch: {config("hostArchitecture", "arch")}')
    else:
        raise Exception(f'Unsupported CPU family: {cpu_family}')

    efi_path = os.path.join(config('refindPath'), 'share', 'refind', efi_file)
    # FIX #452075: EFI binary goes in same dir as config
    dest_path = os.path.join(refind_dir, boot_file if config('efiRemovable') else efi_file)

    copy_file(efi_path, dest_path)

    if not config('efiRemovable') and not config('canTouchEfiVariables'):
        print(
            'warning: canTouchEfiVariables is false and efiInstallAsRemovable is false.\n'
            '  The system may be unbootable without a NVRAM entry or fallback bootloader.',
            file=sys.stderr,
        )

    if config('canTouchEfiVariables'):
        if config('efiRemovable'):
            print('note: efiInstallAsRemovable is true, no need to add EFI NVRAM entry.')
        else:
            efibootmgr = os.path.join(str(config('efiBootMgrPath')), 'bin', 'efibootmgr')
            efi_partition = find_mounted_device(str(config('efiMountPoint')))
            efi_disk = find_disk_device(efi_partition)
            partition_num = efi_partition.removeprefix(efi_disk).removeprefix('p')

            try:
                efibootmgr_output = subprocess.check_output(
                    [efibootmgr], stderr=subprocess.STDOUT,
                    universal_newlines=True, timeout=SUBPROCESS_TIMEOUT,
                )
            except subprocess.CalledProcessError as e:
                print(
                    f'error: efibootmgr failed: {e.output}\n'
                    '  Consider setting efiInstallAsRemovable = true',
                    file=sys.stderr,
                )
                raise

            refind_boot_entry = None
            if matches := re.findall(r'Boot([0-9a-fA-F]{4})\*? rEFInd', efibootmgr_output):
                refind_boot_entry = matches[0]

            if refind_boot_entry:
                boot_order_matches = re.findall(
                    r'BootOrder: ((?:[0-9a-fA-F]{4},?)*)', efibootmgr_output
                )
                boot_order = boot_order_matches[0] if boot_order_matches else None

                # Create new entry first — old entry remains as fallback if this fails
                create_output = subprocess.check_output([
                    efibootmgr, '-c',
                    '-d', efi_disk,
                    '-p', partition_num,
                    '-l', f'\\efi\\refind\\{efi_file}',
                    '-L', 'rEFInd',
                ], stderr=subprocess.STDOUT, universal_newlines=True, timeout=SUBPROCESS_TIMEOUT)

                new_matches = re.findall(r'Boot([0-9a-fA-F]{4})\*? rEFInd', create_output)
                new_boot_num = new_matches[-1] if new_matches else None

                # Delete old entry (non-fatal — two entries is ugly but bootable)
                try:
                    subprocess.check_output([
                        efibootmgr, '-b', refind_boot_entry, '-B',
                    ], stderr=subprocess.STDOUT, universal_newlines=True, timeout=SUBPROCESS_TIMEOUT)
                except subprocess.CalledProcessError as e:
                    print(f'warning: failed to remove old boot entry {refind_boot_entry}: {e.output}', file=sys.stderr)

                # Restore boot order with new entry replacing old position
                if boot_order and new_boot_num:
                    new_boot_order = boot_order.replace(refind_boot_entry, new_boot_num)
                    try:
                        subprocess.check_output([
                            efibootmgr, '-o', new_boot_order,
                        ], stderr=subprocess.STDOUT, universal_newlines=True, timeout=SUBPROCESS_TIMEOUT)
                    except subprocess.CalledProcessError as e:
                        print(f'warning: failed to restore boot order: {e.output}', file=sys.stderr)
            else:
                subprocess.check_output([
                    efibootmgr, '-c',
                    '-d', efi_disk,
                    '-p', partition_num,
                    '-l', f'\\efi\\refind\\{efi_file}',
                    '-L', 'rEFInd',
                ], stderr=subprocess.STDOUT, universal_newlines=True, timeout=SUBPROCESS_TIMEOUT)

    print("removing unused boot files...")
    for path in list(paths.keys()):
        if not paths[path]:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    # Orphan scan restricted to managed subdirectories only
    for subdir in ['kernels', 'themes']:
        scan_dir = os.path.join(refind_dir, subdir)
        if not os.path.exists(scan_dir):
            continue
        for dirpath, _, filenames in os.walk(scan_dir):
            for f in filenames:
                full = os.path.join(dirpath, f)
                if full not in paths and not f.startswith('.'):
                    print(f"removing orphaned file: {full}")
                    os.remove(full)


def main() -> None:
    global install_config
    install_config = load_config()

    try:
        install_bootloader()
    finally:
        try:
            fd = os.open(f"{config('efiMountPoint')}", os.O_RDONLY)
            try:
                rc = libc.syncfs(fd)
                if rc != 0:
                    errno = ctypes.get_errno()
                    print(f"could not sync {config('efiMountPoint')}: {os.strerror(errno)}", file=sys.stderr)
            finally:
                os.close(fd)
        except OSError as e:
            print(f"warning: syncfs failed: {e}", file=sys.stderr)


if __name__ == '__main__':
    main()
