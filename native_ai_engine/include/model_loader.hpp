#ifndef NATIVE_AI_ENGINE_MODEL_LOADER_HPP
#define NATIVE_AI_ENGINE_MODEL_LOADER_HPP

#include "tensor.hpp"
#include <string>
#include <vector>
#include <unordered_map>
#include <memory>

namespace ai_engine {

#pragma pack(push, 1)
struct ModelHeader {
    uint32_t magic;         // 0x41494D44 ("AIMD" in ASCII)
    uint32_t version;       // Version (e.g. 1)
    uint32_t vocab_size;    // Vocabulary size
    uint32_t hidden_dim;    // Hidden dimension size
    uint32_t num_layers;    // Number of transformer/neural layers
    uint32_t num_heads;     // Attention heads
    uint32_t max_seq_len;   // Context window size
    uint32_t tensor_count;  // Total tensor count in binary file
};
#pragma pack(pop)

struct TensorDescriptor {
    char name[64];
    uint32_t type; // DataType enum
    uint32_t dims[4];
    uint64_t offset; // Byte offset in mmap
    uint64_t size_bytes;
};

class RawModel {
public:
    RawModel(const std::string& path);
    ~RawModel();

    // Disable copy
    RawModel(const RawModel&) = delete;
    RawModel& operator=(const RawModel&) = delete;

    bool is_valid() const { return mapped_ptr_ != nullptr; }
    const ModelHeader& header() const { return header_; }
    const std::string& path() const { return path_; }

    Tensor get_tensor(const std::string& name) const;
    bool has_tensor(const std::string& name) const;

private:
    std::string path_;
    int fd_ = -1;
    size_t file_size_ = 0;
    void* mapped_ptr_ = nullptr;
    ModelHeader header_{};
    std::unordered_map<std::string, TensorDescriptor> tensor_table_;

    void parse_header_and_descriptors();
};

} // namespace ai_engine

#endif // NATIVE_AI_ENGINE_MODEL_LOADER_HPP
