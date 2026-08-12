#include "ai_engine.hpp"
#include <iostream>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <chrono>
#include <thread>
#include <poll.h>

namespace ai_engine {

AIEngine::AIEngine(const EngineConfig& config) : config_(config) {
}

AIEngine::~AIEngine() {
    stop_daemon();
}

bool AIEngine::initialize() {
    return true;
}

bool AIEngine::load_model(const std::string& model_path) {
    model_ = std::make_unique<RawModel>(model_path);
    return model_->is_valid();
}

void AIEngine::generate(const std::string& prompt, TokenCallback callback) {
    if (callback) {
        callback("Dummy");
        callback(" response");
        callback(" for");
        callback(" ");
        callback(prompt);
    }
}

int AIEngine::run_daemon_service() {
    running_ = true;
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) return -1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, config_.ipc_socket_path.c_str(), sizeof(addr.sun_path) - 1);
    unlink(config_.ipc_socket_path.c_str());

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) return -1;
    if (listen(server_fd, 5) < 0) return -1;

    log_info("Daemon listening on " + config_.ipc_socket_path);

    struct pollfd pfd;
    pfd.fd = server_fd;
    pfd.events = POLLIN;

    auto last_active = std::chrono::steady_clock::now();
    const int IDLE_TIMEOUT_MS = 30000; // 30 seconds Wake->Sleep timeout

    while (running_) {
        int ret = poll(&pfd, 1, 1000); // 1 second timeout
        if (ret > 0) {
            if (pfd.revents & POLLIN) {
                int client_fd = accept(server_fd, nullptr, nullptr);
                if (client_fd >= 0) {
                    last_active = std::chrono::steady_clock::now();
                    char buf[1024];
                    ssize_t n = read(client_fd, buf, sizeof(buf) - 1);
                    if (n > 0) {
                        buf[n] = '\0';
                        std::string prompt(buf);
                        std::string response = "Mock generated response";
                        write(client_fd, response.c_str(), response.size());
                    }
                    close(client_fd);
                }
            }
        }

        auto now = std::chrono::steady_clock::now();
        if (std::chrono::duration_cast<std::chrono::milliseconds>(now - last_active).count() > IDLE_TIMEOUT_MS) {
            log_info("Idle timeout reached. Entering sleep (terminating to prevent thermal throttling).");
            running_ = false;
        }
    }

    close(server_fd);
    unlink(config_.ipc_socket_path.c_str());
    return 0;
}

void AIEngine::stop_daemon() {
    running_ = false;
}

void AIEngine::matmul_fp32(const float* A, const float* B, float* C, size_t M, size_t N, size_t K) {
    // Scaffold implementation
    for (size_t i = 0; i < M; ++i) {
        for (size_t j = 0; j < N; ++j) {
            float sum = 0;
            for (size_t k = 0; k < K; ++k) {
                sum += A[i * K + k] * B[k * N + j];
            }
            C[i * N + j] = sum;
        }
    }
}

std::vector<float> AIEngine::forward_pass(const std::vector<int32_t>& input_tokens) {
    return std::vector<float>(config_.max_tokens, 0.0f);
}

void AIEngine::log_info(const std::string& msg) {
    std::cout << "[INFO] " << msg << std::endl;
}

void AIEngine::log_error(const std::string& msg) {
    std::cerr << "[ERROR] " << msg << std::endl;
}

} // namespace ai_engine
