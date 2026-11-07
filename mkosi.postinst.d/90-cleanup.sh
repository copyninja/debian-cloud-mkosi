#!/usr/bin/env bash
set -euo pipefail

ROOT="${BUILDROOT:-${1:-}}"

# Clean up apt caches and package lists
if [ -d "${ROOT}/var/lib/apt/lists" ]; then
    find "${ROOT}/var/lib/apt/lists" -mindepth 1 -delete 2>/dev/null || true
fi
if [ -d "${ROOT}/var/cache/apt" ]; then
    find "${ROOT}/var/cache/apt" -type f -name '*.deb' -delete 2>/dev/null || true
fi

# Remove SSH host keys so each provisioned instance generates unique keys on first boot
rm -f "${ROOT}"/etc/ssh/ssh_host_*_key*

# Remove temporary files and machine-specific identifiers
rm -f "${ROOT}/var/lib/dbus/machine-id"

# Sanitize machine-id:
# If PROFILE contains nocloud, write "uninitialized" for systemd-firstboot, otherwise truncate to empty
if [[ "${PROFILE:-}" == *"nocloud"* ]]; then
    echo "uninitialized" > "${ROOT}/etc/machine-id"
else
    : > "${ROOT}/etc/machine-id"
fi
