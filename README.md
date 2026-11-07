# debian-cloud-mkosi

Modern, declarative, reproducible Debian cloud image builder based on **`mkosi` (v26+)**, **`systemd-repart`**, **Btrfs root filesystem with subvolumes**, and **`systemd-boot` / Unified Kernel Images (UKI)**.

This repository modernizes the legacy FAI (Fully Automatic Installation) / GRUB2 / ext4 build system into a declarative system utilizing unprivileged user namespaces and systemd tooling.

---

## Architecture Overview

| Component | Target Implementation |
|---|---|
| **Build Engine** | `mkosi` v26+ (unprivileged `systemd-nspawn`) |
| **Partitioning** | Declarative `systemd-repart` (`mkosi.repart/`) |
| **Root Filesystem** | `btrfs` with `zstd:1` compression and subvolumes (`@`, `@home`, `@var_log`, `@opt`, `@snapshots`) |
| **Bootloader** | `systemd-boot` with Unified Kernel Images (UKI via `systemd-stub`) |
| **Cloud Profiles** | Modular profiles under `mkosi.profiles/` (`aws`, `azure`, `gcp`, `nocloud`, `qemu`, `generic`, `genericcloud`) |
| **Debian Suites** | Release profiles under `mkosi.profiles/` (`bookworm`, `trixie`, `forky`, `sid`) |

---

## Quick Start

### 1. Requirements

Ensure host packages are installed:
```bash
sudo apt install mkosi systemd-repart systemd-dissect btrfs-progs dosfstools
```

Check dependencies for your local setup:
```bash
mkosi dependencies
```

### 2. Viewing Configuration Summary

Verify configuration resolution for any release and cloud target:
```bash
# AWS EC2 on Debian 12 Bookworm
mkosi --profile=bookworm --profile=aws summary

# Azure on Debian 13 Trixie
mkosi --profile=trixie --profile=azure summary

# Local development on Debian Sid
mkosi --profile=sid --profile=qemu summary
```

### 3. Building an Image

Build a cloud image disk artifact:
```bash
# Build AWS image
mkosi --profile=bookworm --profile=aws build

# Build QEMU test image
mkosi --profile=sid --profile=qemu build
```

### 4. Running / Testing in QEMU

Test the built image locally:
```bash
mkosi --profile=sid --profile=qemu qemu
```

### 5. Parity Verification

Audit the built image against official Debian Cloud releases:
```bash
./scripts/verify-image-parity.sh image.raw /path/to/official-debian-12-generic-amd64.raw
```

---

## Directory Structure

```
debian-cloud-mkosi/
├── spec/
│   └── SPECIFICATION.md          # Architectural blueprint and design specification
├── mkosi.conf                     # Global base image configuration
├── mkosi.conf.d/                  # Modular drop-in snippets
│   ├── 10-debian-base.conf        # Debian repository and distribution defaults
│   ├── 20-filesystem-btrfs.conf   # Btrfs build-time subvolume optimization
│   ├── 30-boot-systemd-boot.conf  # systemd-boot & UKI kernel cmdline
│   ├── 40-packages-core.conf      # Core cloud packages
│   └── 50-services.conf          # Systemd socket & service activations
├── mkosi.repart/                  # Declarative partition definitions
│   ├── 00-esp.conf                # 512M FAT32 EFI System Partition
│   └── 10-root.conf               # Btrfs root filesystem with subvolume definitions
├── mkosi.profiles/                # Profiles selectable via --profile
│   ├── aws/                       # AWS EC2 profile & cloud drop-ins
│   ├── azure/                     # Azure profile & Hyper-V PTP clock sync
│   ├── gcp/                       # GCP GCE profile & metadata NTP
│   ├── generic/                   # Bare-metal / multi-cloud image profile
│   ├── genericcloud/              # Minimal virtualized footprint profile
│   ├── nocloud/                   # Local VM profile with systemd-firstboot
│   ├── qemu/                      # Local QEMU testing profile
│   ├── bookworm/                  # Debian 12 (Bookworm)
│   ├── trixie/                    # Debian 13 (Trixie)
│   ├── forky/                     # Debian 14 (Forky) with dracut
│   └── sid/                       # Debian Unstable (Sid)
├── mkosi.extra/                   # Base filesystem overlay (cloud-init, systemd)
├── mkosi.postinst                 # Post-installation master runner
├── mkosi.postinst.d/              # Modular post-installation hooks
└── scripts/
    └── verify-image-parity.sh     # Image parity auditing tool
```

---

## License

Same terms as Debian cloud image tools (GPL-2.0+ / MIT where applicable).
