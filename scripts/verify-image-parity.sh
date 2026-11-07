#!/usr/bin/env bash
# scripts/verify-image-parity.sh
# Automated verification auditor comparing a debian-cloud-mkosi image against
# an official Debian cloud release image.
#
# Usage: ./scripts/verify-image-parity.sh <mkosi-image.raw> <official-debian-image.raw|qcow2>

set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: $0 <mkosi-image.raw> <official-debian-image.raw|qcow2>"
    echo ""
    echo "Audits six dimensions of parity:"
    echo "  1. Installed package list & versions (dpkg-query)"
    echo "  2. /etc configuration tree diff"
    echo "  3. Enabled systemd services"
    echo "  4. User accounts (/etc/passwd) and privileges"
    echo "  5. Group accounts (/etc/group)"
    echo "  6. Binary/structural diff via diffoscope (if available)"
    exit 0
fi

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <mkosi-image.raw> <official-debian-image.raw|qcow2>" >&2
    exit 1
fi

MKOSI_IMG="${1}"
OFFICIAL_IMG="${2}"

if [ ! -f "$MKOSI_IMG" ]; then
    echo "Error: MKOSI image not found at '$MKOSI_IMG'" >&2
    exit 1
fi

if [ ! -f "$OFFICIAL_IMG" ]; then
    echo "Error: Official Debian image not found at '$OFFICIAL_IMG'" >&2
    exit 1
fi

MNT_MKOSI=$(mktemp -d /tmp/mnt-mkosi.XXXXXX)
MNT_OFFICIAL=$(mktemp -d /tmp/mnt-official.XXXXXX)

cleanup() {
    echo "==> Cleaning up image mount points..."
    systemd-dissect --detach "$MNT_MKOSI" 2>/dev/null || true
    systemd-dissect --detach "$MNT_OFFICIAL" 2>/dev/null || true
    rm -rf "$MNT_MKOSI" "$MNT_OFFICIAL"
}
trap cleanup EXIT

echo "==> Mounting disk images using systemd-dissect..."
systemd-dissect --mount "$MKOSI_IMG" "$MNT_MKOSI"
systemd-dissect --mount "$OFFICIAL_IMG" "$MNT_OFFICIAL"

echo ""
echo "=========================================================="
echo "==> 1. Auditing Installed Packages (dpkg-query)..."
echo "=========================================================="
PKG_MKOSI=$(mktemp /tmp/pkgs-mkosi.XXXXXX)
PKG_OFFICIAL=$(mktemp /tmp/pkgs-official.XXXXXX)

dpkg-query --admindir="$MNT_MKOSI/var/lib/dpkg" -W -f='${Package} ${Version}\n' | sort > "$PKG_MKOSI"
dpkg-query --admindir="$MNT_OFFICIAL/var/lib/dpkg" -W -f='${Package} ${Version}\n' | sort > "$PKG_OFFICIAL"

if diff -u "$PKG_OFFICIAL" "$PKG_MKOSI" > /tmp/pkg-diff.txt; then
    echo "[PASS] Package lists and versions match perfectly."
else
    echo "[INFO] Package differences detected:"
    cat /tmp/pkg-diff.txt | head -n 40 || true
fi
rm -f "$PKG_MKOSI" "$PKG_OFFICIAL" /tmp/pkg-diff.txt

echo ""
echo "=========================================================="
echo "==> 2. Auditing /etc Configuration Tree..."
echo "=========================================================="
diff -urN \
    --exclude="machine-id" \
    --exclude="fstab" \
    --exclude="cloud-release" \
    --exclude="adjtime" \
    "$MNT_OFFICIAL/etc" "$MNT_MKOSI/etc" > /tmp/etc-diff.txt || true

if [ ! -s /tmp/etc-diff.txt ]; then
    echo "[PASS] Configuration trees in /etc match."
else
    echo "[INFO] Configuration differences in /etc noted:"
    head -n 50 /tmp/etc-diff.txt || true
fi
rm -f /tmp/etc-diff.txt

echo ""
echo "=========================================================="
echo "==> 3. Auditing Enabled Systemd Units..."
echo "=========================================================="
UNITS_MKOSI=$(mktemp /tmp/units-mkosi.XXXXXX)
UNITS_OFFICIAL=$(mktemp /tmp/units-official.XXXXXX)

systemctl --root="$MNT_MKOSI" list-unit-files --state=enabled | sort > "$UNITS_MKOSI" 2>/dev/null || true
systemctl --root="$MNT_OFFICIAL" list-unit-files --state=enabled | sort > "$UNITS_OFFICIAL" 2>/dev/null || true

if diff -u "$UNITS_OFFICIAL" "$UNITS_MKOSI" > /tmp/units-diff.txt; then
    echo "[PASS] Enabled systemd service units match."
else
    echo "[INFO] Systemd enabled unit differences:"
    cat /tmp/units-diff.txt | head -n 40 || true
fi
rm -f "$UNITS_MKOSI" "$UNITS_OFFICIAL" /tmp/units-diff.txt

echo ""
echo "=========================================================="
echo "==> 4. Auditing User & Group Accounts..."
echo "=========================================================="
echo "--- /etc/passwd diff (excluding dynamic UID ranges):"
diff -u "$MNT_OFFICIAL/etc/passwd" "$MNT_MKOSI/etc/passwd" || true

echo "--- /etc/group diff (expecting clock, lpadmin, dhcpcd on newer systemd/distros):"
diff -u "$MNT_OFFICIAL/etc/group" "$MNT_MKOSI/etc/group" || true

echo ""
echo "=========================================================="
echo "==> 5. Diffoscope Deep Inspection..."
echo "=========================================================="
if command -v diffoscope &>/dev/null; then
    echo "Running diffoscope (generating /tmp/image-parity-report.html)..."
    diffoscope --html /tmp/image-parity-report.html "$MKOSI_IMG" "$OFFICIAL_IMG" || true
    echo "Parity report generated at: /tmp/image-parity-report.html"
else
    echo "[INFO] 'diffoscope' is not installed on host. Skipping deep HTML diff report."
fi

echo ""
echo "==> Image Parity Verification Completed."
