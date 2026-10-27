import LowdriftAnalysis
import LowdriftCore
import LowdriftDSP
import XCTest

/// Renders a preset at its shipping controls (or overrides, 0–100 scale).
func renderPreset(
    _ preset: Preset,
    depth: Double? = nil,
    airflow: Double? = nil,
    hum: Double? = nil,
    seconds: Double = 4,
    sampleRate: Double = 48_000,
    compactSpeaker: Bool = false,
    seed: UInt64 = 0x10D2_1F7
) -> [Float] {
    let c = preset.defaultControls
    return renderSound(
        preset.soundProfile,
        depth: (depth ?? c.depth) / 100,
        airflow: (airflow ?? c.airflow) / 100,
        hum: (hum ?? c.hum) / 100,
        seconds: seconds,
        sampleRate: sampleRate,
        seed: seed,
        compactSpeaker: compactSpeaker
    )
}

/// A renderer that is already playing `preset` at full level.
func playingRenderer(_ preset: Preset, sampleRate: Double = 48_000, seed: UInt64 = 7) -> NoiseRenderer {
    let renderer = NoiseRenderer(sampleRate: sampleRate, seed: seed)
    let c = preset.defaultControls
    renderer.setSound(preset.soundProfile, depth: c.depth / 100, airflow: c.airflow / 100, hum: c.hum / 100)
    renderer.fadeIn()
    _ = render(renderer, frames: Int(sampleRate * 1.5))
    return renderer
}

func decibels(_ value: Double) -> Double { Signal.decibels(value) }

/// Third-octave band levels normalised to the same total weighted level.
func normalizedBandLevels(_ samples: [Float], sampleRate: Double = 48_000) -> [Double] {
    let spectrum = PowerSpectrum(samples, sampleRate: sampleRate)
    let offset = decibels(spectrum.weightedRMS)
    return spectrum.thirdOctaveLevels.filter { $0.center >= 40 && $0.center <= 10_000 }.map { $0.level - offset }
}

func rmsDistance(_ a: [Double], _ b: [Double]) -> Double {
    let squares = zip(a, b).map { ($0 - $1) * ($0 - $1) }
    return (squares.reduce(0, +) / Double(max(squares.count, 1))).squareRoot()
}

/// True when Xcode or `swift test` is running an optimised build; long renders
/// are scaled down for unoptimised builds so the suite stays quick.
var isOptimizedBuild: Bool {
    #if DEBUG
    return false
    #else
    return true
    #endif
}
