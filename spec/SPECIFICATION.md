# Specification: Converting Debian Cloud Images to `mkosi`, `systemd-repart`, `Btrfs`, and `systemd-boot`

## 1. Executive Summary

This document specifies the migration plan and architectural design for converting the legacy **Debian Cloud Image** build system—currently based on FAI (Fully Automatic Installation), GRUB2, and ext4 (`config_space`)—into a modern, declarative, reproducible system based on **`mkosi` (v26+)**, **`systemd-repart`**, **Btrfs root filesystem with subvolumes**, and **`systemd-boot` / Unified Kernel Images (UKI)**.

The target repository is located at `debian-cloud-mkosi/`. This specification serves as the primary implementation blueprint.

---

## 2. Current State (`config_space`) vs. Target State (`debian-cloud-mkosi`)

| Architecture Aspect | Legacy System (`config_space`) | Target System (`debian-cloud-mkosi`) |
| :--- | :--- | :--- |
| **Build Engine** | FAI (Fully Automatic Installation) bash-based hooks & `fcopy` | **`mkosi` v26+** (Declarative `INI` configuration + unprivileged `systemd-nspawn`) |
| **Partitioning** | Imperative FAI disk scripts / `sfdisk` / `parted` | **`systemd-repart`** declarative `.conf` files in `mkosi.repart/` |
| **Root Filesystem** | `ext4` (flat filesystem) | **`btrfs`** (with `zstd:1` compression, subvolume layout `@`, `@home`, `@var_log`, `@opt`, `@snapshots`) |
| **Bootloader** | GRUB2 (`grub-cloud-amd64`, `grub-efi-arm64`, `grub-mkconfig` hooks) | **`systemd-boot`** with Unified Kernel Images (UKI via `systemd-stub`) |
| **Provider Profiles** | FAI classes (`EC2.var`, `AZURE.var`, `GCE.var`, `NOCLOUD.var`) | **`mkosi.profiles/`** directories (`aws`, `azure`, `gcp`, `nocloud`, `qemu`) |
| **Release Profiles** | Directory branches (`11`, `12`, `13`, `14`, `sid`) | **`mkosi.profiles/`** release drop-ins (`bookworm`, `trixie`, `forky`, `sid`) |
| **Package Definition** | `package_config/<CLASS>` line lists | Declarative `Packages=` directives in `mkosi.conf` & profile drop-ins |
| **Post-processing** | `scripts/DEBIAN/`, `scripts/LAST/` | `mkosi.postinst` / `mkosi.postinst.d/` modular execution scripts |

---

## 3. Directory Layout Specification

The `debian-cloud-mkosi` repository will be structured as follows:

```
debian-cloud-mkosi/
├── spec/
│   └── SPECIFICATION.md          # This design document
├── mkosi.conf                     # Global base configuration
├── mkosi.conf.d/                  # Base drop-in configuration snippets
│   ├── 10-debian-base.conf        # Suite defaults, mirror URLs, apt keyring
│   ├── 20-filesystem-btrfs.conf   # Btrfs filesystem defaults & mount options
│   ├── 30-boot-systemd-boot.conf  # Bootloader=systemd-boot & kernel command line
│   ├── 40-packages-core.conf      # System packages common across all cloud builds
│   └── 50-services.conf          # Systemd unit activations (networkd, resolved, etc.)
├── mkosi.repart/                  # Declarative systemd-repart partition definitions
│   ├── 00-esp.conf                # EFI System Partition (FAT32, 512M)
│   └── 10-root.conf               # Root Partition (Btrfs, zstd, subvolumes)
├── mkosi.profiles/                # Profile overlays (invoked via --profile)
│   ├── aws/                       # AWS EC2 Profile
│   │   ├── mkosi.conf
│   │   └── mkosi.extra/           # AWS drop-in files (timesyncd, cloud-init)
│   ├── azure/                     # Azure Profile
│   │   ├── mkosi.conf
│   │   └── mkosi.extra/           # Azure drop-in files (waagent, chrony PTP, dhclient)
│   ├── gcp/                       # GCP GCE Profile
│   │   ├── mkosi.conf
│   │   └── mkosi.extra/           # GCP drop-in files (google-guest-agent, netplan)
│   ├── generic/                   # Generic multi-cloud/metal Profile
│   │   ├── mkosi.conf
│   │   └── mkosi.extra/
│   ├── genericcloud/              # Generic virtualized-only Profile
│   │   ├── mkosi.conf
│   │   └── mkosi.extra/
│   ├── nocloud/                   # NoCloud / Local Virt Profile
│   │   ├── mkosi.conf
│   │   └── mkosi.extra/
│   ├── qemu/                      # QEMU Development & Testing Profile
│   │   ├── mkosi.conf
│   │   └── mkosi.extra/
│   ├── bookworm/                  # Debian 12 Release Profile
│   │   └── mkosi.conf
│   ├── trixie/                    # Debian 13 Release Profile
│   │   └── mkosi.conf
│   ├── forky/                     # Debian 14 Release Profile
│   │   └── mkosi.conf
│   └── sid/                       # Debian Sid Release Profile
│       └── mkosi.conf
├── mkosi.extra/                   # Global extra filesystem overlay (etc/, usr/)
│   └── etc/
│       ├── cloud/cloud.cfg.d/
│       │   └── 01_debian_cloud.cfg
│       └── systemd/
│           ├── resolved.conf.d/
│           └── network/
├── mkosi.postinst                 # Master post-installation execution script
└── mkosi.postinst.d/              # Modular post-installation steps
    ├── 10-btrfs-subvols.sh        # Subvolume fstab generation & mount options
    ├── 20-cloud-init-setup.sh     # Cloud-init defaults & networkd links
    └── 90-cleanup.sh              # Apt cache, machine-id, & host key sanitization
```

---

## 4. Partitioning & Btrfs Filesystem Specification

### 4.1 `systemd-repart` Integration
Partitioning is handled natively by `mkosi` using `systemd-repart`. Files in `mkosi.repart/` override mkosi's built-in partition defaults.

#### `mkosi.repart/00-esp.conf`
```ini
[Partition]
Type=esp
Format=vfat
CopyFiles=/boot:/
CopyFiles=/efi:/
SizeMinBytes=512M
SizeMaxBytes=512M
```

#### `mkosi.repart/10-root.conf`
```ini
[Partition]
Type=root
Format=btrfs
Compression=zstd
CompressionLevel=1
CopyFiles=/
Minimize=guess
Subvolumes=
    @:/
    @home:/home
    @var_log:/var/log
    @opt:/opt
    @snapshots:/.snapshots
```

> **[IMPORTANT] Requirement for Btrfs Subvolumes in `mkosi`:**
> As specified in the `mkosi` man page (`RepartOffline=`), when using `Subvolumes=` in `systemd-repart` partition definitions, `RepartOffline=no` must be configured in `mkosi.conf` or loopback permissions provided, as `btrfs` subvolume ioctls require a mounted filesystem during image assembly.

### 4.2 Architecture Choice: UEFI-Only & BIOS Boot Partition Omission
The legacy FAI partition script (`hooks/partition.AMD64`) created a 3 MiB MBR/BIOS boot partition (`p14`) for GRUB legacy fallback alongside the ESP (`p15`). In `debian-cloud-mkosi`, the BIOS boot partition is **deliberately dropped** in favor of a modern, pure UEFI GPT layout bootable via `systemd-boot` and UKI. Cloud platforms (AWS Nitro, Azure Gen2, GCP modern machine types) natively default to UEFI. Legacy BIOS-only hypervisors are out of scope for this architecture.

### 4.3 Btrfs Layout & Subvolume Strategy
To support rollbacks, state isolation, and fast cloud instance provisioning, the root filesystem is structured into dedicated subvolumes:

1. **`@` (Root Subvolume)**: Mounted on `/`. Contains the OS core.
2. **`@home`**: Mounted on `/home`. Isolates user data from root OS snapshots.
3. **`@var_log`**: Mounted on `/var/log`. Ensures log writes do not pollute root snapshots or consume space required for system rollbacks.
4. **`@opt`**: Mounted on `/opt`. Isolates 3rd-party software packages and application runtimes so that uncontrolled 3rd-party writes or future subvolume quota limits on `/opt` cannot exhaust root filesystem space or impact core system stability.
5. **`@snapshots`**: Mounted on `/.snapshots`. Reserved for `snapper` or `btrfs-progs` automated system state snapshots.

### 4.4 Btrfs Mount Options, Subvolume Mounting, & Auto-Growth
- **Default Mount Options**: `noatime,compress=zstd:1,space_cache=v2,subvol=@`
- **Subvolume Mount Strategy**: Rather than hardcoding partition UUIDs during postinst (which runs before `systemd-repart` finalizes image partitions), subvolume mounts in `/etc/fstab` leverage filesystem labels (`LABEL=rootfs`) or Discoverable Partitions Specification (DPS) with `x-systemd.growfs`, ensuring resilient, portable mounting.
- **First-Boot Resizing**: `systemd-repart.service` and `btrfs filesystem resize max /` automatically expand the root partition and filesystem on cloud instance launch to consume the total provisioned disk size.

---

## 5. Bootloader & Kernel Specification (`systemd-boot` + UKI)

### 5.1 Transitioning from GRUB2 to `systemd-boot`
The legacy `config_space` used `grub-cloud-amd64` / `grub-efi-arm64` with complex `grub-mkconfig` and device map hacks. `debian-cloud-mkosi` completely removes GRUB in favor of `systemd-boot` and Unified Kernel Images (UKI).

### 5.2 `mkosi.conf.d/30-boot-systemd-boot.conf` Configuration
```ini
[Content]
Bootable=yes
Bootloader=systemd-boot

Packages=
    linux-image-cloud-amd64
    systemd-boot-efi
    btrfs-progs
    zstd

KernelCommandLine=
    console=tty1
    rootflags=subvol=@,compress=zstd:1,noatime
    rw
    quiet
```

> **Note on Initrd Generator**:
> - **Debian 12 (Bookworm) & 13 (Trixie)**: Default to `initramfs-tools` (or mkosi built-in).
> - **Debian 14 (Forky) & Sid**: Upstream has transitioned to `dracut` (dropping `cloud-initramfs-growroot` and `initramfs-tools`). The `forky` profile explicitly sets `InitrdGenerator=dracut` and installs `dracut`.

### 5.3 Debian Architecture & EFI Requirements
- **Package Dependency**: Debian separates `systemd-boot` EFI binaries into `systemd-boot-efi`. This package MUST be included in `Packages=` for `systemd-boot` to install `/usr/lib/systemd/boot/efi/systemd-bootx64.efi` (or `systemd-bootaa64.efi`).
- **Unified Kernel Images (UKI)**: `mkosi` automatically combines the kernel (`vmlinuz`), initrd, and kernel command line into a UKI binary placed in `EFI/Linux/` inside the ESP partition.
- **Supported Architectures**:
  - `x86_64` (AMD64): `systemd-boot` EFI bootloader.
  - `arm64` (ARM64): `systemd-boot` EFI bootloader.
  - `riscv64`: `systemd-boot` EFI bootloader.
- **Architectures Scoped Out**:
  - `ppc64el` (IBM POWER) & `s390x` (IBM Z): Require non-UEFI firmware/bootloaders (Petitboot/kexec / zipl / s390-tools) which are incompatible with `systemd-boot` and UKI architecture.
  - Raspberry Pi: Requires hybrid MBR, proprietary firmware partitions, and U-Boot/non-free-firmware, scoped out of cloud images.

---

## 6. Cloud Provider Profiles (`mkosi.profiles/`)

The legacy FAI classes (`EC2`, `AZURE`, `GCE`, `NOCLOUD`) are converted into modular `mkosi` profiles under `mkosi.profiles/`.

### 6.1 AWS EC2 (`mkosi.profiles/aws/`)
* **`mkosi.conf`**:
  ```ini
  [Content]
  Packages=
      awscli
      cloud-init
      cloud-guest-utils
      amazon-ec2-utils

  KernelCommandLine=
      console=ttyS0,115200n8
      console=tty0
      nvme_core.io_timeout=4294967295
  ```
* **Configuration Drop-ins (`mkosi.extra/`)**:
  * `/etc/systemd/timesyncd.conf.d/01_aws_ntp.conf`: `FallbackNTP=169.254.169.123 fd00:ec2::123`
  * `/etc/cloud/cloud.cfg.d/01_debian_cloud.cfg`: Default user `admin`, APT mirror `https://cdn-aws.deb.debian.org/debian`.

### 6.2 Azure (`mkosi.profiles/azure/`)
* **`mkosi.conf`**:
  ```ini
  [Content]
  Packages=
      cloud-init
      cloud-guest-utils
      hyperv-daemons
      waagent
      chrony

  KernelCommandLine=
      console=ttyS0,115200
      earlyprintk=ttyS0
  ```
* **Configuration Drop-ins (`mkosi.extra/`)**:
  * `/etc/cloud/cloud.cfg.d/01_debian_cloud.cfg`: Default user `debian`, APT mirror `http://azure.deb.debian.cloud/debian`.
  * `/etc/cloud/cloud.cfg.d/10_azure.cfg`: Hyper-V telemetry & serial log reporting.
  * `/etc/chrony/chrony.conf.d/01_azure_ptp.conf`: Hyper-V PTP clock source (`refclock PHC /dev/ptp_hyperv poll 3 dpoll -2 offset 0`) to prevent Hyper-V VM clock drift.
  * `/etc/dhcp/dhclient.conf`: Extended DHCP timeout (300s).

### 6.3 GCP GCE (`mkosi.profiles/gcp/`)
* **`mkosi.conf`**:
  ```ini
  [Content]
  Packages=
      google-guest-agent
      google-compute-engine-oslogin
      cloud-init

  KernelCommandLine=
      console=ttyS0,115200
  ```
* **Configuration Drop-ins (`mkosi.extra/`)**:
  * `/etc/cloud/cloud.cfg.d/01_debian_cloud.cfg`: Default user `debian`, metadata-driven SSH key provisioning.
  * `/etc/systemd/timesyncd.conf.d/01_gcp_ntp.conf`: Google metadata NTP server setup (`metadata.google.internal`).
  * `/etc/netplan/90-default.yaml`: Netplan networkd backend binding.

### 6.4 NoCloud / Local VM (`mkosi.profiles/nocloud/`)
* **`mkosi.conf`**:
  ```ini
  [Content]
  Packages=
      cloud-init
      cloud-guest-utils

  KernelCommandLine=
      console=ttyS0,115200
      console=tty1
  ```
> **Firstboot behavior**: On Trixie and later, `/etc/machine-id` is populated with `"uninitialized"` to invoke `systemd-firstboot` for interactive console provisioning instead of automated cloud-init provisioning. On Bookworm, `cloud-initramfs-growroot` is retained.

### 6.5 QEMU Development (`mkosi.profiles/qemu/`)
* **`mkosi.conf`**:
  ```ini
  [Content]
  Packages=
      qemu-guest-agent
      cloud-init
      less
      vim-tiny
      sudo

  KernelCommandLine=
      console=ttyS0,115200
      console=tty1
  ```

### 6.6 Generic & GenericCloud Profiles (`mkosi.profiles/generic/`, `genericcloud/`)
* **`mkosi.profiles/generic/mkosi.conf`**: Multi-environment image containing kernel hardware drivers suitable for bare metal and physical virtualization:
  ```ini
  [Content]
  Packages=
      cloud-init
      cloud-guest-utils
      linux-image-amd64
  ```
* **`mkosi.profiles/genericcloud/mkosi.conf`**: Minimal virtualized footprint utilizing cloud-optimized kernel:
  ```ini
  [Content]
  Packages=
      cloud-init
      cloud-guest-utils
      linux-image-cloud-amd64
  ```

---

## 7. Debian Release Profiles

Release profiles select the Debian suite dynamically via `Distribution=debian` and `Release=`:

* **`mkosi.profiles/bookworm/mkosi.conf`**:
  ```ini
  [Distribution]
  Distribution=debian
  Release=bookworm

  [Content]
  # Remove libnss-resolve per Debian cloud team advisory
  # https://lists.debian.org/debian-cloud/2024/03/msg00018.html
  RemovePackages=
      libnss-resolve
  Packages=
      cloud-initramfs-growroot
  ```
  *(Note: For `bookworm-backports`, explicit kernel packages `linux-image-6.12-cloud-amd64` / `linux-image-6.12-cloud-arm64` can be pinned.)*

* **`mkosi.profiles/trixie/mkosi.conf`**:
  ```ini
  [Distribution]
  Distribution=debian
  Release=trixie
  ```

* **`mkosi.profiles/forky/mkosi.conf`**:
  ```ini
  [Distribution]
  Distribution=debian
  Release=forky

  [Content]
  InitrdGenerator=dracut
  Packages=
      dracut
  RemovePackages=
      initramfs-tools
      cloud-initramfs-growroot
  ```

* **`mkosi.profiles/sid/mkosi.conf`**:
  ```ini
  [Distribution]
  Distribution=debian
  Release=sid

  [Content]
  InitrdGenerator=dracut
  Packages=
      dracut
  ```

---

## 8. Package & Script Migration Plan

### 8.1 Base Package Mapping (`mkosi.conf.d/40-packages-core.conf`)
All common cloud packages from `config_space/12/package_config/SYSTEM_BOOT` and `CLOUD` are consolidated into a declarative core manifest matching upstream Debian cloud images:

```ini
[Content]
Packages=
    base-files
    init
    systemd
    systemd-resolved
    systemd-timesyncd
    libpam-systemd
    libnss-resolve
    libnss-myhostname
    netplan.io
    polkitd
    sudo
    openssh-server
    ssh-import-id
    ca-certificates
    curl
    ethtool
    netbase
    iputils-ping
    iproute2
    iptables
    apt-utils
    linux-sysctl-defaults
    less
    nano
    vim-tiny
    whiptail
    unattended-upgrades
    apparmor
    zstd
    btrfs-progs
    e2fsprogs
```

### 8.2 Post-Install Hooks (`mkosi.postinst.d/`)
The legacy FAI shell scripts (`10-files`, `11-misc`, `10-cleanup`, `20-enable-systemd-networkd`) are converted into standard `mkosi` post-install scripts:

1. **`10-btrfs-subvols.sh`**: Generates `/etc/fstab` entries using filesystem labels (`LABEL=rootfs`) or partition identifiers with subvolume mount options (`@`, `@home`, `@var_log`, `@opt`, `@snapshots`) and `x-systemd.growfs`.
2. **`20-cloud-init-setup.sh`**: Enables `systemd-networkd.service` and `systemd-resolved.service`, configures `/etc/resolv.conf` symlink to `/run/systemd/resolve/resolv.conf`, and locks the root password.
3. **`90-cleanup.sh`**: Sanitizes `/etc/machine-id` (truncated empty for cloud-init images, or populated with `"uninitialized"` for NoCloud/firstboot), removes `/etc/ssh/ssh_host_*`, clears `/var/lib/dbus/machine-id`, and flushes `apt` caches.

---

## 9. Build Workflow & Usage Examples

Using `mkosi` v26+, building an image for a specific cloud provider and release requires specifying the corresponding profiles:

### 9.1 Build AWS Image on Debian Bookworm
```bash
mkosi --profile=bookworm,aws build
```

### 9.2 Build Azure Image on Debian Trixie
```bash
mkosi --profile=trixie,azure build
```

### 9.3 Build and Directly Test QEMU Image on Debian Sid
```bash
mkosi --profile=sid,qemu qemu
```

---

## 10. Future Feature Roadmap

This specification establishes the foundation for the following planned enhancements:

1. **Phase 2: Immutable Images with `dm-verity`**:
   * Configure `Verity=hash` in `systemd-repart` `10-root.conf`.
   * Enable `mkosi` auto-signing for verity roothash and pass roothash into UKI command lines automatically.
2. **Phase 3: Secure Boot & Signed UKIs**:
   * Integrate `SecureBoot=yes` with custom owner keys or `ShimBootloader=signed` using Microsoft Third-Party CA signed shim binaries.
3. **Phase 4: System Extensions (`systemd-sysext`)**:
   * Decouple cloud vendor agents (AWS CLI, Azure waagent, GCP guest agent) into separate `.raw` system extensions.
   * Maintain a single unified, signed base OS image across all cloud platforms.
4. **Phase 5: Btrfs Automated Rollbacks**:
   * Combine Btrfs `@snapshots` with `systemd-boot` snapshot boot entries for fail-safe OS upgrades.

---

## 11. Image Parity Verification & Audit Framework

To ensure that images built via `debian-cloud-mkosi` achieve functional and configuration parity with official Debian Cloud Releases (published at `https://cloud.debian.org/images/cloud/`), an automated verification framework is included in the project specification.

### 11.1 Verification Dimensions
When comparing a newly built `mkosi` image against an official Debian Cloud release image of the same profile (e.g., Debian 12 Bookworm AWS AMD64), the verification pipeline audits six key dimensions:

1. **Package Manifest & Version Parity**:
   * Extracts package lists via `dpkg-query -W -f='${Package} ${Version}\n'` from both root filesystems.
   * Uses `mkosi` built-in manifest generation (`ManifestFormat=json,changelog`) to produce automated package manifests during image builds.
   * Highlights missing, extra, or version-mismatched packages.

2. **Systemd Services & Unit Enablement Parity**:
   * Executes `systemctl list-unit-files` inside both image rootfs environments using `systemd-nspawn`.
   * Verifies that vendor-required cloud services (`cloud-init.service`, `systemd-networkd.service`, `systemd-resolved.service`, `waagent.service`, `google-guest-agent.service`, `amazon-ec2-utils`) have identical activation statuses (`enabled`, `disabled`, `masked`).

3. **Configuration Files (`/etc`) Parity**:
   * Performs recursive tree comparison of `/etc` between mounted images (`diff -urN --exclude=machine-id --exclude=fstab ...`).
   * Audits cloud drop-ins (`/etc/cloud/cloud.cfg.d/`), networking (`/etc/systemd/network/`, `/etc/netplan/`), DNS resolver (`/etc/resolv.conf`), APT mirrors/sources (`/etc/apt/sources.list.d/`), sysctl overrides (`/etc/sysctl.d/`), and NTP defaults (`/etc/systemd/timesyncd.conf.d/`).

4. **User Account & Privilege Parity**:
   * Compares `/etc/passwd`, `/etc/group`, and `/etc/shadow` entries.
   * Validates default non-root user creation (`admin` for AWS, `debian` for Azure/GCP/NoCloud) with correct UID (1000), shell (`/bin/bash`), group memberships (`adm`, `sudo`, `dialout`, `plugdev`, etc.), and passwordless sudoers rules in `/etc/sudoers.d/`.
   * Accounts for newer system groups and users present in trixie/forky (`clock`, `lpadmin`, `dhcpcd`).

5. **File Ownership, Permissions, & Modes**:
   * Audits file ownership (UID/GID) and permission bits (`stat -c "%a %U %G %n"`) for critical paths including `/etc/sudoers.d/`, `/etc/ssh/sshd_config`, and `/etc/shadow`.

6. **Deep Image Structural Diffing (`diffoscope`)**:
   * Uses `diffoscope` (Debian's canonical tool for reproducible build analysis) to perform deep binary and file-level comparison between the freshly generated disk image and the official release image.

### 11.2 Verification Pipeline Script (`scripts/verify-image-parity.sh`)

The automated verification tool `scripts/verify-image-parity.sh` uses systemd image inspection utilities (`systemd-dissect`, `systemd-nspawn`) to mount disk images without root loop device pollution:

```bash
#!/bin/bash
# scripts/verify-image-parity.sh
# Usage: ./verify-image-parity.sh <mkosi-image.raw> <official-debian-image.qcow2|raw>

set -euo pipefail

MKOSI_IMG="${1:?Error: Path to mkosi raw image required}"
OFFICIAL_IMG="${2:?Error: Path to official Debian release image required}"

MNT_MKOSI=$(mktemp -d /tmp/mnt-mkosi.XXXXXX)
MNT_OFFICIAL=$(mktemp -d /tmp/mnt-official.XXXXXX)

cleanup() {
    echo "==> Cleaning up mount points..."
    systemd-dissect --detach "$MNT_MKOSI" 2>/dev/null || true
    systemd-dissect --detach "$MNT_OFFICIAL" 2>/dev/null || true
    rm -rf "$MNT_MKOSI" "$MNT_OFFICIAL"
}
trap cleanup EXIT

echo "==> Mounting raw disk images..."
systemd-dissect --mount "$MKOSI_IMG" "$MNT_MKOSI"
systemd-dissect --mount "$OFFICIAL_IMG" "$MNT_OFFICIAL"

echo "==> 1. Auditing Installed Packages..."
dpkg-query --admindir="$MNT_MKOSI/var/lib/dpkg" -W -f='${Package} ${Version}\n' | sort > /tmp/pkgs-mkosi.txt
dpkg-query --admindir="$MNT_OFFICIAL/var/lib/dpkg" -W -f='${Package} ${Version}\n' | sort > /tmp/pkgs-official.txt
diff -u /tmp/pkgs-official.txt /tmp/pkgs-mkosi.txt || echo "[WARNING] Package mismatch detected."

echo "==> 2. Auditing /etc Configuration Tree..."
diff -urN \
    --exclude="machine-id" \
    --exclude="fstab" \
    --exclude="cloud-release" \
    "$MNT_OFFICIAL/etc" "$MNT_MKOSI/etc" || echo "[INFO] Configuration differences noted above."

echo "==> 3. Auditing Enabled Systemd Services..."
systemd-nspawn -D "$MNT_MKOSI" systemctl list-unit-files --state=enabled > /tmp/units-mkosi.txt
systemd-nspawn -D "$MNT_OFFICIAL" systemctl list-unit-files --state=enabled > /tmp/units-official.txt
diff -u /tmp/units-official.txt /tmp/units-mkosi.txt || echo "[WARNING] Systemd service state mismatch detected."

echo "==> 4. Auditing User & Group Definitions..."
diff -u "$MNT_OFFICIAL/etc/passwd" "$MNT_MKOSI/etc/passwd" || true
diff -u "$MNT_OFFICIAL/etc/group" "$MNT_MKOSI/etc/group" || true

echo "==> 5. Running Diffoscope for Deep Image Inspection..."
if command -v diffoscope &>/dev/null; then
    diffoscope --html /tmp/image-parity-report.html "$MKOSI_IMG" "$OFFICIAL_IMG" || true
    echo "Parity report generated at /tmp/image-parity-report.html"
else
    echo "[INFO] Install 'diffoscope' for detailed HTML structural diff reports."
fi

echo "==> Image Parity Verification Completed."
```

### 11.3 Integration with Build Automation
Manifest generation is enabled in `mkosi.conf` via:
```ini
[Output]
ManifestFormat=json
```

Build and verification invocation:
```bash
# Build image with manifests
mkosi --profile=bookworm,aws build

# Download official release image and run verification check
curl -LO https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.raw
./scripts/verify-image-parity.sh build/image.raw debian-12-generic-amd64.raw
```

