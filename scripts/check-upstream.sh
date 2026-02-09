#!/usr/bin/env bash
# Check for upstream Talos and RPi kernel updates
#
# Compares current versions in Makefile against the latest GitHub releases.
# Outputs GitHub Actions-compatible variables for use in CI workflows.
#
# Usage:
#   ./scripts/check-upstream.sh           # Print results
#   ./scripts/check-upstream.sh >> "$GITHUB_OUTPUT"  # For CI

set -euo pipefail

MAKEFILE="${MAKEFILE:-Makefile}"

# Extract current versions from Makefile
CURRENT_TALOS=$(grep '^TALOS_VERSION' "$MAKEFILE" | head -1 | awk '{print $NF}')
CURRENT_PKG=$(grep '^PKG_VERSION' "$MAKEFILE" | head -1 | awk '{print $NF}')

echo "Current Talos version: $CURRENT_TALOS"
echo "Current PKG version:   $CURRENT_PKG"

# Check latest Talos stable release
LATEST_TALOS=$(curl -sf "https://api.github.com/repos/siderolabs/talos/releases/latest" \
  | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

echo "Latest Talos release:  $LATEST_TALOS"

# Check latest RPi kernel stable tag (format: stable_YYYYMMDD)
LATEST_RPI_KERNEL=$(curl -sf "https://api.github.com/repos/raspberrypi/linux/tags?per_page=10" \
  | grep '"name"' | grep 'stable_' | head -1 | sed -E 's/.*"name": *"([^"]+)".*/\1/')

echo "Latest RPi kernel tag: $LATEST_RPI_KERNEL"

# Output for GitHub Actions
echo "talos_current=$CURRENT_TALOS"
echo "talos_latest=$LATEST_TALOS"

if [ "$CURRENT_TALOS" != "$LATEST_TALOS" ]; then
  echo "talos_update=true"
  echo ">> Talos update available: $CURRENT_TALOS -> $LATEST_TALOS" >&2
else
  echo "talos_update=false"
  echo ">> Talos is up to date" >&2
fi

# For RPi kernel, we output what we found — the actual version tracking
# depends on the pkgs patch content which references a specific kernel tag
echo "rpi_current=check-patch"
echo "rpi_latest=$LATEST_RPI_KERNEL"

# We always flag RPi kernel for review since we can't easily parse the
# patch to extract the exact pinned version
echo "rpi_update=true"
echo ">> RPi kernel latest stable: $LATEST_RPI_KERNEL (review patch manually)" >&2
