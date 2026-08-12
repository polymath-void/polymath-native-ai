# Native AI Architecture

A custom, bare-metal AI engine designed to bypass high-level Android virtualization, running a local Llama model via Termux and Magisk.

## Project Structure
- `native_ai_engine/`: The core Magisk daemon script (`native_ai_engine.sh`) that spawns the highly optimized `llama-server` in the background.
- `python_agent/`: The Orchestrator layer. Includes `tui.py` (frontend) and `llama_gatekeeper.py` (model router).
- `docs/`: Markdown-based rules, skills, and behavior instructions that define the agent's identity.
- `config.env`: Global configuration file (model path, ports, thread limits).

## Features
- **Deep Reasoning**: The agent is prompted to use internal `<thought>` tags before outputting a final answer.
- **Offline First**: Fully self-contained, no external API dependencies.
- **Hardware Optimized**: Uses Termux's pre-compiled C/C++ `llama-server` to maximize ARM64 NEON performance on the Dimensity chip.

## Setup
1. Adjust `config.env` to point to your local `.gguf` model.
2. Deploy the `native_ai_engine` via Magisk.
3. Run `python3 python_agent/tui.py` to start chatting!
