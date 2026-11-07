#!/usr/bin/env bash
set -euo pipefail

ROOT="${BUILDROOT:-${1:-}}"
FSTAB="${ROOT}/etc/fstab"

mkdir -p "${ROOT}/etc"

# Discoverable Partitions Specification (DPS) mounts root automatically.
# Add fstab entries for the subvolume mounts using LABEL=rootfs with space_cache=v2 and zstd compression.
cat >> "$FSTAB" << 'EOF'
# /etc/fstab: static file system information.
# <file system>  <mount point>  <type>  <options>  <dump>  <pass>
LABEL=rootfs     /              btrfs   subvol=@,compress=zstd:1,noatime,space_cache=v2,x-systemd.growfs 0 0
LABEL=rootfs     /home          btrfs   subvol=@home,compress=zstd:1,noatime,space_cache=v2 0 0
LABEL=rootfs     /var/log       btrfs   subvol=@var_log,compress=zstd:1,noatime,space_cache=v2 0 0
LABEL=rootfs     /opt           btrfs   subvol=@opt,compress=zstd:1,noatime,space_cache=v2 0 0
LABEL=rootfs     /.snapshots    btrfs   subvol=@snapshots,compress=zstd:1,noatime,space_cache=v2 0 0
EOF
