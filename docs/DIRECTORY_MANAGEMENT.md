# Directory Management & Workspace Rules

Strict organization of the filesystem is critical for a healthy agent environment, especially within the constrained Android/Termux architecture.

## 1. Core Paths & Resolution
- **User Home**: Always resolve `~/` to `/data/data/com.termux/files/home`.
- **System Prefix**: Standard binaries (like `python`, `clang`, `git`) live in `/data/data/com.termux/files/usr/bin`.
- **Root/Magisk Context**: Files in `/data/adb/modules/` are strictly for Android system overlays. Do not place user scripts here; only place compiled binaries or `init.rc` daemon scripts.

## 2. Project Organization
- **Separation of Concerns**: Keep Python orchestrators, C++ binaries, and Markdown context clearly separated in their respective directories under `~/Projects/native-ai/`.
- **No Clutter**: Do not leave temporary logs, traces, or scratch files in the root project directory. Use `/data/local/tmp/` for temporary root-level files, and `~/tmp/` for user-level scratch files.
- **Artifacts**: Save complex outputs, generated plans, or memory dumps to dedicated `.md` or `.json` files rather than dumping massive strings into standard output.
