use wasmi::*;
use log::info;

/// Lightweight WASM host using wasmi (pure interpreter).
/// No JIT compilation needed — compiles and runs on mobile ARM64.
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

        // Register host_log import: logs a string from WASM shared memory
        linker.func_wrap(
            "env",
            "host_log",
            |caller: Caller<'_, HostState>, ptr: i32, len: i32| {
                let mem = match caller.get_export("memory") {
                    Some(Extern::Memory(mem)) => mem,
                    _ => return,
                };
                let data = mem.data(&caller);
                if let Some(slice) = data.get(ptr as usize..(ptr + len) as usize) {
                    if let Ok(s) = std::str::from_utf8(slice) {
                        info!("WASM Log: {}", s);
                    }
                }
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
        let alloc_buffer = self
            .instance
            .get_typed_func::<i32, i32>(&self.store, "alloc_buffer")?;
        let dealloc_buffer = self
            .instance
            .get_typed_func::<(i32, i32), ()>(&self.store, "dealloc_buffer")?;
        let process_message = self
            .instance
            .get_typed_func::<(i32, i32), i32>(&self.store, "process_message")?;
        let free_bridge_response = self
            .instance
            .get_typed_func::<i32, ()>(&self.store, "free_bridge_response")?;

        let prompt_bytes = prompt.as_bytes();
        let prompt_len = prompt_bytes.len() as i32;

        // Allocate memory for prompt in WASM
        let prompt_ptr = alloc_buffer.call(&mut self.store, prompt_len)?;
        if prompt_ptr == 0 && prompt_len > 0 {
            return Err(anyhow::anyhow!("Failed to allocate WASM buffer"));
        }

        // Write prompt into WASM shared memory
        self.memory
            .write(&mut self.store, prompt_ptr as usize, prompt_bytes)?;

        // Execute the WASM process_message function
        let resp_ptr = process_message.call(&mut self.store, (prompt_ptr, prompt_len))?;

        // Read BridgeResponse from WASM memory (16 bytes: ptr, len, capacity, status)
        let mem_data = self.memory.data(&self.store);
        let resp_offset = resp_ptr as usize;
        
        if resp_offset + 16 > mem_data.len() {
            return Err(anyhow::anyhow!("Invalid BridgeResponse pointer out of bounds"));
        }

        let resp_buf = &mem_data[resp_offset..resp_offset + 16];
        let mut ptr_bytes = [0u8; 4]; ptr_bytes.copy_from_slice(&resp_buf[0..4]);
        let out_ptr = u32::from_le_bytes(ptr_bytes) as usize;
        
        let mut len_bytes = [0u8; 4]; len_bytes.copy_from_slice(&resp_buf[4..8]);
        let out_len = u32::from_le_bytes(len_bytes) as usize;
        
        let mut cap_bytes = [0u8; 4]; cap_bytes.copy_from_slice(&resp_buf[8..12]);
        let _out_cap = u32::from_le_bytes(cap_bytes) as usize;
        
        let mut status_bytes = [0u8; 4]; status_bytes.copy_from_slice(&resp_buf[12..16]);
        let status = u32::from_le_bytes(status_bytes);

        let result = if status != 0 {
            Err(anyhow::anyhow!("WASM returned error status: {}", status))
        } else {
            if out_ptr + out_len > mem_data.len() {
                Err(anyhow::anyhow!("Response string out of bounds"))
            } else {
                let resp_bytes = &mem_data[out_ptr..out_ptr + out_len];
                let resp_str = std::str::from_utf8(resp_bytes)?.to_string();
                Ok(resp_str)
            }
        };

        // Free the structures in WASM
        free_bridge_response.call(&mut self.store, resp_ptr)?;
        dealloc_buffer.call(&mut self.store, (prompt_ptr, prompt_len))?;

        result
    }
}
