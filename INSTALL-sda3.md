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
bootloader.

Caveat: with no bootloader installed, bootc does **not** write a `grub.cfg`
into `sda3`, so Ubuntu's os-prober may not auto-detect it. Use the manual GRUB
entry below (reliable) — `update-grub` alone is best-effort.

## Procedure

### 1. Boot a live environment with `podman` + `bootc`

A Fedora 44 live USB works. Install the tools:
```bash
sudo dnf install -y podman bootc
```

### 2. Format and mount the target

> **Do not mount at `/mnt`** — on this box `/mnt` is an ordinary directory on the
> root filesystem holding user backups. Use `/target` instead.

```bash
sudo mkfs.ext4 -F /dev/sda3
sudo mkdir -p /target && sudo mount /dev/sda3 /target
```

### 3. Prepare the host `ostree/prepare-root.conf`

`bootc install` checks the **host** filesystem (not the image) for
`prepare-root.conf`. Create it on the live host before installing:
```bash
sudo mkdir -p /etc/ostree /usr/lib/ostree
printf '[[composefs]]\nenabled = yes\n[sysroot]\nreadonly = true\n' | sudo tee /etc/ostree/prepare-root.conf /usr/lib/ostree/prepare-root.conf
```

### 4. Make room for the image (optional but usually needed)

The image is ~12 GB. If the live env's root is small, point podman at a bigger
disk (here `sdb5` was used as a scratch store); otherwise skip this and use the
default store:
```bash
sudo mkdir -p /root/scratch/containers /root/scratch/runroot
cat > /root/scratch/host-storage.conf <<'EOF'
[storage]
driver = "overlay"
graphroot = "/root/scratch/containers"
runroot = "/root/scratch/runroot"
EOF
```

### 5. Install bootc onto the filesystem (no bootloader)

Run `bootc` on the **host** (not inside a container). The `podman run ... bootc
install` form fails with `no such object` / `does not resolve to an image ID`,
and `oci-archive`/`docker-archive` sources fail with `invalid gzip header`
(bootc/ostree needs gzip but the layers are zstd). The `containers-storage`
source decompresses zstd correctly — so pull the image into podman first, then
install from the local store:

```bash
# pull into the (optionally custom) store
sudo CONTAINERS_STORAGE_CONF=/root/scratch/host-storage.conf \
  podman pull ghcr.io/vinod2807/fedora-bootc-bspwm:latest

# install from the local store — this imports ~12 GB and takes >15 min
sudo CONTAINERS_STORAGE_CONF=/root/scratch/host-storage.conf \
  bootc install to-filesystem /target \
    --bootloader=none \
    --source-imgref containers-storage:ghcr.io/vinod2807/fedora-bootc-bspwm:latest \
    --target-imgref ghcr.io/vinod2807/fedora-bootc-bspwm:latest
```

> Run it detached if your shell times out (`setsid ... >/tmp/bootc-install.log 2>&1 &`)
> and poll `/tmp/bootc-install.log` + `/target/boot` until it prints
> `Installation complete!`.

`--target-imgref` wires future `bootc upgrade` to pull from ghcr.

### 6. Capture the kernel + partition UUID for GRUB

```bash
# the deployment dir hash and kernel version:
sudo ls /target/boot/ostree/
# -> e.g. default-b0a7d3f98e83e8872911df9710f51ac3ca438384395150c2b43391bfb69a390a/
#    vmlinuz-7.1.10-200.fc44.x86_64
#    initramfs-7.1.10-200.fc44.x86_64.img
sudo blkid /dev/sda3   # fresh UUID (changes after mkfs!)
```

The kernel lives at `/boot/ostree/default-<hash>/vmlinuz-<kver>` **inside**
`sda3` — GRUB must reference that full path, not `/boot/vmlinuz-<kver>`.
(Current known version: `7.1.10-200.fc44.x86_64`.)

### 7. Make bootc the primary bootloader (GRUB in the MBR)

The bootc image already ships `grub2-pc`, so bootc can own the MBR directly.
This is the most robust layout: bootc's GRUB loads first and its menu lists
bootc (default) + Ubuntu + Arch + Windows; a `bootc upgrade` just regenerates
`sda3:/boot/grub2/grub.cfg` (via `/root/mk-bootc-grub.sh`).

On sda3, write `/boot/grub2/grub.cfg` — copy the exact `linux`/`initrd`/`options`
from `sda3:/boot/loader/entries/ostree-1.conf`, plus chainload entries for the
other OSes:
```
set timeout=10
set default=0
menuentry 'Fedora bootc (sda3)' {
    insmod part_msdos; insmod ext2
    search --no-floppy --fs-uuid --set=root <UUID-of-sda3>
    linux  /boot/ostree/default-<hash>/vmlinuz-<kver> <options-from-ostree-1.conf>
    initrd /boot/ostree/default-<hash>/initramfs-<kver>.img
}
menuentry 'Ubuntu 26.04'      { insmod part_msdos; insmod ext2; set root=(hd0,msdos2); configfile /boot/grub/grub.cfg }
menuentry 'Arch Linux'        { insmod part_msdos; insmod ext2; set root=(hd1,msdos5); configfile /boot/grub/grub.cfg }
menuentry 'Windows 11 (sdb1)' { insmod part_msdos; insmod ntfs; insmod chain; search --no-floppy --fs-uuid --set=root 3C5847D558478D18; chainloader +1 }
menuentry 'Windows 11 (sdb2)' { insmod part_msdos; insmod ntfs; insmod chain; search --no-floppy --fs-uuid --set=root 92CA4904CA48E5D7; chainloader +1 }
```
Install bootc's GRUB to the MBR (from a Fedora host that has `grub2-install`):
```bash
sudo grub2-install --boot-directory=/target/boot /dev/sda
```
> The `ostree=/ostree/boot.1/default/<hash>/0` argument is **required** — copy the
> exact `options` line from `ostree-1.conf`. Without `ostree=`, the initramfs won't
> pivot to the deployment.

### 8. Stop Ubuntu from overwriting the MBR on updates

Ubuntu's `grub-pc` postinst runs `grub-install` to `/dev/sda` on package updates,
which would clobber bootc's GRUB. Disable that (leave `update-grub` alone — it only
rewrites Ubuntu's own `grub.cfg`, which is never loaded):
```bash
# as root inside the Ubuntu system (or via chroot):
echo "grub-pc grub-pc/install_devices multiselect "       | debconf-set-selections
echo "grub-pc grub-pc/install_devices_empty boolean true" | debconf-set-selections
```

### 9. First boot

Select **Fedora bootc (sda3)** from bootc's own GRUB menu. On first boot:
- `bootc-firstboot.service` sets up printers, dotfiles, and user services.
- The weekly `bootc-upgrade.timer` is active; `bootc upgrade` later pulls new
  Monday-built images from ghcr.

> **After a `bootc upgrade`**, regenerate `sda3:/boot/grub2/grub.cfg` from the new
> loader entry: `sudo mount /dev/sda3 /target -o rw && sudo /root/mk-bootc-grub.sh && sudo umount /target`.
> (For fully automatic tracking on `bootc upgrade`, the image needs `ostree-grub2`
> — it provides `/etc/grub.d/15_ostree`, which `grub2-mkconfig` (run by bootc on
> upgrade) uses to regenerate the menu with the new default/rollback. Add
> `ostree-grub2 os-prober` to the Containerfile and rebuild. Our `mk-bootc-grub.sh`
> helper keeps the menu current in the meantime.)

## Notes

- `/boot` lives **inside** `sda3` (no separate partition needed on legacy BIOS),
  so GRUB loads the kernel/initramfs directly from `sda3` at
  `/boot/ostree/default-<hash>/`.
- The physical root is discovered via `root=UUID=...`, injected by
  `to-filesystem` from the target filesystem UUID.
- To later remove the bootc system, just delete `sda3` and drop the GRUB entry;
  bootc owns the MBR and Ubuntu's `grub-install` is disabled (step 8) so `apt`
  updates never overwrite it.
