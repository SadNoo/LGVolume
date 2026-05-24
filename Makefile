APP_NAME := LGVolume
BUILD_DIR := .build
DIST_DIR := dist
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app
INSTALL_DIR ?= $(HOME)/Applications
BUILD_ENV := HOME=$(CURDIR) CLANG_MODULE_CACHE_PATH=$(CURDIR)/$(BUILD_DIR)/ModuleCache SWIFTPM_CUSTOM_CACHE_PATH=$(CURDIR)/$(BUILD_DIR)/SwiftPMCache

.PHONY: build run install clean

build:
	env $(BUILD_ENV) ./Scripts/package_app.sh

run: build
	open "$(APP_BUNDLE)"

install: build
	mkdir -p "$(INSTALL_DIR)"
	rsync -a --delete "$(APP_BUNDLE)" "$(INSTALL_DIR)/"

clean:
	rm -rf "$(BUILD_DIR)" "$(DIST_DIR)"
