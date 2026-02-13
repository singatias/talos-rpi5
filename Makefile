# Talos CM5 Builder — Custom Talos Linux images for Raspberry Pi CM5
#
# Forked from https://github.com/talos-rpi5/talos-builder
# Builds Talos with the RPi downstream kernel (CM5/RP1 support)
#
# Usage:
#   make checkouts patches   # Clone and patch upstream sources
#   make kernel              # Build RPi kernel (~15-30 min on ARM64)
#   make overlay             # Build U-Boot + firmware + DTBs
#   make installer           # Build installer image + raw disk image
#   make release             # Tag and push release images
#   make clean               # Remove checkouts and build artifacts

PKG_VERSION = v1.12.0
TALOS_VERSION = v1.12.3
SBCOVERLAY_VERSION = main

# Prefer GNU coreutils (macOS: brew install gnu-sed coreutils)
export PATH := /opt/homebrew/opt/gnu-sed/libexec/gnubin:$(PATH)

REGISTRY ?= docker.io
REGISTRY_USERNAME ?= svrnty

TAG ?= $(shell git describe --tags --exact-match 2>/dev/null || echo dev)

# Docker Hub image names (project-specific)
KERNEL_IMAGE = $(REGISTRY)/$(REGISTRY_USERNAME)/talos-rpi5-kernel
OVERLAY_IMAGE = $(REGISTRY)/$(REGISTRY_USERNAME)/talos-rpi5-overlay
IMAGER_IMAGE = $(REGISTRY)/$(REGISTRY_USERNAME)/talos-rpi5-imager
INSTALLER_IMAGE = $(REGISTRY)/$(REGISTRY_USERNAME)/talos-rpi5-installer

# Public image name on Docker Hub (used by talosctl upgrade)
IMAGE_NAME ?= talos-rpi5

# System extensions baked into the image
EXTENSIONS ?= ghcr.io/siderolabs/iscsi-tools:v0.1.6 ghcr.io/siderolabs/util-linux-tools:2.40.4

# Upstream repositories
PKG_REPOSITORY = https://github.com/siderolabs/pkgs.git
TALOS_REPOSITORY = https://github.com/siderolabs/talos.git
SBCOVERLAY_REPOSITORY = https://github.com/talos-rpi5/sbc-raspberrypi5.git

CHECKOUTS_DIRECTORY := $(PWD)/checkouts
PATCHES_DIRECTORY := $(PWD)/patches

PKGS_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/pkgs && git describe --tag --always --dirty --match v[0-9]\*)
TALOS_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/talos && git describe --tag --always --dirty --match v[0-9]\*)
SBCOVERLAY_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5 && git describe --tag --always)-$(PKGS_TAG)

# Build the --system-extension-image flags from the EXTENSIONS list
EXTENSION_FLAGS = $(foreach ext,$(EXTENSIONS),--system-extension-image=$(ext))

# Supply chain attestation flags (overrides upstream --provenance=false)
ATTESTATION_ARGS = --provenance=mode=max --sbom=true

# Common imager flags for overlay and extensions
IMAGER_COMMON_FLAGS = \
	--overlay-name="rpi5" \
	--overlay-image="$(OVERLAY_IMAGE):$(SBCOVERLAY_TAG)" \
	--overlay-option="configTxtAppend=$$(cat $(PWD)/config/config.txt.append)" \
	$(EXTENSION_FLAGS)

#
# Help
#
.PHONY: help
help:
	@echo "Talos CM5 Builder"
	@echo ""
	@echo "Targets:"
	@echo "  checkouts  — Clone upstream repositories"
	@echo "  patches    — Apply RPi kernel + CM5 patches"
	@echo "  kernel     — Build RPi downstream kernel"
	@echo "  overlay    — Build SBC overlay (U-Boot, firmware, DTBs)"
	@echo "  installer  — Build Talos installer image + raw disk image"
	@echo "  release    — Tag and push release images"
	@echo "  clean      — Remove checkouts and build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  TALOS_VERSION       = $(TALOS_VERSION)"
	@echo "  PKG_VERSION         = $(PKG_VERSION)"
	@echo "  REGISTRY            = $(REGISTRY)"
	@echo "  REGISTRY_USERNAME   = $(REGISTRY_USERNAME)"
	@echo ""
	@echo "Images:"
	@echo "  KERNEL_IMAGE        = $(KERNEL_IMAGE)"
	@echo "  OVERLAY_IMAGE       = $(OVERLAY_IMAGE)"
	@echo "  IMAGER_IMAGE        = $(IMAGER_IMAGE)"
	@echo "  INSTALLER_IMAGE     = $(INSTALLER_IMAGE)"

#
# Checkouts
#
.PHONY: checkouts checkouts-clean
checkouts:
	git clone -c advice.detachedHead=false --branch "$(PKG_VERSION)" "$(PKG_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/pkgs"
	git clone -c advice.detachedHead=false --branch "$(TALOS_VERSION)" "$(TALOS_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/talos"
	git clone -c advice.detachedHead=false --branch "$(SBCOVERLAY_VERSION)" "$(SBCOVERLAY_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5"

checkouts-clean:
	rm -rf "$(CHECKOUTS_DIRECTORY)/pkgs"
	rm -rf "$(CHECKOUTS_DIRECTORY)/talos"
	rm -rf "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5"

#
# Patches
#
.PHONY: patches-pkgs patches-talos patches-overlay patches
patches-pkgs:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/pkgs/"*.patch

patches-talos:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/talos/"*.patch

patches-overlay:
	@cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5" && \
		GO_VER=$$(sed -n 's/^go //p' go.work | head -1) && \
		GO_MINOR=$$(echo "$$GO_VER" | cut -d. -f1,2) && \
		if [ "$$GO_MINOR" = "1.24" ]; then \
			echo "Overlay Go $$GO_VER — applying Go toolchain patch (CVE fix)"; \
			git am "$(PATCHES_DIRECTORY)/talos-rpi5/sbc-raspberrypi5/"*.patch; \
		else \
			echo "Overlay Go $$GO_VER — skipping Go toolchain patch (CVEs fixed upstream)"; \
		fi

patches: patches-pkgs patches-talos patches-overlay

#
# Kernel — build and push the RPi downstream kernel
#
.PHONY: kernel
kernel:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		$(MAKE) docker-kernel \
			TARGET_ARGS="--tag=$(KERNEL_IMAGE):$(PKGS_TAG) --push=true $(ATTESTATION_ARGS)" \
			PLATFORM=linux/arm64

#
# Overlay — build U-Boot + firmware + DTBs
#
# The overlay's pkg.yaml references the kernel as PKGS_PREFIX/kernel:PKGS.
# We rewrite it to point to our project-specific kernel image name.
#
.PHONY: overlay
overlay:
	@echo "SBCOVERLAY_TAG = $(SBCOVERLAY_TAG)"
	@sed -i.bak 's|{{ .BUILD_ARG_PKGS_PREFIX }}/kernel:{{ .BUILD_ARG_PKGS }}|$(KERNEL_IMAGE):$(PKGS_TAG)|' \
		"$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5/internal/base/pkg.yaml" && \
		rm -f "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5/internal/base/pkg.yaml.bak"
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5" && \
		$(MAKE) docker-sbc-raspberrypi5 \
			TARGET_ARGS="--tag=$(OVERLAY_IMAGE):$(SBCOVERLAY_TAG) --push=true $(ATTESTATION_ARGS)" \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64

#
# Installer / Disk Image
#
# Builds the imager, installer-base, and installer images step by step,
# pushing each to our project-specific Docker Hub repos.
#
.PHONY: installer
installer:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) \
			PKG_KERNEL=$(KERNEL_IMAGE):$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			kernel initramfs && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) \
			PKG_KERNEL=$(KERNEL_IMAGE):$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			target-imager \
			TARGET_ARGS="--output type=image,name=$(IMAGER_IMAGE):$(TALOS_TAG),push=true $(ATTESTATION_ARGS)" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) \
			PKG_KERNEL=$(KERNEL_IMAGE):$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			target-installer-base \
			TARGET_ARGS="--output type=image,name=$(INSTALLER_IMAGE):base-$(TALOS_TAG),push=true $(ATTESTATION_ARGS)" && \
		docker pull $(IMAGER_IMAGE):$(TALOS_TAG) && \
		docker run --rm -t -v ./_out:/out --privileged --network=host \
			$(IMAGER_IMAGE):$(TALOS_TAG) \
			installer --arch arm64 \
			--base-installer-image="$(INSTALLER_IMAGE):base-$(TALOS_TAG)" \
			$(IMAGER_COMMON_FLAGS) && \
		LOADED=$$(docker load -i ./_out/installer-arm64.tar | sed 's/Loaded image: //') && \
		printf "FROM $$LOADED\n" | docker buildx build \
			--platform linux/arm64 \
			$(ATTESTATION_ARGS) \
			-t $(INSTALLER_IMAGE):$(TALOS_TAG) --push - && \
		docker \
			run --rm -t -v ./_out:/out -v /dev:/dev --privileged \
			$(IMAGER_IMAGE):$(TALOS_TAG) \
			metal --arch arm64 \
			--base-installer-image="$(INSTALLER_IMAGE):$(TALOS_TAG)" \
			$(IMAGER_COMMON_FLAGS)

#
# Release — tag images with the Git tag for stable references
#
.PHONY: release
release:
	docker buildx imagetools create \
		-t $(REGISTRY)/$(REGISTRY_USERNAME)/$(IMAGE_NAME):$(TAG) \
		$(INSTALLER_IMAGE):$(TALOS_TAG)

#
# Clean
#
.PHONY: clean
clean: checkouts-clean
	rm -rf _out
	rm -rf checkouts/_out
