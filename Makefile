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
#   make release             # Tag images for release

PKG_VERSION = v1.11.0
TALOS_VERSION = v1.11.5
SBCOVERLAY_VERSION = main

REGISTRY ?= docker.io
REGISTRY_USERNAME ?= svrnty

TAG ?= $(shell git describe --tags --exact-match 2>/dev/null || echo dev)

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
SBCOVERLAY_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5 && git describe --tag --always --dirty)-$(PKGS_TAG)

# Build the --system-extension-image flags from the EXTENSIONS list
EXTENSION_FLAGS = $(foreach ext,$(EXTENSIONS),--system-extension-image=$(ext))

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
.PHONY: patches-pkgs patches-talos patches
patches-pkgs:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/pkgs/"*.patch

patches-talos:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/talos/"*.patch

patches: patches-pkgs patches-talos

#
# Kernel
#
.PHONY: kernel
kernel:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
			PLATFORM=linux/arm64 \
			kernel

#
# Overlay
#
.PHONY: overlay
overlay:
	@echo "SBCOVERLAY_TAG = $(SBCOVERLAY_TAG)"
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) IMAGE_TAG=$(SBCOVERLAY_TAG) PUSH=true \
			PKGS_PREFIX=$(REGISTRY)/$(REGISTRY_USERNAME) PKGS=$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			sbc-raspberrypi5

#
# Installer / Disk Image
#
.PHONY: installer
installer:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			IMAGER_ARGS="--overlay-name=rpi5 --overlay-image=$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi5:$(SBCOVERLAY_TAG) $(EXTENSION_FLAGS)" \
			kernel initramfs imager installer-base installer && \
		docker \
			run --rm -t -v ./_out:/out -v /dev:/dev --privileged \
			$(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) \
			metal --arch arm64 \
			--base-installer-image="$(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG)" \
			--overlay-name="rpi5" \
			--overlay-image="$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi5:$(SBCOVERLAY_TAG)" \
			--overlay-option="configTxtAppend=$$(cat $(PWD)/config/config.txt.append)" \
			$(EXTENSION_FLAGS)

#
# Release — tag images with the Git tag for stable references
#
.PHONY: release
release:
	docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) $(REGISTRY)/$(REGISTRY_USERNAME)/$(IMAGE_NAME):$(TAG) && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/$(IMAGE_NAME):$(TAG)

#
# Clean
#
.PHONY: clean
clean: checkouts-clean
	rm -rf checkouts/_out
