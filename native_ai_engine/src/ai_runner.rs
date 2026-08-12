pub struct AiRunner {}

impl AiRunner {
    pub fn new(_model_path: &str) -> anyhow::Result<Self> { Ok(Self {}) }
    pub fn generate(&self, prompt: &str) -> anyhow::Result<String> { Ok("Hello from Llama Gatekeeper!".to_string()) }
}
