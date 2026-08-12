# Makefile for native_ai_engine
# Optimized for Android system binary execution in /system/bin

CXX ?= clang++
CARGO ?= cargo
CXXFLAGS ?= -std=c++20 -O3 -Wall -Wextra -Iinclude -DENABLE_NEON=1 -pthread
LDFLAGS ?= -pthread -llog

TARGET_NAME = native_ai_engine
BUILD_DIR = build
SRC_DIR = src
INC_DIR = include

CPP_SOURCES = $(SRC_DIR)/main.cpp $(SRC_DIR)/ai_engine.cpp $(SRC_DIR)/model_loader.cpp
DEPLOY_SCRIPT = $(HOME)/Projects/local/deploy_scripts/deploy.sh

.PHONY: all build build-cmake build-rust clean deploy test help ndk-build

all: build

help:
	@echo "Native AI Engine Build System"
	@echo "============================="
	@echo "  make build       : Build C++ binary directly using Clang/GCC"
	@echo "  make build-cmake : Build C++ binary via CMake in build/"
	@echo "  make build-rust  : Build Rust release binary via Cargo"
	@echo "  make ndk-build   : Build using Android NDK toolchain"
	@echo "  make test        : Run functional test suite"
	@echo "  make deploy      : Deploy binary to /system/bin using deploy.sh (requires root)"
	@echo "  make clean       : Remove all build artifacts"

build: $(BUILD_DIR)/$(TARGET_NAME)

$(BUILD_DIR)/$(TARGET_NAME): $(CPP_SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(CPP_SOURCES) -o $@ $(LDFLAGS)
	@echo "[+] Successfully built C++ binary: $@"

build-cmake:
	@mkdir -p $(BUILD_DIR)
	@cd $(BUILD_DIR) && cmake -DCMAKE_BUILD_TYPE=Release .. && $(MAKE)
	@echo "[+] Successfully built C++ binary via CMake: $(BUILD_DIR)/$(TARGET_NAME)"

build-rust:
	$(CARGO) build --release
	@mkdir -p $(BUILD_DIR)
	@cp target/release/$(TARGET_NAME) $(BUILD_DIR)/$(TARGET_NAME)
	@echo "[+] Successfully built Rust binary: $(BUILD_DIR)/$(TARGET_NAME)"

ndk-build:
	@if [ -z "$$NDK_ROOT" ]; then \
		echo "[!] Error: NDK_ROOT environment variable is not set."; \
		echo "    Example: export NDK_ROOT=/path/to/android-ndk-r25c"; \
		exit 1; \
	fi
	@mkdir -p $(BUILD_DIR)
	@cd $(BUILD_DIR) && cmake \
		-DCMAKE_TOOLCHAIN_FILE=$$NDK_ROOT/build/cmake/android.toolchain.cmake \
		-DANDROID_ABI=arm64-v8a \
		-DANDROID_PLATFORM=android-29 \
		-DCMAKE_BUILD_TYPE=Release .. && $(MAKE)
	@echo "[+] Android NDK ARM64 build complete: $(BUILD_DIR)/$(TARGET_NAME)"

test: build
	@echo "[+] Running native_ai_engine test suite..."
	@./$(BUILD_DIR)/$(TARGET_NAME) --help
	@./$(BUILD_DIR)/$(TARGET_NAME) --test

deploy:
	@if [ ! -f "$(BUILD_DIR)/$(TARGET_NAME)" ]; then \
		echo "[!] Binary $(BUILD_DIR)/$(TARGET_NAME) not found. Run 'make build' first."; \
		exit 1; \
	fi
	@if [ -f "$(DEPLOY_SCRIPT)" ]; then \
		echo "[+] Invoking deployment script: $(DEPLOY_SCRIPT)"; \
		su -c "$(DEPLOY_SCRIPT) $(PWD)/$(BUILD_DIR)/$(TARGET_NAME)"; \
	else \
		echo "[!] Deployment script not found at $(DEPLOY_SCRIPT)"; \
		exit 1; \
	fi

clean:
	@rm -rf $(BUILD_DIR) target
	@echo "[+] Cleaned build artifacts."
