# fedora-bootc-bspwm

A **bootable container** image that replicates this PC: Fedora 44 (x86_64),
**bspwm** desktop (sxhkd + polybar + rofi + dunst), **lightdm** greeter, full
package set, custom repos, printers, and `/opt` apps — built **ext4** and
bootable on **legacy BIOS** (no UEFI).

The running system is image-based: OS updates are atomic via `bootc upgrade`
(with automatic rollback), not `dnf upgrade`.

## How it works

```
Containerfile  ──podman build──▶  OCI image (ghcr.io/vinod2807/fedora-bootc-bspwm)
                                          │  push (CI, weekly + on push)
                                          ▼
   bootc-image-builder --type raw --type iso --rootfs ext4   ──▶  disk image
                                          │
                                          ▼
                    install on legacy-BIOS PC  ──▶  bootc upgrade (weekly timer)
```

- **GitHub Actions** builds & pushes the container image to
  `ghcr.io/vinod2807/fedora-bootc-bspwm` on every push and **every Monday**.
- You build the **disk image** locally (or on any podman host with KVM) with
  `build.sh`, then install.
- After install, the built-in **weekly timer** runs `bootc upgrade` and reboots
  when a new image is available — so the Monday rebuilds land automatically.

## Prerequisites (build host)

- `podman` (rootful) with KVM (`/dev/kvm`) — needed by `bootc-image-builder`
  to run Anaconda inside a VM.
- `quay.io/centos-bootc/bootc-image-builder:latest` (pulled automatically).

Fedora/CentOS/RHEL hosts work; the running PC does **not** need podman.

## Build the disk image

```bash
git clone https://github.com/vinod2807/fedora-bootc-bspwm
cd fedora-bootc-bspwm
# optional: drop /opt tarballs (Epson utility, zapret2) into src/machine/opt/
chmod +x build.sh
sudo ./build.sh
```

Outputs in `./output`:

- `raw/disk.raw` — raw disk image. `dd`/Write to a disk, or boot in a VM.
  Boots on **legacy BIOS** (GPT + BIOS boot partition + grub2-pc).
- `iso/...iso` — installable USB image. Boots on legacy BIOS; installs to the
  first disk, then it's a bootc system.

> The `iso`/`raw` build needs KVM. On a headless server without KVM, build the
> container image only (`sudo podman build -t localhost/... .`) and run
> `bootc-image-builder` on a KVM-capable host.

## Install

- **Raw:** write `disk.raw` to the target disk (`dd if=disk.raw of=/dev/sdX bs=4M
  status=progress`), then boot.
- **ISO:** write to USB (`dd`/Fedora Media Writer), boot, install to first disk.

First boot runs `bootc-firstboot.service` (printers, dotfiles, user services).

## Configure the user (config.toml)

Edit `config.toml` before building: set the user `password` (hashed) **or** an
SSH `key`. The same username must match `USERNAME` in the `Containerfile` /
`FIRSTBOOT_USER` in `src/firstboot/bootc-firstboot.service`.

## Updating the running system

```bash
sudo bootc upgrade      # stages new image; reboot to apply
sudo bootc status       # see current vs staged
```
The `bootc-upgrade.timer` does this every week automatically.

To ship a new image: push to `main` (or wait for Monday). CI rebuilds and
pushes; your PC picks it up on the next weekly run.

## What is replicated (full fidelity)

| Source (fedora-bootstrap) | Handled by |
|---|---|
| `packages-full.txt` (1900+ rpms) | Containerfile `dnf install --skip-unavailable` |
| custom repos (Copr/Brave/ONLYOFFICE) + GPG | `src/machine/repos/` → `/etc/yum.repos.d` |
| bspwm/lightdm/X11/keyboard configs | `src/machine/etc/` |
| `/usr/local/bin` scripts | `src/machine/usr-local-bin/` |
| `/opt` apps (Epson, zapret2) | `src/machine/opt/*.tar.gz` (gitignored — add locally) |
| printer PPDs + queues | `src/machine/printers*` + firstboot |
| enabled services | `src/machine/services-enabled.txt` |
| user services | firstboot symlinks |

## Not included (by design, like the original bootstrap)

SSH keys, Syncthing device identity, browser profiles, `~/.local/share` state,
and `~/.EpsonPrinterUtility`. The dotfiles clone in firstboot is best-effort
(private repo) — apply manually if it fails.
