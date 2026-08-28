#!/usr/bin/env bash
# Build the bootc image and produce a legacy-BIOS, ext4 raw disk + install ISO.
# Requires: podman (rootful) with KVM access (/dev/kvm) on this host.
set -euo pipefail

cd "$(dirname "$0")"

IMAGE="${IMAGE:-localhost/fedora-bootc-bspwm:latest}"
BUILDER="quay.io/centos-bootc/bootc-image-builder:latest"

echo "==> Building container image"
sudo podman build -t "$IMAGE" .

mkdir -p output

echo "==> Building raw + iso disk images (ext4, legacy BIOS)"
sudo podman run --rm -it --privileged --pull=newer \
  --security-opt label=type:unconfined_t \
  -v "$(pwd)/config.toml:/config.toml:ro" \
  -v "$(pwd)/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  "$BUILDER" \
  --type raw --type iso \
  --rootfs ext4 \
  --use-librepo=True \
  "$IMAGE"

echo "==> Done. Artifacts in ./output"
echo "    raw  -> dd or write to disk (boots on legacy BIOS)"
echo "    iso  -> write to USB, boot, installs to first disk"
