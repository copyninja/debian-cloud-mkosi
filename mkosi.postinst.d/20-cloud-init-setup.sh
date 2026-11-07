#!/usr/bin/env bash
set -euo pipefail

ROOT="${BUILDROOT:-${1:-}}"

# Ensure /etc/resolv.conf points to systemd-resolved stub
mkdir -p "${ROOT}/run/systemd/resolve"
mkdir -p "${ROOT}/etc"
rm -f "${ROOT}/etc/resolv.conf"
ln -sf /run/systemd/resolve/stub-resolv.conf "${ROOT}/etc/resolv.conf"

# Lock the root account password by default (cloud-init or systemd-firstboot will manage credentials)
if [ -f "${ROOT}/etc/shadow" ]; then
    sed -i 's/^root:[^:]*:/root:*:/' "${ROOT}/etc/shadow"
fi
