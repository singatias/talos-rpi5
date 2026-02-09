# Talos CM5 Builder

Custom Talos Linux images for Raspberry Pi CM5 on Compute Blade hardware.

The official Talos Image Factory does not support CM5 — the mainline kernel lacks CM5 device trees and RP1 driver support. This builder uses the RPi downstream kernel (via [talos-rpi5/talos-builder](https://github.com/talos-rpi5/talos-builder) patches) to produce working CM5 images with our extensions and overclock config.

## What it builds

- **Installer image** → `docker.io/svrnty/installer:<tag>` (for `talosctl upgrade`)
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
git tag v1.11.5-1
git push origin v1.11.5-1
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
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `GITEA_TOKEN` | Gitea API token (for creating releases and issues) |

## Runner Setup (ASUS GX10)

The ARM64 build runner needs:
- Docker + Docker Buildx
- Gitea `act_runner` registered with labels: `self-hosted`, `linux`, `arm64`
- Sufficient disk space for kernel builds (~20GB)

```bash
# Install act_runner
curl -sL https://gitea.com/gitea/act_runner/releases/latest/download/act_runner-linux-arm64 -o act_runner
chmod +x act_runner

# Register
./act_runner register --instance <gitea-url> --token <runner-token>

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
```
