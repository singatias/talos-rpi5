# Technical Guide

Build infrastructure, CI/CD configuration, and project structure for the Talos CM5 Builder.

## Building locally (ARM64 host required)

```bash
make checkouts patches   # Clone and patch upstream sources
make kernel              # Build RPi kernel
make overlay             # Build SBC overlay
make installer           # Build installer + disk image
```

## CI/CD (Gitea Actions)

Push a version tag to trigger an automated build:

```bash
git tag v1.12.3-k6.12.47-2
git push origin v1.12.3-k6.12.47-2
```

The pipeline runs on the ARM64 self-hosted runner and:
1. Builds the kernel, overlay, and installer
2. Attaches SBOM attestation (cosign + syft)
3. Pushes the installer image to Docker Hub
4. Creates a Gitea release with the raw disk image

### Upstream update checks

A weekly scheduled workflow checks for new Talos and RPi kernel releases and creates Gitea issues when updates are available.

## CI Secrets

| Secret | Description |
|--------|-------------|
| `REGISTRY_USERNAME` | Docker Hub username (org-level) |
| `REGISTRY_PASSWORD` | Docker Hub access token (org-level) |

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

## Project Structure

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
cosign.pub                 # Public key for verifying image attestations
```
