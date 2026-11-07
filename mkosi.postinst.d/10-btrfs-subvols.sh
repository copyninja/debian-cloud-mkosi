#!/usr/bin/env bash
set -euo pipefail

ROOT="${BUILDROOT:-${1:-}}"

# Ensure all subvolume and boot mount point directories exist before systemd-repart formats the filesystem
mkdir -p "${ROOT}/home"
mkdir -p "${ROOT}/var/log"
mkdir -p "${ROOT}/opt"
mkdir -p "${ROOT}/.snapshots"
mkdir -p "${ROOT}/efi"
mkdir -p "${ROOT}/boot"
