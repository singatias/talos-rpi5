#!/usr/bin/env bash
# Check for upstream Talos and RPi kernel updates
#
# Compares current versions (from Makefile + pkgs patch) against the
# latest GitHub releases/tags. Outputs GitHub Actions-compatible variables.
#
# Usage:
#   ./scripts/check-upstream.sh           # Print results to stdout/stderr
#   ./scripts/check-upstream.sh >> "$GITHUB_OUTPUT"  # For CI

set -euo pipefail

MAKEFILE="${MAKEFILE:-Makefile}"
PATCH_FILE="${PATCH_FILE:-patches/siderolabs/pkgs/0001-Patched-for-Raspberry-Pi-5.patch}"

# ── Current versions ────────────────────────────────────────────────
CURRENT_TALOS=$(grep '^TALOS_VERSION' "$MAKEFILE" | awk '{print $NF}')
CURRENT_RPI_TAG=$(grep '+  linux_version:' "$PATCH_FILE" | awk '{print $NF}')

echo "Current Talos version: $CURRENT_TALOS" >&2
echo "Current RPi kernel tag: $CURRENT_RPI_TAG" >&2

# ── Latest versions from GitHub API ─────────────────────────────────
LATEST_TALOS=$(curl -sf "https://api.github.com/repos/siderolabs/talos/releases/latest" \
  | jq -r '.tag_name')

LATEST_RPI_TAG=$(curl -sf "https://api.github.com/repos/raspberrypi/linux/tags?per_page=20" \
  | jq -r '[.[] | select(.name | startswith("stable_"))][0].name')

echo "Latest Talos release:  $LATEST_TALOS" >&2
echo "Latest RPi kernel tag: $LATEST_RPI_TAG" >&2

# ── Determine what needs updating ───────────────────────────────────
TALOS_UPDATE=false
RPI_UPDATE=false

if [ "$CURRENT_TALOS" != "$LATEST_TALOS" ]; then
  TALOS_UPDATE=true
  echo ">> Talos update available: $CURRENT_TALOS -> $LATEST_TALOS" >&2
else
  echo ">> Talos is up to date" >&2
fi

if [ "$CURRENT_RPI_TAG" != "$LATEST_RPI_TAG" ]; then
  RPI_UPDATE=true
  echo ">> RPi kernel update available: $CURRENT_RPI_TAG -> $LATEST_RPI_TAG" >&2
else
  echo ">> RPi kernel is up to date" >&2
fi

# ── Output for GitHub Actions ───────────────────────────────────────
echo "talos_current=$CURRENT_TALOS"
echo "talos_latest=$LATEST_TALOS"
echo "talos_update=$TALOS_UPDATE"
echo "rpi_current=$CURRENT_RPI_TAG"
echo "rpi_latest=$LATEST_RPI_TAG"
echo "rpi_update=$RPI_UPDATE"
