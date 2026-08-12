#include "model_loader.hpp"
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <iostream>

namespace ai_engine {

RawModel::RawModel(const std::string& path) : path_(path) {
    fd_ = open(path.c_str(), O_RDONLY);
    if (fd_ < 0) return;

    struct stat sb;
    if (fstat(fd_, &sb) == 0) {
        file_size_ = sb.st_size;
        mapped_ptr_ = mmap(nullptr, file_size_, PROT_READ, MAP_PRIVATE, fd_, 0);
        if (mapped_ptr_ == MAP_FAILED) {
            mapped_ptr_ = nullptr;
        } else {
            parse_header_and_descriptors();
        }
    }
}

RawModel::~RawModel() {
    if (mapped_ptr_) {
        munmap(mapped_ptr_, file_size_);
    }
    if (fd_ >= 0) {
        close(fd_);
    }
}

void RawModel::parse_header_and_descriptors() {
    // Scaffold: check GGUF magic or AIMD
    uint32_t* magic = static_cast<uint32_t*>(mapped_ptr_);
    if (*magic == 0x46554747) { // 'GGUF'
        // Handle GGUF format zero-copy mmap scaffolding
        // For the sake of the engine baseline, we mock the header
        header_.magic = *magic;
        header_.version = 3;
        header_.vocab_size = 32000;
        header_.hidden_dim = 4096;
        header_.num_layers = 32;
        header_.num_heads = 32;
        header_.max_seq_len = 2048;
        header_.tensor_count = 0;
    } else {
        // Fallback to AIMD
        header_ = *static_cast<ModelHeader*>(mapped_ptr_);
    }
}

Tensor RawModel::get_tensor(const std::string& name) const {
    auto it = tensor_table_.find(name);
    if (it != tensor_table_.end()) {
        const auto& desc = it->second;
        TensorShape shape;
        shape.batch = desc.dims[0];
        shape.channels = desc.dims[1];
        shape.height = desc.dims[2];
        shape.width = desc.dims[3];
        void* ptr = static_cast<char*>(mapped_ptr_) + desc.offset;
        return Tensor(shape, static_cast<DataType>(desc.type), ptr);
    }
    throw std::runtime_error("Tensor not found: " + name);
}

bool RawModel::has_tensor(const std::string& name) const {
    return tensor_table_.find(name) != tensor_table_.end();
}

} // namespace ai_engine
