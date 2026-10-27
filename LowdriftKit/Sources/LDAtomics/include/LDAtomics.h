#ifndef LDATOMICS_H
#define LDATOMICS_H

#include <stdint.h>

// Minimal lock-free atomics for handing control values from the main thread to
// the real-time audio thread. They operate on plain, naturally aligned 32-bit
// words that Swift allocates once up front, so neither side ever allocates,
// locks or blocks.

static inline uint32_t ld_atomic_load_u32(const uint32_t *ptr) {
    return __atomic_load_n(ptr, __ATOMIC_ACQUIRE);
}

static inline void ld_atomic_store_u32(uint32_t *ptr, uint32_t value) {
    __atomic_store_n(ptr, value, __ATOMIC_RELEASE);
}

static inline uint32_t ld_atomic_fetch_add_u32(uint32_t *ptr, uint32_t value) {
    return __atomic_fetch_add(ptr, value, __ATOMIC_ACQ_REL);
}

static inline int ld_atomic_is_lock_free_u32(void) {
    return __atomic_always_lock_free(sizeof(uint32_t), 0) ? 1 : 0;
}

#endif /* LDATOMICS_H */
