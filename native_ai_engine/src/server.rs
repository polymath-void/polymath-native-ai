use tiny_http::{Server, Response, Method, Header};
use serde::{Deserialize, Serialize};
use serde_json::json;
use log::{info, error};
use std::sync::{Arc, Mutex};
#[allow(unused_imports)]
use std::io::Read;
// use crate::wasm_host::WasmHost;
use crate::ai_runner::AiRunner;

#[derive(Deserialize)]
struct AgentQuery {
    prompt: String,
    context: Option<String>,
}

pub fn run_server(runner: Arc<AiRunner>) -> anyhow::Result<()> {
    let server = Server::http("127.0.0.1:57160").map_err(|e| anyhow::anyhow!("{}", e))?;
    info!("Server listening on 127.0.0.1:57160");

    for mut request in server.incoming_requests() {
        match (request.method(), request.url()) {
            (&Method::Get, "/health") => {
                let response = Response::from_string(json!({"status": "ok"}).to_string())
                    .with_header(Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap());
                let _ = request.respond(response);
            }
            (&Method::Post, "/shutdown") => {
                let mut content = String::new();
                if request.as_reader().read_to_string(&mut content).is_ok() && content == "SHUTDOWN_SOCKET" {
                    info!("Shutdown requested. Exiting.");
                    let _ = request.respond(Response::from_string(json!({"status": "shutting down"}).to_string())
                        .with_header(Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap()));
                    std::process::exit(0);
                } else {
                    let _ = request.respond(Response::from_string("Invalid payload").with_status_code(400));
                }
            }
            (&Method::Post, "/llama_gatekeeper") | (&Method::Post, "/") => {
                let mut content = String::new();
                request.as_reader().read_to_string(&mut content)?;

                info!("Received request: {}", content);
                
                // Parse the JSON
                let query: AgentQuery = match serde_json::from_str(&content) {
                    Ok(q) => q,
                    Err(e) => {
                        error!("Invalid JSON: {}", e);
                        let _ = request.respond(Response::from_string(json!({"error": "Invalid JSON payload"}).to_string()).with_status_code(400));
                        continue;
                    }
                };

                let mut formatted_prompt = String::new();
                if let Some(ctx) = query.context {
                    if !ctx.is_empty() {
                        formatted_prompt.push_str(&format!("<|system|>\n{}<|end|>\n", ctx));
                    }
                }
                formatted_prompt.push_str(&format!("<|user|>\n{}<|end|>\n<|assistant|>\n", query.prompt));

                let response_str = match runner.generate(&formatted_prompt) {
                    Ok(resp) => json!({"response": resp}).to_string(),
                    Err(e) => {
                        error!("Error generating response: {}", e);
                        json!({"error": e.to_string()}).to_string()
                    }
                };

                let response = Response::from_string(response_str)
                    .with_header(Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap());
                
                if let Err(e) = request.respond(response) {
                    error!("Error sending response: {}", e);
                }
            }
            _ => {
                let _ = request.respond(Response::from_string("Method Not Allowed").with_status_code(405));
            }
        }
    }
    Ok(())
}
