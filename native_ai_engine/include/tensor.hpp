#ifndef NATIVE_AI_ENGINE_TENSOR_HPP
#define NATIVE_AI_ENGINE_TENSOR_HPP

#include <cstdint>
#include <cstddef>
#include <vector>
#include <memory>
#include <stdexcept>
#include <cmath>

namespace ai_engine {

enum class DataType {
    FP32 = 0,
    FP16 = 1,
    INT8 = 2,
    Q4_0 = 3
};

struct TensorShape {
    size_t batch = 1;
    size_t channels = 1;
    size_t height = 1;
    size_t width = 1;

    size_t total_elements() const {
        return batch * channels * height * width;
    }
};

class Tensor {
public:
    Tensor() : type_(DataType::FP32), data_ptr_(nullptr), own_memory_(false) {}
    
    Tensor(TensorShape shape, DataType type = DataType::FP32)
        : shape_(shape), type_(type), own_memory_(true) {
        size_t count = shape_.total_elements();
        size_t bytes = count * element_size(type);
        // Align memory to 64-byte boundary for ARM NEON / AVX instructions
        void* ptr = nullptr;
        if (posix_memalign(&ptr, 64, bytes) != 0 || !ptr) {
            throw std::runtime_error("Failed to allocate aligned tensor memory");
        }
        data_ptr_ = ptr;
    }

    // Zero-copy reference constructor over memory-mapped weights
    Tensor(TensorShape shape, DataType type, void* mmap_ptr)
        : shape_(shape), type_(type), data_ptr_(mmap_ptr), own_memory_(false) {}

    ~Tensor() {
        if (own_memory_ && data_ptr_) {
            free(data_ptr_);
            data_ptr_ = nullptr;
        }
    }

    // Move semantics
    Tensor(Tensor&& other) noexcept 
        : shape_(other.shape_), type_(other.type_), data_ptr_(other.data_ptr_), own_memory_(other.own_memory_) {
        other.data_ptr_ = nullptr;
        other.own_memory_ = false;
    }

    Tensor& operator=(Tensor&& other) noexcept {
        if (this != &other) {
            if (own_memory_ && data_ptr_) free(data_ptr_);
            shape_ = other.shape_;
            type_ = other.type_;
            data_ptr_ = other.data_ptr_;
            own_memory_ = other.own_memory_;
            other.data_ptr_ = nullptr;
            other.own_memory_ = false;
        }
        return *this;
    }

    // Disable copying for safety
    Tensor(const Tensor&) = delete;
    Tensor& operator=(const Tensor&) = delete;

    float* data_fp32() { return static_cast<float*>(data_ptr_); }
    const float* data_fp32() const { return static_cast<const float*>(data_ptr_); }

    int8_t* data_int8() { return static_cast<int8_t*>(data_ptr_); }
    const int8_t* data_int8() const { return static_cast<const int8_t*>(data_ptr_); }

    void* raw_data() { return data_ptr_; }
    const void* raw_data() const { return data_ptr_; }

    const TensorShape& shape() const { return shape_; }
    DataType type() const { return type_; }
    size_t total_elements() const { return shape_.total_elements(); }

    static size_t element_size(DataType type) {
        switch (type) {
            case DataType::FP32: return sizeof(float);
            case DataType::FP16: return sizeof(uint16_t);
            case DataType::INT8: return sizeof(int8_t);
            case DataType::Q4_0: return sizeof(uint8_t) / 2;
            default: return sizeof(float);
        }
    }

private:
    TensorShape shape_;
    DataType type_;
    void* data_ptr_;
    bool own_memory_;
};

} // namespace ai_engine

#endif // NATIVE_AI_ENGINE_TENSOR_HPP
