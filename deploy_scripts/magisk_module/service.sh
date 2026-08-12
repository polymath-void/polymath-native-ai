#!/system/bin/sh
# Magisk late_start service script
MODDIR=${0%/*}

# Wait until boot completes to start the heavy engine safely
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 3
done

# Start the native AI engine daemon in the background
nohup ${MODDIR}/system/bin/native_ai_engine > /dev/null 2>&1 &
