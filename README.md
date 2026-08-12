# Polymath Native AI

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Termux-brightgreen)
![Status](https://img.shields.io/badge/status-Audited%20%26%20Active-success)

A custom, bare-metal AI engine and terminal user interface (TUI) designed to bypass high-level Android virtualization. It runs a local Llama model via Termux and deploys the engine as a native background daemon via Magisk. 

This architecture guarantees maximum ARM64 NEON performance (specifically tailored for Dimensity and Snapdragon chips) by memory-mapping the GGUF model directly via `llama-server`.

---

## ⚡ Features

- **Hardware Optimized**: Uses Termux's pre-compiled C/C++ `llama-server` to keep CPU footprint minimal during idle times.
- **Deep Reasoning**: The agent natively uses `<thought>` tags for chain-of-thought analysis in a single engine pass, preventing infinite Python loops.
- **Offline First**: Fully self-contained. No external API dependencies.
- **Whole Brain Memory**: Interactive TUI remembers your session and routes complex context arrays directly into the Llama backend.
- **Dynamic Skills & Git Understanding**: Built-in slash commands let you dynamically load logic schemas or pipe Git statuses directly into the AI's context window.
- **Secure**: TUI is protected by local authentication to prevent unauthorized terminal injection.

---

## 🚀 Installation (One-Shot)

The easiest way to install and configure the entire environment on your rooted device is via our automated installation script. 

### Prerequisites
1. An **Android device with Root (Magisk)**.
2. **Termux** installed.
3. A downloaded `.gguf` LLM model stored somewhere on your device.

### One-Command Setup
Open Termux and run the following command. It will install all dependencies, clone this repository, prompt you for your model's location, and install the daemon into Magisk automatically:

```bash
curl -sL https://raw.githubusercontent.com/polymath-void/polymath-native-ai/main/install.sh | bash
```

*Note: After the script completes, you **must reboot** your device so the Android `init` system can register the new background Magisk daemon.*

---

## 💻 Usage & Configuration

Once installed and your device is rebooted, you can launch the TUI orchestrator from Termux:

```bash
cd ~/Projects/polymath-native-ai
python3 python_agent/tui.py
```

*Default Auth Token:* `admin123` (You will be prompted for this on launch).

### Global Configuration (`config.env`)
You can tweak the AI's behavior without altering any code. Edit `config.env` in the root folder to change:
- `MODEL_PATH`: Absolute path to your `.gguf` model.
- `TEMPERATURE`: How creative the model is (default `0.6`).
- `AUTH_TOKEN`: Your TUI password.
- `THREADS`: Number of CPU threads (default `4`).

### TUI Slash Commands
While inside the chat interface, type these commands to trigger advanced orchestration logic:

| Command | Example | Description |
|---|---|---|
| `/skill <name>` | `/skill SYSTEM_PROMPT` | Loads a Markdown skill file from `docs/` and secretly injects it into the AI's memory. |
| `/git <command>` | `/git status` | Executes the Git command and appends the terminal output directly into the agent's context. |
| `/config` | `/config` | Dumps the active configuration settings to your screen. |
| `clear` | `clear` | Erases the active conversation memory and unloads all skills. |
| `exit` | `exit` | Closes the TUI. |

---

## 🔒 Security Audit & Citations
**Status: Audited**

This architecture strictly enforces the **Wake -> Execute -> Sleep** protocol.
- The `native_ai_engine.sh` daemon is managed solely by Magisk and the Termux root binary layer.
- Python orchestrator logic (`llama_gatekeeper.py`) contains NO autonomous endless loops, preventing device thermal throttling and battery drain. 
- All Deep Reasoning is delegated directly to the `llama-server` C-ABI, bypassing high-overhead Python processing entirely. 

*Designed and maintained by Polymath Void.*
