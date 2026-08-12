# Local Llama Native Architecture - v1.0 (Finalized)

## System Architecture

The native AI architecture has been fully decoupled from the cloud and hard-wired to run strictly locally on the Android device (Nothing Phone - Dimensity 7200). The initial attempt to build a `wasm32-unknown-unknown` bridge was formally abandoned due to missing compilation targets in Termux. 

The architecture has pivoted to a purely native HTTP JSON bridge.

### Core Components:
1. **The Engine (`native_ai_engine`)**
   - **Role:** The C++/Rust Magisk Overlay Daemon.
   - **Function:** Maps the `phi-3-mini-q4.gguf` model directly into hardware memory via zero-copy mmap. It natively parses JSON `AgentQuery` payloads and structures them into `<|system|>`/`<|user|>`/`<|assistant|>` context blocks.
   - **Safety:** Enforces a 30-second hard idle timeout and mandates the `SHUTDOWN_SOCKET` payload on the `/shutdown` endpoint to prevent thermal throttling.

2. **The Gatekeeper (`python_agent/llama_gatekeeper.py`)**
   - **Role:** Standalone Global Executable (`~/bin/llama_gatekeeper`).
   - **Function:** Acts as the impenetrable lifecycle broker. 
   - **Safety Gate:** Uses a strict `try...finally` block. 
     - *Wake:* Executes `su -c start native_ai_engine`. If Android `init` isn't ready, safely falls back to launching the binary manually.
     - *Execute:* POSTs the prompt and context to the engine's `/llama_gatekeeper` endpoint.
     - *Sleep:* Guarantees the `SHUTDOWN_SOCKET` payload is sent and issues `su -c stop native_ai_engine`.

3. **The Carbon Copy TUI (`python_agent/tui.py`)**
   - **Role:** Interactive Frontend Terminal UI.
   - **Function:** Manages "Whole Brain Memory" using a local SQLite database (`memory.db`). It intercepts user prompts, fetches past context from the database, formats it into a single context string, and executes the `llama_gatekeeper` CLI seamlessly.

## Deployment Status
- Magisk Module deployed to `/data/adb/modules/native_ai_engine/system/bin/native_ai_engine`.
- Standalone runner deployed globally to `~/bin/llama_gatekeeper`.
- Old `wasm_bridge` and legacy attempt folders have been permanently purged.

## Maintenance Notes
- **Reboot Required:** For maximum Wake/Sleep efficiency, a system reboot is required to lock the engine into the Android `init` sequence.
- **Future Updates:** All updates to the local AI logic should be routed exclusively through the `llama_gatekeeper` CLI or the `native_ai_engine` Rust server.
