#!/usr/bin/env python3
import os
import json
import sqlite3
import time
from typing import List, Dict
from prompt_toolkit import PromptSession
from prompt_toolkit.history import FileHistory
from prompt_toolkit.styles import Style
from rich.console import Console
from rich.markdown import Markdown
from rich.panel import Panel

# Memory Management System ("Whole Brain Memory")
class MemoryManager:
    def __init__(self, db_path="memory.db"):
        self.db_path = db_path
        self._init_db()

    def _init_db(self):
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS conversation (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    timestamp REAL NOT NULL
                )
            ''')
            conn.commit()

    def add_message(self, role: str, content: str):
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                'INSERT INTO conversation (role, content, timestamp) VALUES (?, ?, ?)',
                (role, content, time.time())
            )
            conn.commit()

    def get_history(self, limit: int = 50) -> List[Dict]:
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                'SELECT role, content FROM conversation ORDER BY timestamp DESC LIMIT ?',
                (limit,)
            )
            rows = cursor.fetchall()
            return [{"role": r[0], "content": r[1]} for r in reversed(rows)]

    def clear(self):
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('DELETE FROM conversation')
            conn.commit()

# TUI Frontend
class AgentTUI:
    def __init__(self):
        self.console = Console()
        self.memory = MemoryManager()
        self.style = Style.from_dict({
            'prompt': 'ansicyan bold',
        })
        self.session = PromptSession(
            history=FileHistory('.agent_history'),
            style=self.style
        )
        self.gatekeeper_url = "http://127.0.0.1:57160/llama_gatekeeper"
        self._load_config()
        self.active_skills = []

    def _load_config(self):
        self.config = {}
        try:
            with open("/data/data/com.termux/files/home/Projects/native-ai/config.env", "r") as f:
                for line in f:
                    if "=" in line:
                        k, v = line.strip().split("=", 1)
                        self.config[k] = v
        except Exception:
            pass

    def _query_llama_gatekeeper(self, prompt: str, context: List[Dict]) -> str:
        """
        Routes the query to the local LLM binary via the standalone llama_gatekeeper CLI.
        Includes full conversational history ("whole brain memory").
        """
        import subprocess
        
        # Format the context into a single string for the backend
        context_str = ""
        for msg in context:
            if msg['role'] == 'user':
                context_str += f"<|user|>\n{msg['content']}<|end|>\n"
            else:
                context_str += f"<|assistant|>\n{msg['content']}<|end|>\n"
                
        try:
            result = subprocess.run(
                ["llama_gatekeeper", prompt, context_str],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                return f"[Gatekeeper CLI Error] {result.stderr}\n{result.stdout}"
            return result.stdout.strip()
        except Exception as e:
            return f"[System Error calling Gatekeeper: {str(e)}]"

    def run(self):
        # Auth check
        auth_token = self.config.get("AUTH_TOKEN")
        if auth_token:
            password = self.session.prompt("Enter Auth Token: ", is_password=True)
            if password != auth_token:
                self.console.print("[red]Authentication failed.[/red]")
                return

        self.console.print(Panel.fit(
            "[bold green]Agent Frontend Initialized[/bold green]\n"
            "Connected to local LLM binary via llama_gatekeeper.\n"
            "Slash commands available: /skill <name>, /git <command>, /config\n"
            "Type 'exit' to quit, 'clear' to erase memory.",
            title="Carbon Copy Agent TUI",
            border_style="green"
        ))
        
        while True:
            try:
                user_input = self.session.prompt("User> ")
                
                if not user_input.strip():
                    continue
                    
                if user_input.lower() in ['exit', 'quit']:
                    self.console.print("[yellow]Shutting down TUI...[/yellow]")
                    break
                    
                if user_input.lower() == 'clear':
                    self.memory.clear()
                    self.active_skills.clear()
                    self.console.print("[yellow]Whole brain memory and active skills cleared.[/yellow]")
                    continue

                if user_input.startswith("/"):
                    self._handle_slash_command(user_input)
                    continue

                # Add to memory
                self.memory.add_message("user", user_input)
                
                # Retrieve context ("whole brain memory")
                context = self.memory.get_history(limit=50)
                
                # Show spinner while thinking
                with self.console.status("[bold cyan]Agent is thinking...", spinner="dots"):
                    response = self._query_llama_gatekeeper(user_input, context)
                
                # Store response
                self.memory.add_message("assistant", response)
                
                # Print response nicely formatted
                self.console.print()
                self.console.print(Panel(
                    Markdown(response),
                    title="[bold magenta]Agent[/bold magenta]",
                    border_style="magenta",
                    expand=False
                ))
                self.console.print()

            except KeyboardInterrupt:
                self.console.print("[yellow]Use 'exit' to quit.[/yellow]")
                continue
            except EOFError:
                break
            except Exception as e:
                self.console.print(f"[red]Error:[/red] {str(e)}")

    def _handle_slash_command(self, cmd: str):
        parts = cmd.split(" ", 1)
        command = parts[0].lower()
        args = parts[1] if len(parts) > 1 else ""

        if command == "/skill":
            skill_name = args.strip()
            if not skill_name:
                self.console.print("[yellow]Usage: /skill <name> (e.g., SYSTEM_PROMPT)[/yellow]")
                return
            path = f"/data/data/com.termux/files/home/Projects/native-ai/docs/{skill_name}.md"
            if not os.path.exists(path):
                self.console.print(f"[red]Skill file {skill_name}.md not found in docs/.[/red]")
                return
            with open(path, "r") as f:
                content = f.read()
            self.memory.add_message("user", f"[SYSTEM: SKILL LOADED: {skill_name}]\n{content}")
            self.active_skills.append(skill_name)
            self.console.print(f"[green]Skill '{skill_name}' successfully injected into memory context.[/green]")

        elif command == "/git":
            if not args:
                self.console.print("[yellow]Usage: /git <command> (e.g., status)[/yellow]")
                return
            import subprocess
            try:
                result = subprocess.run(f"git -C /data/data/com.termux/files/home/Projects/native-ai {args}", shell=True, capture_output=True, text=True)
                output = f"Git Output:\n{result.stdout}\n{result.stderr}".strip()
                self.console.print(f"[cyan]{output}[/cyan]")
                self.memory.add_message("user", f"[SYSTEM: GIT COMMAND RAN: git {args}]\n{output}")
            except Exception as e:
                self.console.print(f"[red]Git command failed: {e}[/red]")
        
        elif command == "/config":
            self.console.print(f"[cyan]Current Config:[/cyan]\n{json.dumps(self.config, indent=2)}")
        else:
            self.console.print(f"[red]Unknown command: {command}[/red]")

if __name__ == "__main__":
    tui = AgentTUI()
    tui.run()
