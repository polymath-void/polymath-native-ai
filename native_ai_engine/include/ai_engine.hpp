#ifndef NATIVE_AI_ENGINE_AI_ENGINE_HPP
#define NATIVE_AI_ENGINE_AI_ENGINE_HPP

#include "tensor.hpp"
#include "model_loader.hpp"
#include <string>
#include <vector>
#include <functional>
#include <memory>
#include <atomic>

namespace ai_engine {

struct EngineConfig {
    std::string model_path = "";
    size_t num_threads = 4;
    size_t max_tokens = 128;
    float temperature = 0.7f;
    float top_p = 0.9f;
    bool daemon_mode = false;
    bool verbose = false;
    std::string ipc_socket_path = "/dev/socket/native_ai_engine.sock";
};

using TokenCallback = std::function<void(const std::string& token)>;

class AIEngine {
public:
    explicit AIEngine(const EngineConfig& config);
    ~AIEngine();

    bool initialize();
    bool load_model(const std::string& model_path);

    // Run inference on raw prompt and emit tokens
    void generate(const std::string& prompt, TokenCallback callback = nullptr);

    // Daemon execution mode for system service
    int run_daemon_service();

    // Signal trigger for system shutdown
    void stop_daemon();

    const EngineConfig& config() const { return config_; }

private:
    EngineConfig config_;
    std::unique_ptr<RawModel> model_;
    std::atomic<bool> running_{false};

    // Low-level SIMD Matrix Vector Multiplication (NEON / Fallback)
    void matmul_fp32(const float* A, const float* B, float* C, size_t M, size_t N, size_t K);

    // Dummy forward pass for scaffold baseline
    std::vector<float> forward_pass(const std::vector<int32_t>& input_tokens);

    void log_info(const std::string& msg);
    void log_error(const std::string& msg);
};

} // namespace ai_engine

#endif // NATIVE_AI_ENGINE_AI_ENGINE_HPP
