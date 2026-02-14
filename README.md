# Talos CM5 Builder

Custom Talos Linux images for Raspberry Pi 5 / CM5 on Compute Blade hardware.

<a href="https://hub.docker.com/r/svrnty/talos-rpi5" target="_blank"><img src="https://img.shields.io/docker/v/svrnty/talos-rpi5?sort=semver&label=talos-rpi5&logo=docker&arch=arm64" alt="Docker Hub"></a>
<a href="https://hub.docker.com/r/svrnty/talos-rpi5" target="_blank"><img src="https://img.shields.io/docker/pulls/svrnty/talos-rpi5?logo=docker" alt="Docker Pulls"></a>
<a href="https://hub.docker.com/r/svrnty/talos-rpi5" target="_blank"><img src="https://img.shields.io/docker/image-size/svrnty/talos-rpi5?sort=semver&logo=docker&arch=arm64" alt="Docker Image Size"></a>

The official Talos Image Factory does not support CM5 — the mainline kernel lacks CM5 device trees and RP1 driver support. This builder uses the RPi downstream kernel (via [talos-rpi5/talos-builder](https://github.com/talos-rpi5/talos-builder) patches) to produce working CM5 images with our extensions and overclock config.

## Current versions

| Component | Version |
|-----------|---------|
| Talos Linux | <a href="https://github.com/siderolabs/talos" target="_blank"><img src="https://img.shields.io/badge/talos-v1.12.3-blue?logo=kubernetes&logoColor=white" alt="Talos version"></a> |
| RPi Kernel | <a href="https://github.com/raspberrypi/linux" target="_blank"><img src="https://img.shields.io/badge/kernel-6.12.47-blue?logo=linux&logoColor=white" alt="Kernel version"></a> |
| iscsi-tools | <a href="https://github.com/siderolabs/extensions" target="_blank"><img src="https://img.shields.io/badge/iscsi--tools-v0.1.6-blue?logo=docker" alt="iscsi-tools version"></a> |
| util-linux-tools | <a href="https://github.com/siderolabs/extensions" target="_blank"><img src="https://img.shields.io/badge/util--linux--tools-2.40.4-blue?logo=docker" alt="util-linux-tools version"></a> |

## Image tags

Release images are published to <a href="https://hub.docker.com/r/svrnty/talos-rpi5" target="_blank"><code>docker.io/svrnty/talos-rpi5</code></a> with the format:

```
v<talos>-k<kernel>-<revision>
```

For example: `v1.12.3-k6.12.47-2`

| Segment | Meaning |
|---------|---------|
| `v1.12.3` | Upstream Talos Linux version |
| `k6.12.47` | RPi downstream kernel version |
| `2` | Build revision (bumped for config/patch changes on the same upstream versions) |

## Usage

### Install from raw disk image

Download `metal-arm64.raw.zst` from the [latest release](../../releases/latest) and flash to eMMC:

```bash
zstd -d metal-arm64.raw.zst -o metal-arm64.raw
# Flash to eMMC/SD via your preferred tool (dd, balenaEtcher, etc.)
```

### Upgrade an existing node

```bash
talosctl upgrade --image docker.io/svrnty/talos-rpi5:v1.12.3-k6.12.47-2
```

> **Note:** In-place upgrades use GRUB with `--no-nvram` to work around the RPi5/CM5 `SetVariableRT` firmware limitation. This patch is included but not yet tested in production — re-flashing the disk image is the proven fallback.

```bash
# Fallback: re-flash method
zstd -d metal-arm64.raw.zst -o metal-arm64.raw
# Flash to eMMC/SD via your preferred tool
```

### What's included

- RPi downstream kernel with CM5/RP1 support (4K page size, aligned with upstream Talos)
- GRUB bootloader with `--no-nvram` for reliable `talosctl upgrade` on RPi5/CM5
- Overclock: 2.6GHz (`arm_freq=2600`, `over_voltage_delta=50000`, `arm_boost=1`)
- Extensions: `iscsi-tools`, `util-linux-tools`

## Known issues

### No serial console output after boot

Serial output goes silent after the EFI stub decompresses the kernel and exits boot services. This affects headless debugging on CM5 boards where serial is the primary console.

*Upstream: <a href="https://github.com/talos-rpi5/talos-builder/issues/4" target="_blank">talos-builder#4</a>*

### Install disk config ignored on SBCs

Talos ignores the `machine.install.disk` config field on SBC platforms. You **must flash the disk image directly** to your target disk (eMMC, SD, NVMe). Booting from USB or NVMe also requires flashing directly to that disk — the image targets SD (`mmcblk0`) by default.

*Upstream: <a href="https://github.com/talos-rpi5/talos-builder/issues/22" target="_blank">talos-builder#22</a>*

## Roadmap

This project targets production-ready Talos clusters on RPi5/CM5 hardware.

| Status | Milestone | Description |
|--------|-----------|-------------|
| Untested | **4K page size** | Aligned with upstream Talos kernel config. Reduces memory overhead and improves workload compatibility (Longhorn, jemalloc, F2FS, etc.). |
| Untested | **Reliable in-place upgrades** | Force GRUB bootloader with `--no-nvram` on arm64 to work around the `SetVariableRT` firmware limitation (<a href="https://github.com/talos-rpi5/talos-builder/issues/21" target="_blank">talos-builder#21</a>). |
| Pending | **Serial console fix** | Debug U-Boot/kernel handoff to restore serial output after EFI stub exit. |
| Pending | **NVMe boot support** | Produce images that target NVMe directly, or document a supported NVMe boot flow. |

## Building

For local builds, CI/CD setup, runner configuration, and project structure, see [TECHNICAL.md](TECHNICAL.md).

## License

This project is licensed under the [Mozilla Public License 2.0](LICENSE).

It builds upon the following MPL 2.0 licensed upstream projects:

- [siderolabs/talos](https://github.com/siderolabs/talos) — Talos Linux OS
- [siderolabs/pkgs](https://github.com/siderolabs/pkgs) — Talos package definitions
- [talos-rpi5/sbc-raspberrypi5](https://github.com/talos-rpi5/sbc-raspberrypi5) — Raspberry Pi 5 SBC overlay

Our patches to these projects are in the `patches/` directory and are distributed under the same MPL 2.0 terms.
