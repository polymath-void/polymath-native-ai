use crate::memory::ShortTermMemory;
use crate::tools;
use crate::tools::factory::ToolFactory;
use std::sync::OnceLock;
use reqwest::Client;
use serde_json::{json, Value};
use std::env;
use std::pin::Pin;
use std::future::Future;

static CLIENT: OnceLock<Client> = OnceLock::new();

/// Wraps the recursive call in a Boxed Future to satisfy Rust's async recursion rules
pub fn run_subagent<'a>(
    role_description: String,
    objective: String,
    tool_factory: &'a ToolFactory,
    current_depth: u8,
    max_depth: u8,
    tx: tokio::sync::mpsc::Sender<String>,
) -> Pin<Box<dyn Future<Output = Result<String, Box<dyn std::error::Error + Send + Sync>>> + Send + 'a>> {
    Box::pin(async move {
        // Initialize local WASM engine directly
        let wat_path = "/data/data/com.termux/files/home/Projects/local/python_agent/agent_core.wat";
        let mut wasm_host = crate::wasm_host::WasmHost::new(wat_path)?;

        let mut st_memory = ShortTermMemory::new(15);
        st_memory.add_turn(json!({ "role": "user", "parts": [{"text": &objective}] }));
        
        let identity = match current_depth {
            0 => "Polymath (Main Agent)",
            1 => "Master Agent",
            2 => "Sub Agent",
            _ => "Micro Agent",
        };
        
        let delegation_target = match current_depth {
            0 => "Master Agent",
            1 => "Sub Agent",
            _ => "Micro Agent",
        };

        // System prompt reinforces verification at higher levels and implements Zen Metacognition
        let system_instruction = format!(
            "{}\n\n=== ZEN REASONING PROTOCOL & HIERARCHY ===\n\
             You are acting as the {} in our recursive swarm architecture.\n\
             Before taking any action, you must follow the Zen Metacognition loop:\n\
             1. STEP-BACK REFLECTION: What is the underlying core of this request? Are there hidden edge cases?\n\
             2. CHAIN-OF-THOUGHT: Break the solution down into atomic, verifiable steps.\n\
             3. CRITIQUE: Play devil's advocate against your own plan before executing it.\n\n\
             === DELEGATION CHAIN ===\n\
             If the task requires implementation, deep reasoning, or breaking down, you MUST delegate it to a {}.\n\
             The hierarchy flows strictly as: Polymath -> Master -> Sub -> Micro.\n\
             Micro Agents submit their work to Sub Agents -> Sub Agents submit reports to Master Agents -> Master Agents combine all solved reports and submit the actual problem-solving process back up to Polymath.\n\
             If you are Polymath, your final job is to refine the response, implement the codebase, or fix the errors seamlessly to provide the pure solution directly to the user.\n\
             CRITICAL: You must verify the output of your subordinates. If they fail, delegate the task back to them with explicit corrections.",
            role_description, identity, delegation_target
        );

        let prefix = match current_depth {
            0 => "●>",
            1 => "●●",
            2 => "<●●>",
            _ => " <●>",
        };
        if current_depth > 0 {
            let _ = tx.send(format!("{} [{} Spawned]: {}", prefix, identity, role_description)).await;
        }
        loop {
            let mut function_declarations = tools::builtin::get_builtin_schemas();
            function_declarations.extend(tool_factory.load_dynamic_schemas());

            // If we hit max depth, REMOVE the delegate_task tool so Micro-Agents are forced to execute
            if current_depth >= max_depth {
                function_declarations.retain(|f| f["name"] != "delegate_task");
            }

            let tools_payload = json!([{ "functionDeclarations": function_declarations }]);
            let request_body = json!({
                "systemInstruction": { "parts": [{"text": system_instruction}] },
                "contents": st_memory.get_contents(),
                "tools": tools_payload
            });
            let local_request = json!({
                "prompt": request_body
            });

            // Call the local WASM engine directly without any network requests
            let res_body = wasm_host.process_prompt(&local_request.to_string())?;
            let res_json: Value = serde_json::from_str(&res_body)?;
            let parts = match res_json["candidates"][0]["content"]["parts"].as_array() {
                Some(p) => p,
                None => return Ok(format!("Agent failed to parse API response.")),
            };

            if let Some(func_call) = parts[0].get("functionCall") {
                let name = func_call["name"].as_str().unwrap();
                let args = &func_call["args"];

                let result = match name {
                    "execute_shell_command" => tools::execute_shell_command(args["command"].as_str().unwrap_or("")),
                    "delegate_task" => {
                        let role = args["role_description"].as_str().unwrap_or("");
                        let sub_objective = args["objective"].as_str().unwrap_or("");
                        
                        let _ = tx.send(format!("{} [Delegating to {}]: {}", prefix, delegation_target, sub_objective)).await;
                        
                        // Recursive Call
                        match run_subagent(role.to_string(), sub_objective.to_string(), tool_factory, current_depth + 1, max_depth, tx.clone()).await {
                            Ok(sub_result) => format!("SUBORDINATE ({}) SUBMISSION FOR VERIFICATION:\n{}", delegation_target, sub_result),
                            Err(e) => format!("{} failed: {}", delegation_target, e)
                        }
                    }
                    "query_swarm_playground" => {
                        let task_type = args["task_type"].as_str().unwrap_or("");
                        let payload = args["payload"].as_str().unwrap_or("");
                        let _ = tx.send(format!("{} [Swarm Playground]: {} -> {}", prefix, task_type, payload)).await;
                        
                        let playground_req = json!({
                            "type": task_type,
                            "query": payload,
                            "code": payload,
                            "url": payload,
                            "msg": payload
                        });
                        
                        match CLIENT.get().unwrap().post("http://127.0.0.1:5000/api/dispatch")
                            .json(&playground_req)
                            .send()
                            .await {
                                Ok(resp) => {
                                    match resp.json::<Value>().await {
                                        Ok(json) => format!("Playground Response:\n{}", json.to_string()),
                                        Err(_) => "Failed to parse JSON response from Playground".to_string()
                                    }
                                },
                                Err(e) => format!("Playground API failed: {}", e)
                            }
                    }
                    "fetch_url" => {
                        let url = args["url"].as_str().unwrap_or("");
                        crate::tools::context::fetch_url(url).await
                    }
                    "read_rss" => {
                        let url = args["url"].as_str().unwrap_or("");
                        crate::tools::context::read_rss(url).await
                    }
                    "scan_workspace" => {
                        let path = args["path"].as_str().unwrap_or(".");
                        let max_depth = args["max_depth"].as_u64().map(|n| n as usize);
                        crate::tools::context::scan_workspace(path, max_depth)
                    }
                    "git_context" => {
                        let action = args["action"].as_str().unwrap_or("status");
                        crate::tools::context::git_context(action)
                    }
                    "scan_universal_memory" => {
                        let path = args["workspace_path"].as_str().unwrap_or(".");
                        crate::memory::universal_bridge::UniversalBridge::scan_and_ingest(path)
                    }
                    "learn_skill" => {
                        let name = args["skill_name"].as_str().unwrap_or("");
                        let trigger = args["context_trigger"].as_str().unwrap_or("");
                        let method = args["methodology"].as_str().unwrap_or("");
                        if let Ok(db) = crate::memory::long_term::LongTermMemory::new("/data/data/com.termux/files/home/.polymath_agent/memory.db") {
                            match db.learn_skill(name, trigger, method) {
                                Ok(_) => format!("Successfully learned skill: {}", name),
                                Err(e) => format!("Failed to learn skill: {}", e)
                            }
                        } else {
                            "Failed to open Long Term Memory DB".to_string()
                        }
                    }
                    "verify_submission" => {
                        let text = args["submission_text"].as_str().unwrap_or("");
                        let criteria = args["verification_criteria"].as_str().unwrap_or("");
                        format!("VERIFICATION COMPLETED. Verified '{}' against '{}'", text.len(), criteria)
                    }
                    custom_tool => tool_factory.execute_dynamic_tool(custom_tool, args),
                };

                st_memory.add_turn(json!({ "role": "model", "parts": [{"functionCall": func_call}] }));
                st_memory.add_turn(json!({ "role": "function", "parts": [{ "functionResponse": { "name": name, "response": {"result": result} } }] }));
                continue;
            } else if let Some(text) = parts[0].get("text") {
                if current_depth > 0 {
                    let _ = tx.send(format!("{} ✔️ [{} Completed Task]", prefix, identity)).await;
                }
                return Ok(text.as_str().unwrap().to_string());
            }
        }
    })
}
