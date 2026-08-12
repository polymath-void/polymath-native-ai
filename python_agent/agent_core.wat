(module
  (import "env" "host_log" (func $host_log (param i32 i32)))
  (memory (export "memory") 1)

  ;; Define static offsets
  (func $get_prompt_offset (result i32) (i32.const 1024))
  (export "get_prompt_offset" (func $get_prompt_offset))

  (func $get_response_offset (result i32) (i32.const 4096))
  (export "get_response_offset" (func $get_response_offset))

  ;; Mock process_prompt: Trigger the AI processing
  ;; In a real Magisk overlay, this WASM function uses host callbacks or shared memory atomics
  ;; to alert the C++ engine that a prompt is ready at `prompt_offset`.
  ;; Here, we just return a success code.
  (func $process_prompt (param $prompt_len i32) (result i32)
    ;; Call host_log to notify Python that prompt is received
    (call $host_log (i32.const 1024) (local.get $prompt_len))
    (i32.const 1) ;; Return success
  )
  (export "process_prompt" (func $process_prompt))
)
