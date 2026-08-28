# Installing to an existing partition (`/dev/sda3`) alongside another OS

This machine uses **MBR / legacy BIOS**, with Ubuntu's GRUB already in the
`/dev/sda` MBR and the current root on `sda6`. We install the bootc image onto
`sda3` **without** touching the MBR, then let Ubuntu's `update-grub` (or a manual
entry) chain to it.

> Do **not** use the `raw`/`iso` auto-installer for this — those write to the
> whole first disk and would wipe it. Use `bootc install to-filesystem`.

## What `--bootloader=none` does

`bootc install to-filesystem ... --bootloader=none` writes the root filesystem,
kernel, initramfs and `/boot` contents onto the target partition but skips
installing any bootloader to the disk MBR/ESP. Ubuntu's GRUB stays the primary
bootloader. (See `bootc install to-filesystem --help`; equivalent to
`bootloader = "none"` in the install config.)

Caveat: with no bootloader installed, bootc does **not** write a `grub.cfg`
into `sda3`, so Ubuntu's os-prober may not auto-detect it. Use the manual GRUB
entry below (reliable) — `update-grub` alone is best-effort.

## Procedure

### 1. Boot a live environment with `podman`

Any Fedora live USB works; install podman there if needed:
```bash
sudo dnf install -y podman
```

### 2. Format and mount the target
```bash
mkfs.ext4 /dev/sda3
mkdir -p /mnt && mount /dev/sda3 /mnt
```

### 3. Install bootc onto the filesystem (no bootloader)
```bash
podman run --rm --privileged --pid=host \
  -v /dev:/dev \
  -v /var/lib/containers:/var/lib/containers \
  --security-opt label=type:unconfined_t \
  ghcr.io/vinod2807/fedora-bootc-bspwm:latest \
  bootc install to-filesystem /mnt \
    --bootloader=none \
    --target-imgref ghcr.io/vinod2807/fedora-bootc-bspwm:latest

# Note the installed kernel version for the GRUB entry:
ls /mnt/boot
```

`--target-imgref` wires future `bootc upgrade` to pull from ghcr.

### 4. Reboot into Ubuntu and register the entry

Get the partition UUID:
```bash
blkid /dev/sda3
```

Option A — try auto-detection first:
```bash
sudo update-grub
```
If a "Fedora" entry appears, you're done.

Option B — manual entry (reliable). Add to `/etc/grub.d/40_custom` on Ubuntu:
```bash
#!/bin/sh
exec tail -n +3 "$0"
menuentry "Fedora bootc (sda3)" {
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root <UUID-of-sda3>   # from blkid above
    linux  /boot/vmlinuz-<kver> root=UUID=<UUID-of-sda3> ro
    initrd /boot/initramfs-<kver>.img
}
```
Replace `<UUID-of-sda3>` with the `blkid` output and `<kver>` with the version
from `ls /mnt/boot` (e.g. `6.1.8-200.fc44.x86_64`). Then:
```bash
sudo update-grub
```

### 5. First boot

Select **Fedora bootc (sda3)** from Ubuntu's GRUB menu. On first boot:
- `bootc-firstboot.service` sets up printers, dotfiles, and user services.
- The weekly `bootc-upgrade.timer` is active; `bootc upgrade` later pulls new
  Monday-built images from ghcr.

## Notes

- `/boot` lives **inside** `sda3` (no separate partition needed on legacy BIOS),
  so GRUB loads the kernel/initramfs directly from `sda3`.
- The physical root is discovered via `root=UUID=...`, injected by
  `to-filesystem` from the target filesystem UUID.
- To later remove the bootc system, just delete `sda3` and drop the GRUB entry;
  Ubuntu's MBR is untouched throughout.
