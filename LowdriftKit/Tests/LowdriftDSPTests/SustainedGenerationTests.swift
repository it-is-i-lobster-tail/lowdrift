import Foundation
import LowdriftAnalysis
import LowdriftCore
import LowdriftDSP
import XCTest

/// Long-run behaviour: no repetition, no drift, no instability, and a small CPU cost.
final class SustainedGenerationTests: XCTestCase {
    private let rate = 48_000.0

    func testSustainedGenerationIsStable() {
        // Ten simulated minutes in optimised builds, two in debug builds.
        let minutes = isOptimizedBuild ? 10 : 2
        for preset in [Preset.basementAC, .airVent] {
            let renderer = playingRenderer(preset)
            var levels: [Double] = []
            for _ in 0 ..< minutes * 6 {
                let chunk = render(renderer, frames: Int(rate * 10), slice: 1_024)
                XCTAssertTrue(chunk.allSatisfy(\.isFinite), "\(preset) produced a non-finite sample")
                XCTAssertLessThan(Signal.peak(chunk), 0.97)
                XCTAssertLessThan(abs(Signal.mean(chunk)), 2e-3, "\(preset) drifted off zero")
                levels.append(decibels(Signal.rms(chunk)))
            }
            let mean = levels.reduce(0, +) / Double(levels.count)
            // Slow natural variation is allowed, but it stays subtle.
            XCTAssertLessThan(levels.map { abs($0 - mean) }.max()!, 1.5, "\(preset) level wandered: \(levels)")
        }
    }

    func testOutputNeverRepeats() {
        let samples = renderPreset(.towerFan, seconds: isOptimizedBuild ? 60 : 20)
        let second = Int(rate)
        let first = samples[0 ..< second]
        var worst = 0.0
        for start in stride(from: second, to: samples.count - second, by: second / 2) {
            worst = max(worst, abs(Signal.correlation(first, samples[start ..< start + second])))
        }
        XCTAssertLessThan(worst, 0.05, "A later segment correlates with the first second")
    }

    func testSlowVariationIsSubtleAndNotPeriodic() {
        let samples = renderPreset(.basementAC, seconds: isOptimizedBuild ? 120 : 40)
        // One-second RMS track: small spread and no strong periodicity (no LFO pumping).
        let track = Signal.envelope(samples, window: Int(rate)).map(decibels)
        let mean = track.reduce(0, +) / Double(track.count)
        let centered = track.map { $0 - mean }
        XCTAssertLessThan(centered.map(abs).max()!, 1.5)
        let variance = centered.map { $0 * $0 }.reduce(0, +)
        for lag in 2 ..< track.count / 3 {
            let r = zip(centered, centered.dropFirst(lag)).map { $0 * $1 }.reduce(0, +) / max(variance, 1e-12)
            XCTAssertLessThan(r, 0.6, "Envelope repeats with a period of \(lag) s")
        }
    }

    func testRenderCostIsSmall() {
        let renderer = playingRenderer(.boxFan)
        let frames = Int(rate * 20)
        let start = Date()
        _ = render(renderer, frames: frames, slice: 1_024)
        let elapsed = Date().timeIntervalSince(start)
        let realtimeFactor = 20 / elapsed
        print("Render speed: \(Int(realtimeFactor))× real time (\(isOptimizedBuild ? "optimised" : "debug") build)")
        // Debug builds are far slower than the app's release build; this only guards
        // against pathological regressions there.
        XCTAssertGreaterThan(realtimeFactor, isOptimizedBuild ? 100 : 3)
    }

    /// Simulates a full eight-hour night offline. Takes a few minutes in an
    /// optimised build; enable with LOWDRIFT_OVERNIGHT_TEST=1.
    func testOvernightRenderStaysClean() throws {
        guard ProcessInfo.processInfo.environment["LOWDRIFT_OVERNIGHT_TEST"] == "1" else {
            throw XCTSkip("Set LOWDRIFT_OVERNIGHT_TEST=1 to render eight hours offline")
        }
        let renderer = playingRenderer(.basementAC)
        var buffer = [Float](repeating: 0, count: 4_096)
        var minuteSum = 0.0, minuteCount = 0, peak: Float = 0
        var minuteLevels: [Double] = []
        let total = Int(rate * 8 * 3_600)
        var produced = 0
        while produced < total {
            let n = min(buffer.count, total - produced)
            buffer.withUnsafeMutableBufferPointer { _ = renderer.render(into: $0.baseAddress!, frameCount: n) }
            for i in 0 ..< n {
                let v = buffer[i]
                guard v.isFinite else { return XCTFail("Non-finite sample at \(produced + i)") }
                peak = max(peak, abs(v))
                minuteSum += Double(v * v)
            }
            minuteCount += n
            if minuteCount >= Int(rate * 60) {
                minuteLevels.append(decibels((minuteSum / Double(minuteCount)).squareRoot()))
                minuteSum = 0; minuteCount = 0
            }
            produced += n
        }
        let mean = minuteLevels.reduce(0, +) / Double(minuteLevels.count)
        print("Overnight: \(minuteLevels.count) minutes, peak \(peak), level spread \(minuteLevels.min()! - mean)…\(minuteLevels.max()! - mean) dB")
        XCTAssertLessThan(peak, 0.97)
        XCTAssertLessThan(minuteLevels.map { abs($0 - mean) }.max()!, 1.0)
    }
}
