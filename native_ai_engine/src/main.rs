// mod wasm_host;
mod server;
mod ai_runner;

use std::sync::{Arc, Mutex};
use log::{info, error};

fn main() -> anyhow::Result<()> {
    env_logger::init();
    info!("Starting Native AI Engine...");

    let model_path = "/data/data/com.termux/files/home/models/phi-3-mini-q4.gguf";
    
    let runner = match ai_runner::AiRunner::new(model_path) {
        Ok(r) => Arc::new(r),
        Err(e) => {
            error!("Failed to initialize AI Runner: {}", e);
            return Err(e);
        }
    };

    ctrlc::set_handler(move || {
        info!("Received Ctrl-C, shutting down Native AI Engine.");
        std::process::exit(0);
    }).expect("Error setting Ctrl-C handler");

    info!("AI Engine initialized. Starting HTTP server.");
    server::run_server(runner)?;

    Ok(())
}
