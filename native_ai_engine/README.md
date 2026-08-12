# Native AI Engine (`native_ai_engine`)

High-performance raw AI model execution engine scaffolded for Android system execution in `/system/bin`. Supporting zero-copy memory mapping (`mmap`), SIMD/NEON tensor acceleration, multi-threading, CLI generation, and daemon service lifecycle management.

---

## 📁 Directory Architecture

```
~/Projects/local/native_ai_engine/
├── CMakeLists.txt         # Primary CMake build specification (C++20, NEON, NDK, Static)
├── Makefile               # Convenience build automation wrapper & deployment target
├── Cargo.toml             # Rust Cargo package & binary configuration
├── native_ai_engine.rc    # Android init.rc service definition for /system/bin daemon
├── README.md              # Documentation & build instructions
├── include/               # C++ Header declarations
│   ├── ai_engine.hpp      # Core engine lifecycle & generation API
│   ├── model_loader.hpp   # Zero-copy mmap model loading & header verification
│   └── tensor.hpp         # Aligned memory allocation & tensor shapes
└── src/                   # Source implementations
    ├── main.cpp           # C++ Binary CLI & Daemon entrypoint
    ├── ai_engine.cpp      # C++ Engine logic & ARM NEON SIMD kernels
    ├── model_loader.cpp   # C++ mmap binary parser
    ├── main.rs            # Rust Binary CLI entrypoint
    ├── engine.rs          # Rust Engine core
    └── model.rs           # Rust mmap model parser
```

---

## 🛠️ Building the Project

### 1. Direct C++ Build (Clang / Make)
```bash
cd ~/Projects/local/native_ai_engine
make build
```

### 2. CMake Build
```bash
make build-cmake
```

### 3. Android NDK Toolchain Cross-Compilation (ARM64)
```bash
export NDK_ROOT=/path/to/android-ndk
make ndk-build
```

### 4. Rust Cargo Build
```bash
make build-rust
```

---

## 🧪 Testing

Run the self-diagnostic unit test suite:
```bash
make test
```
Or run directly:
```bash
./build/native_ai_engine --test
```

---

## 🚀 System Deployment (`/system/bin`)

To deploy the compiled binary to `/system/bin` and set up the `/system/etc/init/native_ai_engine.rc` service:

```bash
make deploy
```
*(Requires `su` root permissions on Android device)*

---

## 💡 CLI Usage Examples

### Run interactive prompt generation:
```bash
./build/native_ai_engine --prompt "Summarize quantum mechanics" --max-tokens 256 --temp 0.8
```

### Run with a custom binary model file:
```bash
./build/native_ai_engine -m /data/local/tmp/model.bin -p "Hello AI"
```

### Run in background daemon mode:
```bash
./build/native_ai_engine --daemon --verbose
```
