use wasmi::*;

/// Lightweight WASM host using wasmi (pure interpreter).
/// Embedded directly into Polymath-Void-Agent for offline, rootless model execution.
pub struct WasmHost {
    store: Store<HostState>,
    instance: Instance,
    memory: Memory,
}

/// Host state shared with WASM imports
struct HostState;

impl WasmHost {
    pub fn new(wasm_path: &str) -> anyhow::Result<Self> {
        let engine = Engine::default();

        // Read the .wat or .wasm file
        let wasm_bytes = if wasm_path.ends_with(".wat") {
            let wat_source = std::fs::read_to_string(wasm_path)?;
            wat::parse_str(&wat_source)
                .map_err(|e| anyhow::anyhow!("WAT parse error: {}", e))?
        } else {
            std::fs::read(wasm_path)?
        };

        let module = Module::new(&engine, &wasm_bytes[..])?;

        let mut store = Store::new(&engine, HostState);
        let mut linker = Linker::<HostState>::new(&engine);

        // Register host_log callback: executes the native offline AI model
        linker.func_wrap(
            "env",
            "host_log",
            |mut caller: Caller<'_, HostState>, ptr: i32, len: i32| {
                let mem = match caller.get_export("memory") {
                    Some(Extern::Memory(mem)) => mem,
                    _ => return,
                };
                
                let mut prompt_bytes = vec![0u8; len as usize];
                if mem.read(&caller, ptr as usize, &mut prompt_bytes).is_err() {
                    return;
                }
                
                let prompt_str = match std::str::from_utf8(&prompt_bytes) {
                    Ok(s) => s,
                    Err(_) => return,
                };

                // Delegate the heavy execution to the Swarm Playground (which bypasses PhantomProcessKiller)
                let payload = format!(r#"{{"prompt": "{}"}}"#, prompt_str.escape_default());
                let output = std::process::Command::new("curl")
                    .arg("-s")
                    .arg("-X")
                    .arg("POST")
                    .arg("-H")
                    .arg("Content-Type: application/json")
                    .arg("-d")
                    .arg(&payload)
                    .arg("http://127.0.0.1:5000/api/infer_sync")
                    .output();

                let mut response_text = match output {
                    Ok(out) => {
                        let stdout_str = String::from_utf8_lossy(&out.stdout);
                        // Parse JSON response from the API
                        match serde_json::from_str::<serde_json::Value>(&stdout_str) {
                            Ok(json_res) => {
                                if let Some(res_str) = json_res.get("result").and_then(|r| r.as_str()) {
                                    let clean_lines: Vec<&str> = res_str.lines()
                                        .filter(|line| !line.starts_with("["))
                                        .collect();
                                    clean_lines.join("\n")
                                } else if let Some(err_str) = json_res.get("error").and_then(|e| e.as_str()) {
                                    format!("[Swarm Playground Error]: {}", err_str)
                                } else {
                                    format!("[Invalid JSON Response]: {}", stdout_str)
                                }
                            }
                            Err(_) => format!("[Execution Error - Bad JSON]: {}", stdout_str),
                        }
                    }
                    Err(e) => format!("[Request Error]: {}", e),
                };
                
                if response_text.is_empty() {
                    response_text = format!("Local Model Echo: {}", prompt_str);
                }

                let response_json = serde_json::json!({
                    "candidates": [
                        {
                            "content": {
                                "parts": [
                                    { "text": response_text }
                                ]
                            }
                        }
                    ]
                });
                let response_json_str = response_json.to_string();

                // Write response to address 4096 (get_response_offset)
                let resp_ptr = 4096;
                let resp_bytes = response_json_str.as_bytes();
                let _ = mem.write(&mut caller, resp_ptr, resp_bytes);
                let _ = mem.write(&mut caller, resp_ptr + resp_bytes.len(), &[0]);
            },
        )?;

        let instance = linker
            .instantiate(&mut store, &module)?
            .start(&mut store)?;

        let memory = instance
            .get_memory(&store, "memory")
            .ok_or_else(|| anyhow::anyhow!("memory export not found"))?;

        Ok(Self {
            store,
            instance,
            memory,
        })
    }

    pub fn process_prompt(&mut self, prompt: &str) -> anyhow::Result<String> {
        // Get function exports
        let get_prompt_offset = self
            .instance
            .get_typed_func::<(), i32>(&self.store, "get_prompt_offset")?;
        let get_response_offset = self
            .instance
            .get_typed_func::<(), i32>(&self.store, "get_response_offset")?;
        let process_prompt_fn = self
            .instance
            .get_typed_func::<i32, i32>(&self.store, "process_prompt")?;

        // Write prompt into WASM shared memory
        let prompt_ptr = get_prompt_offset.call(&mut self.store, ())? as usize;
        let prompt_bytes = prompt.as_bytes();
        self.memory
            .write(&mut self.store, prompt_ptr, prompt_bytes)?;
        self.memory
            .write(&mut self.store, prompt_ptr + prompt_bytes.len(), &[0])?;

        // Execute the WASM process_prompt function
        let _result = process_prompt_fn.call(&mut self.store, prompt_bytes.len() as i32)?;

        // Read response from WASM shared memory
        let resp_ptr = get_response_offset.call(&mut self.store, ())? as usize;
        let mem_data = self.memory.data(&self.store);

        let mut len = 0;
        while resp_ptr + len < mem_data.len() && mem_data[resp_ptr + len] != 0 {
            len += 1;
        }

        let resp_bytes = &mem_data[resp_ptr..resp_ptr + len];
        let resp_str = std::str::from_utf8(resp_bytes)?.to_string();

        Ok(resp_str)
    }
}
