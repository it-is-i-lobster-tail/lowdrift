/// Long-period pseudorandom noise source for continuous procedural generation.
///
/// xoshiro128+ has a period of 2^128 − 1 samples. At 48 kHz that is roughly
/// 2 × 10^26 years before the sequence could repeat, so no listening session can
/// ever hear a repeated pattern. State is four 32-bit words, updated with a few
/// shifts and xors per sample: no tables, no allocation.
public struct NoiseSource: Sendable {
    private var s0: UInt32
    private var s1: UInt32
    private var s2: UInt32
    private var s3: UInt32

    public init(seed: UInt64) {
        // Expand the seed with SplitMix64 as recommended by the xoshiro authors.
        var x = seed
        func splitMix() -> UInt64 {
            x &+= 0x9E37_79B9_7F4A_7C15
            var z = x
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        let a = splitMix()
        let b = splitMix()
        s0 = UInt32(truncatingIfNeeded: a)
        s1 = UInt32(truncatingIfNeeded: a >> 32)
        s2 = UInt32(truncatingIfNeeded: b)
        s3 = UInt32(truncatingIfNeeded: b >> 32)
        if s0 | s1 | s2 | s3 == 0 { s0 = 0x9E37_79B9 } // the all-zero state is the only invalid one
    }

    @inline(__always)
    public mutating func next() -> UInt32 {
        let result = s0 &+ s3
        let t = s1 << 9
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = (s3 << 11) | (s3 >> 21)
        return result
    }

    /// Uniform white noise in [-1, 1) built from the 24 high bits (variance 1/3).
    @inline(__always)
    public mutating func nextBipolar() -> Float {
        Float(Int32(bitPattern: next()) >> 8) * (1.0 / 8_388_608.0)
    }

    /// Variance of `nextBipolar()`; used by the analytic loudness model.
    /// (A computed constant, not a stored global, so the render thread never
    /// touches lazily initialised globals.)
    public static var bipolarVariance: Float { 1.0 / 3.0 }
}
