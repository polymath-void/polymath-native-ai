# Project Context

- **Goal:** Build a production-grade native aarch64 binary.
- **Technology:** Rust, tokio.
- **Current Status:** Recursive Swarm Architecture with Validation Gateway implemented.
- **Architecture:** Single binary, no bloated interpreters.
- **Dependencies:** 
  - `tokio` (runtime)
  - `reqwest` (HTTP)
  - `serde`/`serde_json` (serialization)
  - `dotenvy` (config)
  - `rusqlite` (persistent storage)
  - `scraper` (HTML parsing)
  - `rss` (RSS parsing)
  - `ignore` (file system traversal)
- **Dependencies:** IPC broker integration (VoidTerm).
- **Tooling:** Dynamic Tool Factory (~/.polymath_agent/tools/)
- **Orchestration:** Recursive Swarm Delegation Router (Master -> Sub-Agent -> Micro-Agent) with programmatic Validation Gateway.
- **Cognition:** Skill Adapting Architecture via `learn_skill` and persistent SQLite storage.
- **Environment:** Context Ingestion Engine (Web, RSS, Workspace, Git).
- **Boot Deployment:** Magisk OverlayFS deployment script at `deploy_polymath.sh` configuring boot auto-start for Polymath-Void Agent (`/system/bin/polymath_void_agent`) on `sys.boot_completed=1` while maintaining `native_ai_engine` in a sleeping/disabled state for strict on-demand Wake-Sleep orchestration.


