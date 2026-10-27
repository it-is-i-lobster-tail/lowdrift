import Foundation
import LowdriftDSP

// Offline measurement helpers used by the tests and the render tool. None of
// this code is linked into the app.

/// Renders a sound offline through a fresh renderer, after letting the fade-in finish.
public func renderSound(
    _ profile: SoundProfile,
    depth: Double,
    airflow: Double,
    hum: Double,
    seconds: Double,
    sampleRate: Double = 48_000,
    seed: UInt64 = 0x10D2_1F7,
    settleSeconds: Double = 2,
    compactSpeaker: Bool = false,
    characters: [SoundCharacter]? = nil
) -> [Float] {
    let renderer = NoiseRenderer(
        sampleRate: sampleRate,
        characters: characters ?? SoundProfile.allCases.map(\.character),
        seed: seed
    )
    renderer.setCompactSpeaker(compactSpeaker)
    renderer.setSound(profile, depth: depth, airflow: airflow, hum: hum)
    renderer.fadeIn()
    var discard = [Float](repeating: 0, count: 1_024)
    var remaining = Int(settleSeconds * sampleRate)
    while remaining > 0 {
        let n = min(remaining, discard.count)
        discard.withUnsafeMutableBufferPointer { _ = renderer.render(into: $0.baseAddress!, frameCount: n) }
        remaining -= n
    }
    return render(renderer, frames: Int(seconds * sampleRate))
}

/// Pulls `frames` samples from a renderer in hardware-sized slices.
public func render(_ renderer: NoiseRenderer, frames: Int, slice: Int = 512) -> [Float] {
    var output = [Float](repeating: 0, count: frames)
    output.withUnsafeMutableBufferPointer { buffer in
        var offset = 0
        while offset < frames {
            let n = min(slice, frames - offset)
            _ = renderer.render(into: buffer.baseAddress! + offset, frameCount: n)
            offset += n
        }
    }
    return output
}

public enum Signal {
    public static func rms(_ x: ArraySlice<Float>) -> Double {
        guard !x.isEmpty else { return 0 }
        var sum = 0.0
        for v in x { sum += Double(v) * Double(v) }
        return (sum / Double(x.count)).squareRoot()
    }

    public static func rms(_ x: [Float]) -> Double { rms(x[...]) }

    public static func mean(_ x: [Float]) -> Double {
        guard !x.isEmpty else { return 0 }
        return x.reduce(0.0) { $0 + Double($1) } / Double(x.count)
    }

    public static func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    /// Largest sample-to-sample change.
    public static func maxStep(_ x: [Float]) -> Float {
        guard x.count > 1 else { return 0 }
        var m: Float = 0
        for i in 1..<x.count { m = max(m, abs(x[i] - x[i - 1])) }
        return m
    }

    /// RMS in consecutive windows.
    public static func envelope(_ x: [Float], window: Int) -> [Double] {
        stride(from: 0, to: x.count - window + 1, by: window).map { rms(x[$0 ..< $0 + window]) }
    }

    public static func decibels(_ linear: Double) -> Double { 20 * log10(max(linear, 1e-12)) }

    /// Normalised cross-correlation of two equal-length segments at lag 0.
    public static func correlation(_ a: ArraySlice<Float>, _ b: ArraySlice<Float>) -> Double {
        let n = min(a.count, b.count)
        var ab = 0.0, aa = 0.0, bb = 0.0
        var ia = a.startIndex, ib = b.startIndex
        for _ in 0..<n {
            let x = Double(a[ia]), y = Double(b[ib])
            ab += x * y; aa += x * x; bb += y * y
            ia += 1; ib += 1
        }
        return ab / max((aa * bb).squareRoot(), 1e-30)
    }
}

/// Iterative radix-2 complex FFT.
public struct FFT {
    public let size: Int
    private let cosTable: [Double]
    private let sinTable: [Double]

    public init(size: Int) {
        precondition(size > 1 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        cosTable = (0..<size / 2).map { cos(2 * Double.pi * Double($0) / Double(size)) }
        sinTable = (0..<size / 2).map { -sin(2 * Double.pi * Double($0) / Double(size)) }
    }

    public func transform(real: inout [Double], imag: inout [Double]) {
        let n = size
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { real.swapAt(i, j); imag.swapAt(i, j) }
        }
        var length = 2
        while length <= n {
            let step = n / length
            let half = length / 2
            var start = 0
            while start < n {
                for k in 0..<half {
                    let wr = cosTable[k * step], wi = sinTable[k * step]
                    let a = start + k, b = a + half
                    let tr = real[b] * wr - imag[b] * wi
                    let ti = real[b] * wi + imag[b] * wr
                    real[b] = real[a] - tr; imag[b] = imag[a] - ti
                    real[a] += tr; imag[a] += ti
                }
                start += length
            }
            length <<= 1
        }
    }
}

/// One-sided power spectral density estimate.
public struct PowerSpectrum {
    public let frequencies: [Double]
    /// Power per Hz.
    public let density: [Double]
    public let binWidth: Double

    /// Welch estimate with Hann windows and 50 % overlap.
    public init(_ x: [Float], sampleRate: Double, segment: Int = 16_384) {
        let fft = FFT(size: segment)
        let window = (0..<segment).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(segment)) }
        let windowPower = window.reduce(0) { $0 + $1 * $1 }
        var accumulated = [Double](repeating: 0, count: segment / 2 + 1)
        var segments = 0
        var start = 0
        while start + segment <= x.count {
            var re = (0..<segment).map { Double(x[start + $0]) * window[$0] }
            var im = [Double](repeating: 0, count: segment)
            fft.transform(real: &re, imag: &im)
            for k in 0...segment / 2 { accumulated[k] += re[k] * re[k] + im[k] * im[k] }
            segments += 1
            start += segment / 2
        }
        let scale = 1 / (Double(max(segments, 1)) * windowPower * sampleRate)
        density = accumulated.enumerated().map { k, v in
            let oneSided = (k == 0 || k == segment / 2) ? 1.0 : 2.0
            return v * scale * oneSided
        }
        binWidth = sampleRate / Double(segment)
        frequencies = (0...segment / 2).map { Double($0) * sampleRate / Double(segment) }
    }

    public func power(from low: Double, to high: Double) -> Double {
        var sum = 0.0
        for (f, p) in zip(frequencies, density) where f >= low && f < high { sum += p * binWidth }
        return sum
    }

    /// RMS after the engine's own perceptual weighting.
    public var weightedRMS: Double {
        var sum = 0.0
        for (f, p) in zip(frequencies, density) where f > 0 { sum += p * Double(loudnessWeightPower(Float(f))) * binWidth }
        return sum.squareRoot()
    }

    /// RMS after standard A-weighting.
    public var aWeightedRMS: Double {
        var sum = 0.0
        for (f, p) in zip(frequencies, density) where f > 0 { sum += p * aWeightingPower(f) * binWidth }
        return sum.squareRoot()
    }

    /// Power-weighted mean frequency between 20 Hz and 16 kHz.
    public var centroid: Double {
        var num = 0.0, den = 0.0
        for (f, p) in zip(frequencies, density) where f >= 20 && f <= 16_000 { num += f * p; den += p }
        return num / max(den, 1e-30)
    }

    /// Levels (dB) in third-octave bands from 25 Hz to 12.5 kHz.
    public var thirdOctaveLevels: [(center: Double, level: Double)] {
        (0..<28).map { i in
            let center = 25 * pow(2, Double(i) / 3)
            let p = power(from: center / pow(2, 1.0 / 6), to: center * pow(2, 1.0 / 6))
            return (center, 10 * log10(max(p, 1e-20)))
        }
    }

    /// Peak-to-local-floor ratio (dB) of the strongest bin within ±`tolerance` Hz of `hz`,
    /// compared with the median of bins 15–60 Hz away. Measures tonal prominence.
    public func tonalProminence(at hz: Double, tolerance: Double = 2) -> Double {
        let peak = zip(frequencies, density).filter { abs($0.0 - hz) <= tolerance }.map(\.1).max() ?? 0
        let floor = zip(frequencies, density).filter { abs($0.0 - hz) >= 15 && abs($0.0 - hz) <= 60 }.map(\.1).sorted()
        guard !floor.isEmpty else { return 0 }
        return 10 * log10(max(peak, 1e-30) / max(floor[floor.count / 2], 1e-30))
    }
}

public func aWeightingPower(_ hz: Double) -> Double {
    let f2 = hz * hz
    let ra = pow(12_194.217, 2) * f2 * f2
        / ((f2 + pow(20.598_997, 2)) * ((f2 + pow(107.652_65, 2)) * (f2 + pow(737.862_23, 2))).squareRoot()
            * (f2 + pow(12_194.217, 2)))
    let gain = ra * 1.258_925_4
    return gain * gain
}

public enum WAVFile {
    /// Writes 16-bit PCM mono with TPDF dither.
    public static func write16(_ samples: [Float], sampleRate: Int, to url: URL) throws {
        var data = header(dataBytes: samples.count * 2, sampleRate: sampleRate, bitsPerSample: 16, format: 1)
        var dither = NoiseSource(seed: 0xD17_4E5)
        data.reserveCapacity(data.count + samples.count * 2)
        for s in samples {
            let tpdf = (dither.nextBipolar() + dither.nextBipolar()) * 0.5
            let v = Int16(clamping: Int((Double(s) * 32_767 + Double(tpdf)).rounded()))
            withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
        }
        try data.write(to: url)
    }

    private static func header(dataBytes: Int, sampleRate: Int, bitsPerSample: Int, format: Int) -> Data {
        var d = Data()
        func append32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
        func append16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); append32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); append32(16); append16(format); append16(1)
        append32(sampleRate); append32(sampleRate * bitsPerSample / 8); append16(bitsPerSample / 8); append16(bitsPerSample)
        d.append(contentsOf: Array("data".utf8)); append32(dataBytes)
        return d
    }
}
