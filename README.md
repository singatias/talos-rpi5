# Talos CM5 Builder

Custom Talos Linux images for Raspberry Pi CM5 on Compute Blade hardware.

[![Docker Hub](https://img.shields.io/docker/v/svrnty/talos-rpi5?sort=semver&label=talos-rpi5&logo=docker)](https://hub.docker.com/r/svrnty/talos-rpi5)
[![Docker Pulls](https://img.shields.io/docker/pulls/svrnty/talos-rpi5?logo=docker)](https://hub.docker.com/r/svrnty/talos-rpi5)
[![Docker Image Size](https://img.shields.io/docker/image-size/svrnty/talos-rpi5?sort=semver&logo=docker)](https://hub.docker.com/r/svrnty/talos-rpi5)

The official Talos Image Factory does not support CM5 — the mainline kernel lacks CM5 device trees and RP1 driver support. This builder uses the RPi downstream kernel (via [talos-rpi5/talos-builder](https://github.com/talos-rpi5/talos-builder) patches) to produce working CM5 images with our extensions and overclock config.

## Current versions

| Component | Version |
|-----------|---------|
| Talos Linux | `v1.12.3` |
| RPi Kernel | `6.12.47` |
| iscsi-tools | `v0.1.6` |
| util-linux-tools | `2.40.4` |

## Image tags

Release images are published to [`docker.io/svrnty/talos-rpi5`](https://hub.docker.com/r/svrnty/talos-rpi5) with the format:

```
v<talos>-k<kernel>-<revision>
```

For example: `v1.12.3-k6.12.47-2`

| Segment | Meaning |
|---------|---------|
| `v1.12.3` | Upstream Talos Linux version |
| `k6.12.47` | RPi downstream kernel version |
| `2` | Build revision (bumped for config/patch changes on the same upstream versions) |

Use this tag with `talosctl upgrade`:

```bash
talosctl upgrade --image docker.io/svrnty/talos-rpi5:v1.12.3-k6.12.47-2
```

## What it builds

- **Installer image** → `docker.io/svrnty/talos-rpi5:<tag>` (for `talosctl upgrade`)
- **Raw disk image** → Gitea release `metal-arm64.raw.zst` (for eMMC flashing)

Baked-in config:
- RPi downstream kernel with CM5/RP1 support
- Overclock: 2.6GHz (`arm_freq=2600`, `over_voltage_delta=50000`, `arm_boost=1`)
- Extensions: `iscsi-tools`, `util-linux-tools`

## Usage

### Building locally (ARM64 host required)

```bash
make checkouts patches   # Clone and patch sources
make kernel              # Build RPi kernel
make overlay             # Build SBC overlay
make installer           # Build installer + disk image
```

### CI/CD (Gitea Actions)

Push a version tag to trigger an automated build:

```bash
git tag v1.12.3-k6.12.47-2
git push origin v1.12.3-k6.12.47-2
```

The pipeline runs on the ARM64 self-hosted runner and:
1. Builds the kernel, overlay, and installer
2. Pushes the installer image to Docker Hub
3. Creates a Gitea release with the raw disk image

### Upstream update checks

A weekly scheduled workflow checks for new Talos and RPi kernel releases and creates Gitea issues when updates are available.

## CI Secrets

| Secret | Description |
|--------|-------------|
| `REGISTRY_USERNAME` | Docker Hub username (org-level) |
| `REGISTRY_PASSWORD` | Docker Hub access token (org-level) |
| `COSIGN_PRIVATE_KEY` | PEM-encoded cosign signing key (org-level) |
| `COSIGN_PASSWORD` | Password for the cosign private key (org-level) |

## Runner Setup (Apple Silicon Mac Mini)

The build runner needs:
- Docker Desktop with Buildx (arm64 native)
- Gitea `act_runner` registered with labels: `self-hosted`, `macOS`, `arm64`
- Sufficient disk space for kernel builds (~20GB)

```bash
# Install act_runner via Homebrew
brew install act_runner

# Or download directly
curl -sL https://gitea.com/gitea/act_runner/releases/latest/download/act_runner-darwin-arm64 -o act_runner
chmod +x act_runner

# Register
./act_runner register \
  --instance https://git.openharbor.io \
  --token <runner-token> \
  --name mac-mini \
  --labels self-hosted,macOS,arm64

# Run as service
./act_runner daemon
```

## Structure

```
.gitea/workflows/
  build.yaml              # Build pipeline (tag push trigger)
  check-updates.yaml      # Upstream update checker (weekly cron)
Makefile                   # Build orchestration
config/
  config.txt.append        # CM5 overclock settings
  extensions.yaml          # System extensions list
scripts/
  check-upstream.sh        # Version comparison script
patches/
  siderolabs/
    pkgs/0001-*.patch      # RPi kernel patch
    talos/0001-*.patch     # Module list patch
  talos-rpi5/
    sbc-raspberrypi5/      # Overlay patches (Go toolchain bump)
```

## License

This project is licensed under the [Mozilla Public License 2.0](LICENSE).

It builds upon the following MPL 2.0 licensed upstream projects:

- [siderolabs/talos](https://github.com/siderolabs/talos) — Talos Linux OS
- [siderolabs/pkgs](https://github.com/siderolabs/pkgs) — Talos package definitions
- [talos-rpi5/sbc-raspberrypi5](https://github.com/talos-rpi5/sbc-raspberrypi5) — Raspberry Pi 5 SBC overlay

Our patches to these projects are in the `patches/` directory and are distributed under the same MPL 2.0 terms.
