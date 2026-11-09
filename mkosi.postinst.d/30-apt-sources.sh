#!/usr/bin/env bash
set -euo pipefail

ROOT="${BUILDROOT:-${1:-}}"

# Detect Debian release codename from os-release inside the image
SUITE="trixie"
if [ -f "${ROOT}/usr/lib/os-release" ]; then
    # shellcheck disable=SC1091
    SUITE=$(grep -E "^VERSION_CODENAME=" "${ROOT}/usr/lib/os-release" | cut -d= -f2 | tr -d '"')
elif [ -f "${ROOT}/etc/os-release" ]; then
    # shellcheck disable=SC1091
    SUITE=$(grep -E "^VERSION_CODENAME=" "${ROOT}/etc/os-release" | cut -d= -f2 | tr -d '"')
fi

SUITE="${SUITE:-${DISTRIBUTION_RELEASE:-trixie}}"

mkdir -p "${ROOT}/etc/apt/mirrors" "${ROOT}/etc/apt/sources.list.d"

# 1. /etc/apt/sources.list reference note
echo "# See /etc/apt/sources.list.d/debian.sources" > "${ROOT}/etc/apt/sources.list"

# 2. Mirror list files matching upstream debian-cloud-images
cat > "${ROOT}/etc/apt/mirrors/debian.list" <<'EOF'
https://deb.debian.org/debian
EOF

cat > "${ROOT}/etc/apt/mirrors/debian-security.list" <<'EOF'
https://deb.debian.org/debian-security
EOF

# 3. Modern deb822 source specification matching upstream debian-cloud-images
if [ "${SUITE}" = "sid" ]; then
    cat > "${ROOT}/etc/apt/sources.list.d/debian.sources" <<EOF
Types: deb deb-src
URIs: mirror+file:///etc/apt/mirrors/debian.list
Suites: sid
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
else
    cat > "${ROOT}/etc/apt/sources.list.d/debian.sources" <<EOF
Types: deb deb-src
URIs: mirror+file:///etc/apt/mirrors/debian.list
Suites: ${SUITE} ${SUITE}-updates ${SUITE}-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: mirror+file:///etc/apt/mirrors/debian-security.list
Suites: ${SUITE}-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
fi

chmod 0644 "${ROOT}/etc/apt/sources.list" \
           "${ROOT}/etc/apt/mirrors/debian.list" \
           "${ROOT}/etc/apt/mirrors/debian-security.list" \
           "${ROOT}/etc/apt/sources.list.d/debian.sources"
