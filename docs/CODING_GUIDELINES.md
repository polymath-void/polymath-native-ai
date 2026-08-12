# Code Generation Guidelines

When writing or reviewing code, strictly adhere to the following principles:

## 1. Modular and Maintainable
- Write small, single-purpose functions.
- Keep the `native_ai_engine` ecosystem clean: Logic goes in Python, heavy lifting goes in C++/Rust, and instructions go in Markdown.

## 2. Error Handling is Mandatory
- Never assume a command or API call will succeed. 
- Use `try/except` blocks in Python.
- Provide clean, human-readable error messages (e.g., `[Gatekeeper Network Error]`) instead of raw stack traces.

## 3. Formatting
- Provide code in clean Markdown blocks.
- When modifying an existing file, only provide the changes (diffs) or explicitly state where the new code should be injected, unless the file is very short.

## 4. Termux & Android Specifics
- Python paths should default to `#!/usr/bin/env python3`.
- Daemons running as root (`su`) do NOT have access to the Termux `PREFIX` environment variables by default. Any shell script running as root must explicitly export `PREFIX` and `LD_LIBRARY_PATH`.
