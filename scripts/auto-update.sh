#!/usr/bin/env bash
# Auto-update upstream versions, verify patches, and generate a release tag
#
# Expects environment variables from check-upstream.sh:
#   TALOS_UPDATE, RPI_UPDATE, LATEST_TALOS, LATEST_RPI_TAG
#
# Outputs (for GitHub Actions):
#   patch_failed=true   — if patches fail to apply (caller should create issue)
#   new_tag=<tag>       — the computed release tag (e.g. v1.12.3-k6.12.47-1)
#
# Usage:
#   TALOS_UPDATE=true LATEST_TALOS=v1.13.0 ./scripts/auto-update.sh >> "$GITHUB_OUTPUT"

set -euo pipefail

TALOS_UPDATE=${TALOS_UPDATE:-false}
RPI_UPDATE=${RPI_UPDATE:-false}
LATEST_TALOS=${LATEST_TALOS:-}
LATEST_RPI_TAG=${LATEST_RPI_TAG:-}

MAKEFILE="Makefile"
PATCH_FILE="patches/siderolabs/pkgs/0001-Patched-for-Raspberry-Pi-5.patch"

# Helper: extract kernel semver (e.g. 6.12.47) from the RPi repo Makefile
get_kernel_version() {
  local tag="$1"
  curl -sf "https://raw.githubusercontent.com/raspberrypi/linux/${tag}/Makefile" \
    | awk '
      /^VERSION/     { version=$3 }
      /^PATCHLEVEL/  { patchlevel=$3 }
      /^SUBLEVEL/    { sublevel=$3 }
      END { print version "." patchlevel "." sublevel }
    '
}

# ── RPi kernel update ───────────────────────────────────────────────
if [ "$RPI_UPDATE" = "true" ] && [ -n "$LATEST_RPI_TAG" ]; then
  echo "Updating RPi kernel to $LATEST_RPI_TAG ..." >&2

  # Download tarball and compute checksums
  TARBALL_URL="https://github.com/raspberrypi/linux/archive/refs/tags/${LATEST_RPI_TAG}.tar.gz"
  TMP=$(mktemp)
  curl -sL "$TARBALL_URL" -o "$TMP"
  NEW_SHA256=$(shasum -a 256 "$TMP" | awk '{print $1}')
  NEW_SHA512=$(shasum -a 512 "$TMP" | awk '{print $1}')
  rm -f "$TMP"

  echo "  SHA256: $NEW_SHA256" >&2
  echo "  SHA512: $NEW_SHA512" >&2

  # Get actual kernel version for the config header
  KERNEL_VERSION=$(get_kernel_version "$LATEST_RPI_TAG")
  echo "  Kernel version: $KERNEL_VERSION" >&2

  # Update patch file
  sed -i "s/+  linux_version: .*/+  linux_version: ${LATEST_RPI_TAG}/" "$PATCH_FILE"
  sed -i "s/+  linux_sha256: .*/+  linux_sha256: ${NEW_SHA256}/" "$PATCH_FILE"
  sed -i "s/+  linux_sha512: .*/+  linux_sha512: ${NEW_SHA512}/" "$PATCH_FILE"
  sed -i "s|+# Linux/arm64 .* Kernel Configuration|+# Linux/arm64 ${KERNEL_VERSION} Kernel Configuration|" "$PATCH_FILE"
fi

# ── Talos update ────────────────────────────────────────────────────
if [ "$TALOS_UPDATE" = "true" ] && [ -n "$LATEST_TALOS" ]; then
  echo "Updating Talos to $LATEST_TALOS ..." >&2

  # Update TALOS_VERSION in Makefile
  sed -i "s/^TALOS_VERSION = .*/TALOS_VERSION = ${LATEST_TALOS}/" "$MAKEFILE"

  # Derive matching PKG_VERSION (same major.minor as Talos)
  PKG_MINOR=$(echo "$LATEST_TALOS" | sed -E 's/^(v[0-9]+\.[0-9]+)\..*/\1/')
  LATEST_PKG=$(curl -sf "https://api.github.com/repos/siderolabs/pkgs/tags?per_page=20" \
    | jq -r "[.[] | select(.name | startswith(\"${PKG_MINOR}\"))][0].name")

  if [ -n "$LATEST_PKG" ] && [ "$LATEST_PKG" != "null" ]; then
    echo "  Updating PKG_VERSION to $LATEST_PKG" >&2
    sed -i "s/^PKG_VERSION = .*/PKG_VERSION = ${LATEST_PKG}/" "$MAKEFILE"
  else
    echo "  WARNING: No matching pkgs tag for $PKG_MINOR — keeping current PKG_VERSION" >&2
  fi
fi

# ── Smoke test — verify patches apply ───────────────────────────────
echo "Running patch smoke test ..." >&2
if ! gmake checkouts patches; then
  echo "Patches failed to apply!" >&2
  gmake checkouts-clean >/dev/null 2>&1 || true
  echo "patch_failed=true"
  exit 0
fi
gmake checkouts-clean >/dev/null 2>&1

# ── Generate tag ────────────────────────────────────────────────────
TALOS_VER=$(grep '^TALOS_VERSION' "$MAKEFILE" | awk '{print $NF}')
RPI_TAG=$(grep '+  linux_version:' "$PATCH_FILE" | awk '{print $NF}')
KERNEL_VER=$(get_kernel_version "$RPI_TAG")

# Find next build number for this component combination
TAG_PREFIX="${TALOS_VER}-k${KERNEL_VER}"
LAST_BUILD=$(git tag -l "${TAG_PREFIX}-*" \
  | sed "s|${TAG_PREFIX}-||" \
  | sort -n \
  | tail -1)
NEXT_BUILD=$(( ${LAST_BUILD:-0} + 1 ))
NEW_TAG="${TAG_PREFIX}-${NEXT_BUILD}"

# ── Update README badges and examples ───────────────────────────────
README="README.md"
if [ -f "$README" ]; then
  OLD_TALOS=$(sed -n 's/.*talos-v\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' "$README" | head -1)
  OLD_KERNEL=$(sed -n 's/.*kernel-\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' "$README" | head -1)
  OLD_TAG=$(sed -n 's/.*\(v[0-9]*\.[0-9]*\.[0-9]*-k[0-9]*\.[0-9]*\.[0-9]*-[0-9]*\).*/\1/p' "$README" | head -1)

  echo "Updating README: talos v${OLD_TALOS} → v${TALOS_VER}, kernel ${OLD_KERNEL} → ${KERNEL_VER}, tag ${OLD_TAG} → ${NEW_TAG}" >&2

  sed -i "s/talos-v${OLD_TALOS}/talos-${TALOS_VER}/g" "$README"
  sed -i "s/kernel-${OLD_KERNEL}/kernel-${KERNEL_VER}/g" "$README"
  sed -i "s/\`v${OLD_TALOS}\`/\`${TALOS_VER}\`/g" "$README"
  sed -i "s/\`k${OLD_KERNEL}\`/\`k${KERNEL_VER}\`/g" "$README"
  if [ -n "$OLD_TAG" ]; then
    sed -i "s/${OLD_TAG}/${NEW_TAG}/g" "$README"
  fi
fi

echo "Generated tag: $NEW_TAG" >&2
echo "new_tag=$NEW_TAG"
