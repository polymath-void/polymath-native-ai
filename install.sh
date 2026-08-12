#!/data/data/com.termux/files/usr/bin/bash

# Native AI Engine - One-Shot Installer
# Designed for Termux + Magisk

echo "========================================="
echo "  Native AI Engine - One-Shot Installer  "
echo "========================================="

# 1. Check for Root (Magisk)
if ! su -c "echo 'Root access granted'"; then
    echo "[!] Error: Root access is required to deploy the Magisk daemon."
    exit 1
fi

# 2. Install Termux Dependencies
echo "[*] Installing Termux dependencies (git, python, llama-cpp)..."
pkg update -y
pkg install -y git python llama-cpp

# 3. Install Python Dependencies
echo "[*] Installing Python dependencies (prompt_toolkit, rich)..."
pip install prompt_toolkit rich

# 4. Clone Repository
REPO_DIR="$HOME/Projects/polymath-native-ai"
if [ ! -d "$REPO_DIR" ]; then
    echo "[*] Cloning Native AI repository..."
    mkdir -p "$HOME/Projects"
    # Replace URL with actual GitHub repository when published
    git clone https://github.com/polymath-void/polymath-native-ai.git "$REPO_DIR"
else
    echo "[*] Repository already exists at $REPO_DIR. Pulling latest..."
    cd "$REPO_DIR" && git pull
fi

cd "$REPO_DIR"

# 5. Model Configuration
echo ""
echo "[?] Please enter the absolute path to your .gguf model file"
echo "    (Example: /data/data/com.termux/files/home/models/phi-3-mini-q4.gguf):"
read -r MODEL_PATH

if [ ! -f "$MODEL_PATH" ]; then
    echo "[!] Warning: File $MODEL_PATH not found. Make sure to download it before starting."
fi

# Create config.env
echo "[*] Generating config.env..."
cat <<EOF > config.env
# Configuration for Native AI Engine
MODEL_PATH=$MODEL_PATH
PORT=57160
THREADS=4
CONTEXT_SIZE=2048
TEMPERATURE=0.6
AUTH_TOKEN=admin123
EOF

# 6. Magisk Module Deployment
echo "[*] Deploying native_ai_engine Magisk module..."

su -c "mkdir -p /data/adb/modules/native_ai_engine/system/bin"

# Create module.prop
su -c "cat <<EOF > /data/adb/modules/native_ai_engine/module.prop
id=native_ai_engine
name=Native AI Engine
version=v2.0
versionCode=2
author=Polymath
description=Bare-metal Termux Llama-Server backend daemon
EOF"

# Deploy binary
su -c "cp $REPO_DIR/native_ai_engine/native_ai_engine.sh /data/adb/modules/native_ai_engine/system/bin/native_ai_engine"
su -c "chmod +x /data/adb/modules/native_ai_engine/system/bin/native_ai_engine"

echo "========================================="
echo "[+] Installation Complete!"
echo "========================================="
echo "The Magisk daemon script has been deployed."
echo "If this is your first time installing, you MUST reboot your device so Android init can register the service."
echo ""
echo "After reboot, start the agent by running:"
echo "  cd ~/Projects/polymath-native-ai"
echo "  python3 python_agent/tui.py"
echo ""
echo "Default Auth Token: admin123"
echo "========================================="
