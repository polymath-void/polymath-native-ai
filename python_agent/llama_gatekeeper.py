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

def load_config():
    config_path = "/data/data/com.termux/files/home/Projects/polymath-native-ai/config.env"
    port = "57160"
    temperature = 0.6
    try:
        with open(config_path, "r") as f:
            for line in f:
                if line.startswith("PORT="):
                    port = line.strip().split("=")[1]
                elif line.startswith("TEMPERATURE="):
                    temperature = float(line.strip().split("=")[1])
    except Exception:
        pass
    return f"http://127.0.0.1:{port}", temperature

ENGINE_URL, ENGINE_TEMP = load_config()

def wake_daemon():
    try:
        # Try native Android init first (works after reboot)
        subprocess.run(DAEMON_START_CMD, check=True, capture_output=True)
    except Exception:
        pass

    # Verify if the engine actually started and wait for model load
    for _ in range(30):
        try:
            req = urllib.request.Request(f"{ENGINE_URL}/health", method='GET')
            with urllib.request.urlopen(req, timeout=1) as resp:
                if resp.status == 200:
                    return # Server is ready!
        except urllib.error.HTTPError as e:
            if e.code == 503:
                # 503 means model is still loading
                time.sleep(1)
                continue
        except Exception:
            # Not reachable yet, try starting it directly if init failed
            subprocess.Popen(
                ["su", "-c", "/data/adb/modules/native_ai_engine/system/bin/native_ai_engine"],
                stdout=subprocess.DEVNULL, 
                stderr=subprocess.DEVNULL
            )
            time.sleep(1)

def sleep_daemon():
    # llama-server doesn't have a shutdown endpoint, just stop the service
    subprocess.run(DAEMON_STOP_CMD, capture_output=True)

def execute_query(prompt, context=""):
    system_prompt = (
        "You are a deeply reasoning AI. Always analyze the user's request step-by-step "
        "and wrap your inner monologue inside <thought>...</thought> tags before generating the final answer."
    )
    full_prompt = f"<|system|>\n{system_prompt}<|end|>\n{context}<|user|>\n{prompt}<|end|>\n<|assistant|>\n"
    payload = json.dumps({"prompt": full_prompt, "n_predict": 1024, "temperature": ENGINE_TEMP}).encode('utf-8')
    req = urllib.request.Request(
        f"{ENGINE_URL}/v1/completions",
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if "choices" in data and len(data["choices"]) > 0:
                text = data["choices"][0]["text"].strip()
                
                # Extract metrics
                usage = data.get("usage", {})
                timings = data.get("timings", {})
                total_tokens = usage.get("total_tokens", 0)
                tps = timings.get("predicted_per_second", 0.0)
                
                metrics = f"\n\n--- \n*⚡ Tokens: {total_tokens} | Speed: {tps:.2f} t/s*"
                return text + metrics
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
    
    start_time = time.time()
    
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
