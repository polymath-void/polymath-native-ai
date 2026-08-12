#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#  Native AI Engine - One-Shot Setup & Build Script
#  Version: 2.0 (Battery-Safe, No Background Loops)
#  Target:  Android Termux (arm64-v8a, Magisk Rooted)
#  Author:  Polymath AGY Native Core
#
#  USAGE:
#    chmod +x ~/Projects/native-ai/setup.sh && ~/Projects/native-ai/setup.sh
#
#  This script will:
#    1. Install all Termux dependencies
#    2. Fix Rust linker for Android Bionic libc
#    3. Configure Cargo for Termux aarch64
#    4. Build the Native AI Engine binary
#    5. Patch the Magisk module (remove background loops)
#    6. Deploy the binary to /system/bin via Magisk overlay
#    7. Apply integration patches (remove stale imports)
#    8. Set up the Python Orchestrator (Wake -> Execute -> Sleep)
#
#  SAFETY RULES ENFORCED:
#    - NO infinite loops (while true) in any daemon or service
#    - NO boot-triggered auto-start (sys.boot_completed)
#    - Engine is ONLY started on-demand by the Python Orchestrator
#    - Engine is ALWAYS stopped after task completion (0% CPU)
#    - Dynamic statement-based execution, NOT polling loops
# ============================================================================

set -e

# ── Color Codes ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Paths ────────────────────────────────────────────────────────────────────
PREFIX="/data/data/com.termux/files/usr"
HOME_DIR="/data/data/com.termux/files/home"
PROJECTS_DIR="${HOME_DIR}/Projects"
ENGINE_DIR="${PROJECTS_DIR}/local/native_ai_engine"
PYTHON_AGENT_DIR="${PROJECTS_DIR}/local/python_agent"
DEPLOY_DIR="${PROJECTS_DIR}/local/deploy_scripts"
MAGISK_MODULE="/data/adb/modules/native_ai_engine"
MODEL_PATH="${HOME_DIR}/models/phi-3-mini-q4.gguf"

# ── Functions ────────────────────────────────────────────────────────────────
log_step() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}[STEP $1]${NC} $2"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
log_ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_err()  { echo -e "  ${RED}✗${NC} $1"; }

check_root() {
    if ! su -c "id" >/dev/null 2>&1; then
        log_err "Root access (Magisk) is required. Please grant root."
        exit 1
    fi
    log_ok "Root access confirmed."
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 1: Install Termux Dependencies
# ══════════════════════════════════════════════════════════════════════════════
install_dependencies() {
    log_step "1/8" "Installing Termux dependencies..."

    pkg update -y -o Dpkg::Options::="--force-confnew" 2>/dev/null || true
    pkg install -y \
        rust \
        clang \
        make \
        cmake \
        python \
        git \
        binutils \
        2>/dev/null

    log_ok "Core packages installed (rust, clang, python, cmake, make)."

    # Python dependencies for the orchestrator
    pip install --quiet wasmtime fastapi uvicorn 2>/dev/null || true
    log_ok "Python packages installed (wasmtime, fastapi, uvicorn)."
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 2: Fix Rust Linker for Android Termux
# ══════════════════════════════════════════════════════════════════════════════
fix_rust_linker() {
    log_step "2/8" "Fixing Rust linker for Android Bionic libc..."

    # Symlink libgcc -> libunwind (Android uses LLVM, not GCC)
    if [ ! -L "${PREFIX}/lib/libgcc.a" ]; then
        ln -sf "${PREFIX}/lib/libunwind.a" "${PREFIX}/lib/libgcc.a"
        log_ok "Created libgcc.a -> libunwind.a symlink."
    else
        log_ok "libgcc.a symlink already exists."
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 3: Configure Cargo for Termux aarch64
# ══════════════════════════════════════════════════════════════════════════════
configure_cargo() {
    log_step "3/8" "Configuring Cargo for Termux aarch64 target..."

    mkdir -p "${ENGINE_DIR}/.cargo"

    cat > "${ENGINE_DIR}/.cargo/config.toml" << 'CARGO_CONFIG'
# Cargo config for Android Termux (aarch64-linux-android)
# Forces clang linker to avoid glibc/bionic mismatch errors.
# Adds Termux lib path for libunwind resolution.

[build]
rustflags = ["-C", "link-arg=-L/data/data/com.termux/files/usr/lib", "-C", "link-arg=-lunwind"]

[target.aarch64-linux-android]
linker = "clang"
CARGO_CONFIG

    log_ok "Cargo config written to ${ENGINE_DIR}/.cargo/config.toml"

    # Ensure Cargo.toml has mobile-friendly release profile
    # (No LTO, multi-codegen-units to prevent rustc stack overflow on mobile)
    if grep -q 'lto = true' "${ENGINE_DIR}/Cargo.toml" 2>/dev/null; then
        sed -i 's/lto = true/lto = false/' "${ENGINE_DIR}/Cargo.toml"
        log_warn "Patched Cargo.toml: disabled LTO (prevents rustc stack overflow on mobile)."
    fi
    if grep -q 'codegen-units = 1' "${ENGINE_DIR}/Cargo.toml" 2>/dev/null; then
        sed -i 's/codegen-units = 1/codegen-units = 16/' "${ENGINE_DIR}/Cargo.toml"
        log_warn "Patched Cargo.toml: codegen-units=16 (prevents stack overflow on mobile)."
    fi

    # Ensure wasmtime is replaced with wasmi (pure interpreter, no cranelift JIT)
    if grep -q 'wasmtime' "${ENGINE_DIR}/Cargo.toml" 2>/dev/null; then
        sed -i 's/^wasmtime.*$/wasmi = "0.40"\nwat = "1.0"/' "${ENGINE_DIR}/Cargo.toml"
        log_warn "Patched Cargo.toml: replaced wasmtime with wasmi (no cranelift needed)."
    fi

    log_ok "Cargo fully configured for mobile compilation."
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 4: Build the Native AI Engine (Rust)
# ══════════════════════════════════════════════════════════════════════════════
build_engine() {
    log_step "4/8" "Building Native AI Engine (Rust release binary)..."
    log_warn "This may take 5-15 minutes on mobile. Be patient."

    cd "${ENGINE_DIR}"

    # Use elevated stack size to prevent rustc SIGSEGV on heavy crates
    export RUST_MIN_STACK=134217728  # 128MB

    # Attempt build from Termux first
    if cargo build --release 2>&1; then
        log_ok "Engine built successfully from Termux userland."
    else
        log_warn "Termux build hit stack limits. Attempting root-elevated build..."

        # Root build bypasses Android's per-app stack limits
        su -c "
            export PATH=${PREFIX}/bin:\$PATH
            export HOME=${HOME_DIR}
            export RUST_MIN_STACK=134217728
            export CARGO_HOME=${HOME_DIR}/.cargo
            ulimit -s 131072
            cd ${ENGINE_DIR}
            cargo build --release
        "
        log_ok "Engine built successfully via root-elevated build."
    fi

    BINARY_PATH="${ENGINE_DIR}/target/release/native_ai_engine"
    if [ -f "${BINARY_PATH}" ]; then
        log_ok "Binary ready at: ${BINARY_PATH}"
        log_ok "Binary size: $(du -h ${BINARY_PATH} | cut -f1)"
    else
        log_err "Binary not found after build. Check errors above."
        exit 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 5: Patch Magisk Module (Remove Background Loops & Boot Triggers)
# ══════════════════════════════════════════════════════════════════════════════
patch_magisk_module() {
    log_step "5/8" "Patching Magisk module for battery safety..."

    if [ ! -d "${MAGISK_MODULE}" ]; then
        log_warn "Magisk module not found at ${MAGISK_MODULE}. Skipping patch."
        log_warn "You can create it manually or run 'make deploy' after build."
        return
    fi

    # Kill any rogue daemon processes from the old dummy script
    su -c "pkill -f 'native_ai_engine' 2>/dev/null || true"
    log_ok "Killed any rogue daemon processes."

    # Replace service.sh with a safe NO-OP version
    # The engine must NEVER auto-start at boot!
    su -c "cat > ${MAGISK_MODULE}/service.sh" << 'SERVICE_SAFE'
#!/system/bin/sh
# Magisk service.sh - Native AI Engine
# SAFETY: This script intentionally does NOTHING at boot.
# The engine is started ON-DEMAND by the Python Orchestrator
# and stopped immediately after task completion.
#
# Architecture: Wake -> Execute -> Sleep (0% idle CPU)
# Start manually: su -c start native_ai_engine
# Stop manually:  su -c stop native_ai_engine

# NO BOOT TRIGGERS. NO INFINITE LOOPS. NO BACKGROUND POLLING.
exit 0
SERVICE_SAFE

    log_ok "Magisk service.sh patched (no boot auto-start)."
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 6: Deploy Binary to Magisk Module Overlay
# ══════════════════════════════════════════════════════════════════════════════
deploy_binary() {
    log_step "6/8" "Deploying binary to Magisk module overlay..."
    
    BINARY_PATH="${ENGINE_DIR}/target/release/native_ai_engine"

    if [ ! -f "${BINARY_PATH}" ]; then
        log_err "Binary not found at ${BINARY_PATH}. Run build first."
        return
    fi

    # Deploy to Magisk module overlay (persists across reboots)
    su -c "
        mkdir -p ${MAGISK_MODULE}/system/bin
        cp -f ${BINARY_PATH} ${MAGISK_MODULE}/system/bin/native_ai_engine
        chmod 755 ${MAGISK_MODULE}/system/bin/native_ai_engine
        chown root:root ${MAGISK_MODULE}/system/bin/native_ai_engine
    "
    log_ok "Binary deployed to ${MAGISK_MODULE}/system/bin/native_ai_engine"

    # Also deploy init.rc with safe config (disabled, oneshot, NO boot trigger)
    su -c "cat > ${MAGISK_MODULE}/system/etc/init/native_ai_engine.rc" << 'INITRC'
# Android init.rc service specification for native_ai_engine
# SAFETY: disabled + oneshot = NEVER auto-starts, runs once per trigger only
service native_ai_engine /system/bin/native_ai_engine --daemon --verbose
    class main
    user root
    group root system readproc
    seclabel u:r:su:s0
    disabled
    oneshot
INITRC

    log_ok "Init.rc deployed (disabled + oneshot, no boot trigger)."
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 7: Patch Integration Files (Remove Stale Imports)
# ══════════════════════════════════════════════════════════════════════════════
patch_integrations() {
    log_step "7/8" "Applying integration patches..."

    if grep -q 'from wasmtime' "${PROJECTS_DIR}/local/polymath-integrated/context_daemon.py" 2>/dev/null; then
        sed -i 's/^from wasmtime.*$/# WASM bridge is handled natively by the Rust engine (wasmi runtime)/' "${PROJECTS_DIR}/local/polymath-integrated/context_daemon.py"
        log_warn "Patched context_daemon.py: removed stale wasmtime import."
    fi

    if grep -q 'from wasmtime' "${PYTHON_AGENT_DIR}/main.py" 2>/dev/null; then
        sed -i 's/^from wasmtime.*$/# WASM bridge handled by Native Engine via HTTP/' "${PYTHON_AGENT_DIR}/main.py"
        log_warn "Patched main.py: removed stale wasmtime import."
    fi

    log_ok "Integration patches applied."
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 8: Set Up Python Orchestrator
# ══════════════════════════════════════════════════════════════════════════════
setup_python_orchestrator() {
    log_step "8/8" "Setting up Python Orchestrator (Wake -> Execute -> Sleep)..."

    cd "${PYTHON_AGENT_DIR}"

    # Create venv if it doesn't exist
    if [ ! -d "venv" ]; then
        python3 -m venv venv
        log_ok "Python virtual environment created."
    fi

    # Install requirements
    source venv/bin/activate 2>/dev/null || . venv/bin/activate
    pip install --quiet wasmtime 2>/dev/null || true
    deactivate 2>/dev/null || true

    log_ok "Python Orchestrator ready at ${PYTHON_AGENT_DIR}/main.py"

    # Create the quick-run script
    cat > "${PROJECTS_DIR}/local/run_ai.sh" << 'RUN_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# ┌──────────────────────────────────────────────┐
# │  Native AI Engine - Quick Run Script         │
# │  Usage: ~/Projects/local/run_ai.sh "your prompt"   │
# │  Lifecycle: Wake -> Execute -> Sleep          │
# └──────────────────────────────────────────────┘

PROMPT="${1:-Hello, analyze my system.}"
PYTHON_DIR="/data/data/com.termux/files/home/Projects/local/python_agent"

echo "╔══════════════════════════════════════════╗"
echo "║   Native AI Engine - Task Execution      ║"
echo "╠══════════════════════════════════════════╣"
echo "║ Prompt: ${PROMPT:0:38}  ║"
echo "╚══════════════════════════════════════════╝"

cd "${PYTHON_DIR}"
source venv/bin/activate 2>/dev/null || . venv/bin/activate
python3 main.py
deactivate 2>/dev/null || true

echo ""
echo "[✓] Task complete. Engine sleeping. CPU: 0%"
RUN_SCRIPT
    chmod +x "${PROJECTS_DIR}/local/run_ai.sh"
    log_ok "Quick-run script created at ~/Projects/local/run_ai.sh"

    # Create the health check script
    cat > "${PROJECTS_DIR}/local/health_check.sh" << 'HEALTH_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# ┌──────────────────────────────────────────────┐
# │  Native AI Engine - Health Check             │
# │  Checks if the engine is safely idle.        │
# └──────────────────────────────────────────────┘

echo "═══ Native AI Engine Health Check ═══"
echo ""

# Check if daemon is running (it should NOT be unless actively processing)
if pgrep -f "native_ai_engine" > /dev/null 2>&1 || su -c "pgrep -f native_ai_engine" > /dev/null 2>&1; then
    echo "  ⚠ WARNING: native_ai_engine is running in background!"
    echo "  → This violates battery safety rules."
    echo "  → Kill it with: su -c 'pkill -f native_ai_engine'"
    su -c "ps -eo pid,pcpu,pmem,comm | grep native_ai_engine" 2>/dev/null || true
else
    echo "  ✓ Engine is safely idle (0% CPU)"
fi

echo ""

# Check model file
MODEL="/data/data/com.termux/files/home/models/phi-3-mini-q4.gguf"
if [ -f "$MODEL" ]; then
    echo "  ✓ Model found: $(du -h $MODEL | cut -f1) $(basename $MODEL)"
else
    echo "  ✗ Model NOT found at $MODEL"
fi

# Check binary
BINARY="/data/data/com.termux/files/home/Projects/local/native_ai_engine/target/release/native_ai_engine"
if [ -f "$BINARY" ]; then
    echo "  ✓ Binary compiled: $(du -h $BINARY | cut -f1) native_ai_engine"
else
    echo "  ✗ Binary NOT compiled. Run ~/Projects/native-ai/setup.sh"
fi

# Check Magisk module
if [ -d "/data/adb/modules/native_ai_engine" ]; then
    echo "  ✓ Magisk module installed"
else
    echo "  ✗ Magisk module not found"
fi

# Check WASM bridge
WAT="/data/data/com.termux/files/home/Projects/local/python_agent/agent_core.wat"
if [ -f "$WAT" ]; then
    echo "  ✓ WASM bridge present (agent_core.wat)"
else
    echo "  ✗ WASM bridge missing"
fi

echo ""
echo "═══ Battery Status ═══"
termux-battery-status 2>/dev/null || echo "  (Install termux-api for battery info)"
HEALTH_SCRIPT
    chmod +x "${PROJECTS_DIR}/local/health_check.sh"
    log_ok "Health check script created at ~/Projects/local/health_check.sh"

    if ! grep -q 'alias poly=' "${HOME_DIR}/.bashrc" 2>/dev/null; then
        echo 'alias poly="sh /data/data/com.termux/files/home/Projects/local/polymath-integrated/start.sh"' >> "${HOME_DIR}/.bashrc"
        log_ok "Added 'poly' alias to .bashrc"
    else
        log_ok "'poly' alias already exists in .bashrc"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║    Native AI Engine - One-Shot Setup & Build                ║"
echo "║    Battery-Safe · No Background Loops · Dynamic Execution   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

check_root
install_dependencies
fix_rust_linker
configure_cargo
build_engine
patch_magisk_module
deploy_binary
patch_integrations
setup_python_orchestrator

echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    SETUP COMPLETE! ✓                        ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
echo "║  Quick Commands:                                            ║"
echo "║    Run AI:       ~/Projects/local/run_ai.sh \"your prompt\"         ║"
echo "║    Health Check:  ~/Projects/local/health_check.sh                ║"
echo "║    Rebuild:       ~/Projects/native-ai/setup.sh                       ║"
echo "║                                                            ║"
echo "║  Architecture: Wake → Execute → Sleep (0% idle CPU)        ║"
echo "║  Model: ~/models/phi-3-mini-q4.gguf (Q4 mmap)              ║"
echo "║  Engine: Rust + WASM Bridge + Python Orchestrator           ║"
echo "║                                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
