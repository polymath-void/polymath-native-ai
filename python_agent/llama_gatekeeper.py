#!/usr/bin/env python3
"""
Standalone Llama Gatekeeper
Fully independent AI runner module. Does not require Antigravity (agy).
Routes queries to the native AI engine and enforces Wake->Execute->Sleep.
"""
import sys
import json
import time
import urllib.request
import urllib.error
import subprocess

DAEMON_START_CMD = ["su", "-c", "start native_ai_engine"]
DAEMON_STOP_CMD = ["su", "-c", "stop native_ai_engine"]
ENGINE_URL = "http://127.0.0.1:57160"

def wake_daemon():
    try:
        # Try native Android init first (works after reboot)
        subprocess.run(DAEMON_START_CMD, check=True, capture_output=True)
        time.sleep(0.5) 
    except Exception:
        pass

    # Verify if the engine actually started by checking the health endpoint
    try:
        req = urllib.request.Request(f"{ENGINE_URL}/health", method='GET')
        urllib.request.urlopen(req, timeout=1)
    except Exception:
        # If it failed (likely because no reboot after Magisk install), run binary directly
        subprocess.Popen(
            ["su", "-c", "/data/adb/modules/native_ai_engine/system/bin/native_ai_engine"],
            stdout=subprocess.DEVNULL, 
            stderr=subprocess.DEVNULL
        )
        time.sleep(1.5) # Give it an extra second to load the model and bind socket

def sleep_daemon():
    try:
        # Graceful sleep payload
        req = urllib.request.Request(
            f"{ENGINE_URL}/shutdown",
            data=b'SHUTDOWN_SOCKET',
            method='POST'
        )
        urllib.request.urlopen(req, timeout=3)
    except Exception:
        pass
    finally:
        # Hard stop via init
        subprocess.run(DAEMON_STOP_CMD, capture_output=True)

def execute_query(prompt, context=""):
    payload = json.dumps({"prompt": prompt, "context": context}).encode('utf-8')
    req = urllib.request.Request(
        f"{ENGINE_URL}/llama_gatekeeper",
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if "response" in data:
                return data["response"]
            elif "error" in data:
                return f"[Gatekeeper Backend Error] {data['error']}"
    except urllib.error.URLError as e:
        return f"[Gatekeeper Network Error] Failed to reach native engine: {e}"
    except Exception as e:
        return f"[Gatekeeper System Error] Unexpected failure: {e}"

def main():
    if len(sys.argv) < 2:
        print("Usage: llama_gatekeeper \"Your prompt here\"")
        print("Optional: llama_gatekeeper \"Your prompt\" \"System context or memory\"")
        sys.exit(1)
        
    prompt = sys.argv[1]
    context = sys.argv[2] if len(sys.argv) > 2 else ""
    
    # 1. Enforce strict Wake lifecycle
    wake_daemon()
    
    try:
        # 2. Execute routing natively
        response = execute_query(prompt, context)
        print(response)
    finally:
        # 3. Enforce strict Sleep lifecycle
        sleep_daemon()

if __name__ == "__main__":
    main()
