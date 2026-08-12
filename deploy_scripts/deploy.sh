#!/system/bin/sh
# Root-Level Deployment Script for Android Daemon Services
# Location: ~/Projects/local/deploy_scripts/deploy.sh
# Usage: su -c ./deploy.sh [path_to_binary]

set -e

# Configuration
BINARY_SRC="${1:-./dummy_daemon}"
BINARY_NAME="$(basename "${BINARY_SRC}")"
TARGET_BIN_DIR="/system/bin"
TARGET_INIT_DIR="/system/etc/init"
SERVICE_NAME="${BINARY_NAME%.*}"
SERVICE_RC="${TARGET_INIT_DIR}/${SERVICE_NAME}.rc"

echo "=================================================="
echo " Starting Root-Level Daemon Deployment"
echo "=================================================="

# Check root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Error: This script must be executed as root (uid 0)." >&2
    echo "    Please run with: su -c $0 $@" >&2
    exit 1
fi

# Ensure source binary exists
if [ ! -f "${BINARY_SRC}" ]; then
    echo "[!] Warning: Source binary '${BINARY_SRC}' not found."
    echo "[+] Generating placeholder dummy binary for testing..."
    cat << 'EOF' > "${BINARY_SRC}"
#!/system/bin/sh
# Dummy Daemon Executable
echo "[dummy_daemon] Daemon started at $(date)"
# NO INFINITE LOOPS! Dynamic execution only.
echo "[dummy_daemon] Executing payload natively and shutting down."
exit 0
EOF
    chmod 755 "${BINARY_SRC}"
fi

# Step 1: Remount /system as RW
echo "[+] Step 1: Remounting /system as read-write (rw)..."
if mount -o remount,rw /system 2>/dev/null; then
    echo "    Successfully remounted /system as rw."
elif mount -o remount,rw / 2>/dev/null; then
    echo "    Successfully remounted / (rootfs) as rw."
else
    echo "    Attempting generic remount command..."
    mount -o rw,remount /system || mount -o rw,remount / || {
        echo "[!] Error: Failed to remount /system as read-write." >&2
        exit 1
    }
fi

# Step 2: Copy binary to /system/bin
echo "[+] Step 2: Copying binary to ${TARGET_BIN_DIR}/${BINARY_NAME}..."
cp -f "${BINARY_SRC}" "${TARGET_BIN_DIR}/${BINARY_NAME}"
chmod 755 "${TARGET_BIN_DIR}/${BINARY_NAME}"
chown root:root "${TARGET_BIN_DIR}/${BINARY_NAME}" 2>/dev/null || true
echo "    Binary installed: ${TARGET_BIN_DIR}/${BINARY_NAME}"

# Step 3: Set up dummy init.rc service file
echo "[+] Step 3: Creating init.rc service file at ${SERVICE_RC}..."
mkdir -p "${TARGET_INIT_DIR}" 2>/dev/null || true
cat << EOF > "${SERVICE_RC}"
# Android init.rc service file for ${SERVICE_NAME}
# Location: ${SERVICE_RC}

service ${SERVICE_NAME} ${TARGET_BIN_DIR}/${BINARY_NAME}
    class main
    user root
    group root
    seclabel u:r:su:s0
    disabled
    oneshot

EOF

chmod 644 "${SERVICE_RC}"
chown root:root "${SERVICE_RC}" 2>/dev/null || true
echo "    Service definition created: ${SERVICE_RC}"

# Step 4: Remount /system back to RO
echo "[+] Step 4: Remounting /system back to read-only (ro)..."
if mount -o remount,ro /system 2>/dev/null; then
    echo "    Successfully remounted /system as ro."
elif mount -o remount,ro / 2>/dev/null; then
    echo "    Successfully remounted / (rootfs) as ro."
else
    echo "[!] Warning: Could not explicitly remount /system as ro."
fi

echo "=================================================="
echo " Deployment Complete!"
echo " Service Name: ${SERVICE_NAME}"
echo " Executable:   ${TARGET_BIN_DIR}/${BINARY_NAME}"
echo " Init Config:  ${SERVICE_RC}"
echo ""
echo " Management Commands:"
echo "   Start:  su -c start ${SERVICE_NAME}"
echo "   Stop:   su -c stop ${SERVICE_NAME}"
echo "=================================================="
