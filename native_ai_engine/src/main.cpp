#include "ai_engine.hpp"
#include <iostream>
#include <cstring>
#include <csignal>

using namespace ai_engine;

AIEngine* g_engine = nullptr;

void signal_handler(int signum) {
    if (g_engine) {
        g_engine->stop_daemon();
    }
}

int main(int argc, char** argv) {
    EngineConfig config;
    config.model_path = "/data/data/com.termux/files/home/models/phi-3-mini-q4.gguf";

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--daemon") == 0) {
            config.daemon_mode = true;
        } else if (strcmp(argv[i], "--test") == 0) {
            std::cout << "Test mode running." << std::endl;
            return 0;
        }
    }

    AIEngine engine(config);
    g_engine = &engine;
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    if (!engine.initialize()) {
        std::cerr << "Failed to initialize engine." << std::endl;
        return 1;
    }

    if (config.daemon_mode) {
        std::cout << "Starting daemon..." << std::endl;
        return engine.run_daemon_service();
    } else {
        std::cout << "Loading model..." << std::endl;
        if (!engine.load_model(config.model_path)) {
            std::cerr << "Failed to load model: " << config.model_path << std::endl;
            return 1;
        }
        std::cout << "Generating test output..." << std::endl;
        engine.generate("Test prompt", [](const std::string& t){ std::cout << t; });
        std::cout << std::endl;
    }

    return 0;
}
