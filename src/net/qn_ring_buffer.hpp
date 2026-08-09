#ifndef QN_RING_BUFFER_H
#define QN_RING_BUFFER_H

#include <atomic>
#include <vector>

namespace godot {

template <typename T, size_t Capacity>
class SPSCRingBuffer {
private:
    std::vector<T> buffer;
    std::atomic<size_t> head{0};
    std::atomic<size_t> tail{0};

public:
    SPSCRingBuffer() : buffer(Capacity) {}

    bool push(const T& item) {
        size_t current_tail = tail.load(std::memory_order_relaxed);
        size_t next_tail = (current_tail + 1) % Capacity;
        
        if (next_tail == head.load(std::memory_order_acquire)) {
            return false; // Queue is full
        }
        
        buffer[current_tail] = item;
        tail.store(next_tail, std::memory_order_release);
        return true;
    }

    bool pop(T& item) {
        size_t current_head = head.load(std::memory_order_relaxed);
        
        if (current_head == tail.load(std::memory_order_acquire)) {
            return false; // Queue is empty
        }
        
        item = buffer[current_head];
        buffer[current_head] = T(); // Libera imediatamente a referência do objeto (evita vazamento em PackedByteArrays/Dicionários)
        head.store((current_head + 1) % Capacity, std::memory_order_release);
        return true;
    }
    
    size_t size() const {
        size_t h = head.load(std::memory_order_acquire);
        size_t t = tail.load(std::memory_order_acquire);
        if (t >= h) return t - h;
        return Capacity - h + t;
    }
};

} // namespace godot

#endif // QN_RING_BUFFER_H
