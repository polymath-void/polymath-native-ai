#!/usr/bin/env python3
import os
import json
import sqlite3
import time
import getpass
import re
from typing import List, Dict
from prompt_toolkit import PromptSession
from prompt_toolkit.history import FileHistory
from prompt_toolkit.styles import Style

# Ensure the saved_chats directory exists so we can save memories
import os
os.makedirs("/data/data/com.termux/files/home/Projects/polymath-native-ai/saved_chats", exist_ok=True)
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
            with open("/data/data/com.termux/files/home/Projects/polymath-native-ai/config.env", "r") as f:
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
            gatekeeper_path = "/data/data/com.termux/files/home/Projects/polymath-native-ai/python_agent/llama_gatekeeper.py"
            result = subprocess.run(
                ["python3", gatekeeper_path, prompt, context_str],
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
            password = getpass.getpass("Enter Auth Token: ")
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
                start_time = time.time()
                with self.console.status("[bold cyan]Agent is thinking...", spinner="dots"):
                    response = self._query_llama_gatekeeper(user_input, context)
                total_time = time.time() - start_time
                
                # Add total time to the footer if the gatekeeper returned metrics
                if "*⚡ Tokens:" in response:
                    response = response.replace("*⚡", f"*⏱️ {total_time:.1f}s | ⚡")
                
                # Store response
                self.memory.add_message("assistant", response)
                
                # Print response nicely formatted
                self.console.print()
                self.console.rule("[bold magenta]Agent[/bold magenta]")
                
                # Split and format <thought> tags with ASCII colors
                parts = re.split(r'(<thought>.*?</thought>)', response, flags=re.DOTALL)
                for part in parts:
                    if not part.strip():
                        continue
                    if part.startswith("<thought>"):
                        thought_text = part.replace("<thought>", "").replace("</thought>", "").strip()
                        self.console.print(f"[dim cyan]💭 {thought_text}[/dim cyan]\n")
                    else:
                        self.console.print(Markdown(part.strip()))
                        self.console.print()
                        
                self.console.rule(style="magenta")
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
            if not skill_name or skill_name.lower() == "list":
                docs_dir = "/data/data/com.termux/files/home/Projects/polymath-native-ai/docs"
                try:
                    skills = [f[:-3] for f in os.listdir(docs_dir) if f.endswith(".md")]
                except Exception:
                    skills = []
                
                if not skills:
                    self.console.print("[red]No skills found in docs/ directory.[/red]")
                    return
                
                self.console.print("[cyan]Available Skills:[/cyan]")
                for i, s in enumerate(skills):
                    self.console.print(f"  [bold yellow]{i+1}[/bold yellow]: {s}")
                
                try:
                    choice = self.session.prompt("Select a skill number (or press enter to cancel): ")
                    if not choice.strip():
                        return
                    choice_idx = int(choice.strip()) - 1
                    if 0 <= choice_idx < len(skills):
                        skill_name = skills[choice_idx]
                    else:
                        self.console.print("[red]Invalid selection.[/red]")
                        return
                except ValueError:
                    self.console.print("[red]Invalid input. Please enter a number.[/red]")
                    return
                except KeyboardInterrupt:
                    return

            path = f"/data/data/com.termux/files/home/Projects/polymath-native-ai/docs/{skill_name}.md"
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
                result = subprocess.run(f"git -C /data/data/com.termux/files/home/Projects/polymath-native-ai {args}", shell=True, capture_output=True, text=True)
                output = f"Git Output:\n{result.stdout}\n{result.stderr}".strip()
                self.console.print(f"[cyan]{output}[/cyan]")
                self.memory.add_message("user", f"[SYSTEM: GIT COMMAND RAN: git {args}]\n{output}")
            except Exception as e:
                self.console.print(f"[red]Git command failed: {e}[/red]")
        
        elif command == "/save":
            filename = args.strip()
            if not filename:
                self.console.print("[yellow]Usage: /save <filename> (e.g., /save my_project_chat)[/yellow]")
                return
            
            # Fetch the current conversation memory
            history = self.memory.get_history(limit=500)
            if not history:
                self.console.print("[yellow]Memory is empty, nothing to save.[/yellow]")
                return
                
            save_dir = "/data/data/com.termux/files/home/Projects/polymath-native-ai/saved_chats"
            os.makedirs(save_dir, exist_ok=True)
            
            # Ensure it ends with .md
            if not filename.endswith(".md"):
                filename += ".md"
            filepath = os.path.join(save_dir, filename)
            
            try:
                with open(filepath, "w") as f:
                    f.write(f"# Saved Memory Log: {filename}\n\n")
                    for msg in history:
                        f.write(f"**{msg['role'].upper()}**: {msg['content']}\n\n")
                self.console.print(f"[green]Memory successfully backed up to saved_chats/{filename}[/green]")
            except Exception as e:
                self.console.print(f"[red]Failed to save memory:[/red] {e}")

        elif command == "/config":
            self.console.print(f"[cyan]Current Config:[/cyan]\n{json.dumps(self.config, indent=2)}")
        else:
            self.console.print(f"[red]Unknown command: {command}[/red]")

if __name__ == "__main__":
    tui = AgentTUI()
    tui.run()
