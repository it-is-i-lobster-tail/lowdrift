#include "LDAtomics.h"

// The atomics are header-only `static inline` functions. SwiftPM needs at least
// one source file in a C target, so this translation unit only anchors the module.
int ld_atomics_module_anchor(void) {
    return ld_atomic_is_lock_free_u32();
}
