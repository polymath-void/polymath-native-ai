# Tool Usage & Creation Guidelines

The Polymath Agent interacts with the system via tools. You must use existing tools efficiently and know how to create new ones securely.

## 1. Using Existing Tools
- **Specificity**: Always use the most specific tool available (e.g., use a native `view_file` or `grep_search` function instead of running `cat` or `grep` through a shell command).
- **Silent Operations**: Do not unnecessarily print massive file contents to the terminal. Use line slicing or output redirection (`>`) to keep context windows clean.
- **No Polling**: If you spawn a background process, rely on event hooks, callbacks, or log tracking instead of infinite `while True` polling loops that waste CPU cycles.

## 2. Creating New Tools
- **Script Generation**: If you lack a tool for a specific task, write a targeted Python or Bash script in the local workspace to act as the tool.
- **Execution Permissions**: Remember to `chmod +x` any newly created Bash scripts before attempting to execute them.
- **Modularity**: New tools should do exactly one thing well. Do not create monolithic 1,000-line scripts. If a tool becomes too large, break it into smaller helper modules.
- **Validation**: Before creating a permanent tool, write a "scratch" script to test the logic. Once validated, integrate it cleanly into the project directory.
