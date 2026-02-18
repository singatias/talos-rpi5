# Talos CM5 Builder

Custom Talos Linux images for Raspberry Pi 5 / CM5 on Compute Blade hardware.

<a href="https://hub.docker.com/r/svrnty/talos-rpi5" target="_blank"><img src="https://img.shields.io/docker/v/svrnty/talos-rpi5?sort=semver&label=talos-rpi5&logo=docker&arch=arm64" alt="Docker Hub"></a>
<a href="https://hub.docker.com/r/svrnty/talos-rpi5" target="_blank"><img src="https://img.shields.io/docker/pulls/svrnty/talos-rpi5?logo=docker" alt="Docker Pulls"></a>
<a href="https://hub.docker.com/r/svrnty/talos-rpi5" target="_blank"><img src="https://img.shields.io/docker/image-size/svrnty/talos-rpi5?sort=semver&logo=docker&arch=arm64" alt="Docker Image Size"></a>

The official Talos Image Factory does not support CM5 — the mainline kernel lacks CM5 device trees and RP1 driver support. This builder uses the RPi downstream kernel (via [talos-rpi5/talos-builder](https://github.com/talos-rpi5/talos-builder) patches) to produce working CM5 images with our extensions and overclock config.

## Current versions

| Component | Version |
|-----------|---------|
| Talos Linux | <a href="https://github.com/siderolabs/talos" target="_blank"><img src="https://img.shields.io/badge/talos-v1.12.4-blue?logo=kubernetes&logoColor=white" alt="Talos version"></a> |
| RPi Kernel | <a href="https://github.com/raspberrypi/linux" target="_blank"><img src="https://img.shields.io/badge/kernel-6.12.47-blue?logo=linux&logoColor=white" alt="Kernel version"></a> |
| iscsi-tools | <a href="https://github.com/siderolabs/extensions" target="_blank"><img src="https://img.shields.io/badge/iscsi--tools-v0.1.6-blue?logo=docker" alt="iscsi-tools version"></a> |
| util-linux-tools | <a href="https://github.com/siderolabs/extensions" target="_blank"><img src="https://img.shields.io/badge/util--linux--tools-2.40.4-blue?logo=docker" alt="util-linux-tools version"></a> |

## Image tags

Release images are published to <a href="https://hub.docker.com/r/svrnty/talos-rpi5" target="_blank"><code>docker.io/svrnty/talos-rpi5</code></a> with the format:

```
v<talos>-k<kernel>-<revision>
```

For example: `v1.12.4-k6.12.47-4`

| Segment | Meaning |
|---------|---------|
| `v1.12.4` | Upstream Talos Linux version |
| `k6.12.47` | RPi downstream kernel version |
| `3` | Build revision (bumped for config/patch changes on the same upstream versions) |

## Usage

### Install from raw disk image

Download `metal-arm64.raw.zst` from the [latest release](../../releases/latest) and flash to eMMC:

```bash
zstd -d metal-arm64.raw.zst -o metal-arm64.raw
# Flash to eMMC/SD via your preferred tool (dd, balenaEtcher, etc.)
```

### Upgrade an existing node

```bash
talosctl upgrade --image docker.io/svrnty/talos-rpi5:v1.12.4-k6.12.47-4 --nodes <node-ip>
```

In-place upgrades are fully supported. The image includes patches to force GRUB with `--no-nvram` on arm64 (working around the RPi5/CM5 `SetVariableRT` firmware limitation) and to handle the SBC EFI-only disk layout (no separate BOOT partition).

### What's included

- RPi downstream kernel with CM5/RP1 support (4K page size, aligned with upstream Talos)
- GRUB bootloader with `--no-nvram` for reliable `talosctl upgrade` on RPi5/CM5
- SBC EFI-only boot layout support (probe, install, revert all fall back to EFI partition when BOOT partition is absent)
- Fallback to classic bind mounts on kernels without `open_tree` support (Linux <6.15)
- Overclock: 2.6GHz (`arm_freq=2600`, `over_voltage_delta=50000`, `arm_boost=1`)
- PCIe Gen 3 enabled for NVMe (~800 MB/s, via `dtparam=pciex1_gen=3` in `config.txt`)
- Extensions: `iscsi-tools`, `util-linux-tools`

## Known issues

### ~~No serial console output after boot~~ (Fixed)

The overlay was using `console=ttyAMA0` (GPIO 14/15 UART) but the RPi5/CM5 debug UART is `ttyAMA10`. Fixed by switching to `console=ttyAMA10,115200` and adding `earlycon=pl011,0x107d001000,115200n8` for early boot output. Also added `[pi5] enable_uart=0` to `config.txt` to match upstream and avoid U-Boot compatibility issues.

*Upstream: <a href="https://github.com/talos-rpi5/talos-builder/issues/4" target="_blank">talos-builder#4</a>*

### Install disk config ignored on SBCs

Talos ignores the `machine.install.disk` config field on SBC platforms. You **must flash the disk image directly** to your target disk (eMMC, SD, NVMe). For NVMe boot, `dd` the metal image to the NVMe drive and configure the EEPROM boot order (`BOOT_ORDER=0xf416`, `PCIE_PROBE=1`).

*Upstream: <a href="https://github.com/talos-rpi5/talos-builder/issues/22" target="_blank">talos-builder#22</a>*

## Patches

| Patch | Target | Description |
|-------|--------|-------------|
| `0001` (pkgs) | Kernel | RPi downstream kernel 6.12.x with CM5/RP1 device tree and driver support |
| `0001` (talos) | Modules | arm64 kernel module list for RPi downstream kernel |
| `0002` (talos) | GRUB | `--no-nvram` for `grub-install` on arm64 (U-Boot lacks EFI `SetVariable`) |
| `0003` (talos) | Bootloader | Force GRUB over sd-boot on arm64 (sd-boot crashes without EFI runtime) |
| `0004` (talos) | Runtime | Fallback to classic bind mounts on kernels without `open_tree` (Linux <6.15) |
| `0005` (talos) | GRUB | Handle missing BOOT partition for SBC EFI-only disk layouts |
| `0001` (overlay) | Toolchain | Bump Go to 1.24.13 (CVE fix) |
| `0002` (overlay) | Console | Fix serial console for RPi5/CM5 debug UART (`ttyAMA10`) |
| `0003` (overlay) | Upgrade | Detect EFI mount path for SBC layouts (no BOOT partition) |

## Roadmap

This project targets production-ready Talos clusters on RPi5/CM5 hardware.

| Status | Milestone | Description |
|--------|-----------|-------------|
| Tested | **4K page size** | Aligned with upstream Talos kernel config. Reduces memory overhead and improves workload compatibility (Longhorn, jemalloc, F2FS, etc.). |
| Tested | **Reliable in-place upgrades** | Force GRUB bootloader with `--no-nvram` on arm64, handle SBC EFI-only disk layout. Verified end-to-end with `talosctl upgrade`. |
| Tested | **Kernel <6.15 compatibility** | Unconditional `open_tree` capability check — falls back to classic bind mounts on RPi downstream kernel 6.12.x. |
| Untested | **Serial console fix** | Use correct debug UART (`ttyAMA10`) with `earlycon` for early boot output. |
| Tested | **NVMe boot support** | `dd` image to NVMe + set EEPROM `BOOT_ORDER=0xf416` and `PCIE_PROBE=1`. Verified on 1TB Kingston NVMe on Compute Blade. |

## NVMe boot

The kernel has NVMe built-in (`CONFIG_BLK_DEV_NVME=y`), so booting from NVMe should work by flashing the disk image directly and configuring the RPi5/CM5 EEPROM.

### 1. Flash the image to NVMe

Connect the NVMe drive via a USB adapter and flash:

```bash
zstd -d metal-arm64.raw.zst | sudo dd of=/dev/<nvme-device> bs=4M status=progress
sync
```

### 2. Configure EEPROM boot order

Use `rpiboot` to update the CM5 EEPROM. Clone the usbboot repo and edit the boot config:

```bash
git clone --depth=1 https://github.com/raspberrypi/usbboot
cd usbboot && make
# Edit the EEPROM config for CM5
cp recovery/boot.conf recovery/boot.conf.bak
```

Add or update these values in `recovery/boot.conf`:

```ini
BOOT_ORDER=0xf416
PCIE_PROBE=1
```

Then flash via USB with the CM5 in USB boot mode (hold nRPIBOOT or disable eMMC boot on your carrier board):

```bash
sudo ./rpiboot -d recovery
```

`BOOT_ORDER` is read right-to-left: try NVMe (`6`) first, then SD (`1`), then USB (`4`), then restart (`f`). `PCIE_PROBE=1` is required for non-HAT+ NVMe adapters (Compute Blade, most M.2 carrier boards).

### 3. Boot from NVMe

Power on. The RPi firmware should find the boot partition on NVMe, load U-Boot, and boot Talos.

### Optional: enable PCIe Gen 3

PCIe Gen 3 doubles NVMe throughput (~400 MB/s → ~800 MB/s). Not officially certified by Raspberry Pi but stable on most NVMe drives.

**New installs** — PCIe Gen 3 is enabled by default in images built from this repo (`config.txt.append` includes `dtparam=pciex1_gen=3`).

**Existing nodes** — After a `talosctl upgrade`, the overlay rewrites `config.txt` with the baked-in settings (including PCIe Gen 3). If you need to enable it manually on an older image:

1. Power off the node and remove the NVMe drive
2. Connect via USB adapter and mount the first (EFI) partition
3. Add to `config.txt` under the `[pi5]` section:
   ```ini
   dtparam=pciex1_gen=3
   ```
4. Unmount, reinstall the drive, and power on

To verify after boot:
```bash
talosctl -n <ip> dmesg | grep -i pcie
# Look for "Gen 3" in the PCIe link speed output
```

## Building

For local builds, CI/CD setup, runner configuration, and project structure, see [TECHNICAL.md](TECHNICAL.md).

## License

This project is licensed under the [Mozilla Public License 2.0](LICENSE).

It builds upon the following MPL 2.0 licensed upstream projects:

- [siderolabs/talos](https://github.com/siderolabs/talos) — Talos Linux OS
- [siderolabs/pkgs](https://github.com/siderolabs/pkgs) — Talos package definitions
- [talos-rpi5/sbc-raspberrypi5](https://github.com/talos-rpi5/sbc-raspberrypi5) — Raspberry Pi 5 SBC overlay

Our patches to these projects are in the `patches/` directory and are distributed under the same MPL 2.0 terms.
