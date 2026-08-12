import json
import threading
import sys
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
try:
    from llama_cpp import Llama
except ImportError:
    Llama = None

MODEL_PATH = "/data/data/com.termux/files/home/models/phi-3-mini-q4.gguf"
PORT = 57160

# Global state
llm = None
server = None

class GatekeeperHandler(BaseHTTPRequestHandler):
    def _send_response(self, status, payload):
        self.send_response(status)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(payload).encode('utf-8'))

    def do_GET(self):
        if self.path == '/health':
            self._send_response(200, {"status": "ok"})
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/shutdown':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')
            if post_data == 'SHUTDOWN_SOCKET':
                self._send_response(200, {"status": "shutting down"})
                print("Shutdown command received. Stopping server...")
                threading.Thread(target=server.shutdown, daemon=True).start()
            else:
                self._send_response(400, {"error": "Invalid shutdown payload"})
                
        elif self.path == '/llama_gatekeeper':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')
            try:
                data = json.loads(post_data)
                prompt = data.get("prompt", "")
                context = data.get("context", "")
                
                if llm is None:
                    self._send_response(500, {"error": "LLM not initialized"})
                    return
                
                # Format for Phi-3
                full_prompt = f"{context}<|user|>\n{prompt}<|end|>\n<|assistant|>\n"
                
                print(f"Generating response for prompt: {prompt[:50]}...")
                output = llm(
                    full_prompt,
                    max_tokens=512,
                    stop=["<|user|>", "<|end|>"],
                    echo=False
                )
                
                response_text = output['choices'][0]['text'].strip()
                self._send_response(200, {"response": response_text})
                
            except Exception as e:
                self._send_response(500, {"error": str(e)})
        else:
            self.send_response(404)
            self.end_headers()

def run_server():
    global llm, server
    
    print(f"Loading model from {MODEL_PATH}...")
    if not os.path.exists(MODEL_PATH):
        print(f"ERROR: Model file not found at {MODEL_PATH}")
        sys.exit(1)
        
    if Llama is None:
        print("ERROR: llama_cpp module not found. Are you running the compiled binary?")
        sys.exit(1)
        
    try:
        # Initialize with reasonable defaults for mobile
        llm = Llama(
            model_path=MODEL_PATH, 
            n_ctx=2048, 
            n_threads=4,
            verbose=False
        )
        print("Model loaded successfully.")
    except Exception as e:
        print(f"Failed to load model: {e}")
        sys.exit(1)

    server_address = ('127.0.0.1', PORT)
    server = HTTPServer(server_address, GatekeeperHandler)
    print(f"Starting native AI engine on http://127.0.0.1:{PORT}")
    server.serve_forever()
    print("Server stopped.")

if __name__ == '__main__':
    run_server()
