// lowdrift-render: renders Lowdrift presets to WAV files and prints a short
// acoustic summary, so sounds can be auditioned and tuned without the app.
//
//   swift run -c release lowdrift-render                # all presets, 30 s each
//   swift run -c release lowdrift-render basementAC --seconds 120 --depth 90
//   swift run -c release lowdrift-render all --out ~/Desktop/lowdrift-previews
//   swift run -c release lowdrift-render --bench          # render cost per preset

import Foundation
import LowdriftAnalysis
import LowdriftCore
import LowdriftDSP

struct Options {
    var presets: [Preset] = Preset.allCases
    var seconds = 30.0
    var sampleRate = 48_000.0
    var depth: Double?
    var airflow: Double?
    var hum: Double?
    var flutter: Double?
    var drift: Double?
    var output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("previews")
    var writeFiles = true
    /// Renders every preset at the corners and centre of the Depth × Airflow range.
    var matrix = false
    /// Simulates the phone's built-in speaker route.
    var compactSpeaker = false
}

func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--seconds": options.seconds = Double(iterator.next() ?? "") ?? options.seconds
        case "--rate": options.sampleRate = Double(iterator.next() ?? "") ?? options.sampleRate
        case "--depth": options.depth = Double(iterator.next() ?? "")
        case "--airflow": options.airflow = Double(iterator.next() ?? "")
        case "--hum": options.hum = Double(iterator.next() ?? "")
        case "--flutter": options.flutter = Double(iterator.next() ?? "")
        case "--drift": options.drift = Double(iterator.next() ?? "")
        case "--out": options.output = URL(fileURLWithPath: (iterator.next() ?? "previews") as NSString as String)
        case "--no-files": options.writeFiles = false
        case "--matrix": options.matrix = true
        case "--speaker": options.compactSpeaker = true
        case "--predict", "--bench": break
        case "all": options.presets = Preset.allCases
        default:
            if let preset = Preset(rawValue: argument) {
                options.presets = [preset]
            } else {
                FileHandle.standardError.write(Data("Unknown argument \(argument)\n".utf8))
                exit(2)
            }
        }
    }
    return options
}

let options = parse(Array(CommandLine.arguments.dropFirst()))
if options.writeFiles {
    try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
}

func format(_ value: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", value) }

if CommandLine.arguments.contains("--bench") {
    // Render cost in steady playback, in hardware-sized slices (4,096 frames is
    // what iOS uses with the screen locked). Reports nanoseconds per output
    // sample and how many times faster than real time this machine renders.
    let slice = 4_096
    let seconds = CommandLine.arguments.contains("--seconds") ? options.seconds : 120
    var buffer = [Float](repeating: 0, count: slice)
    print("preset         ns/sample   × real time")
    var totalNs = 0.0
    for preset in options.presets {
        let defaults = preset.defaultControls
        let renderer = NoiseRenderer(sampleRate: options.sampleRate, seed: 0x10D2_1F7)
        renderer.setCompactSpeaker(options.compactSpeaker)
        renderer.setSound(preset.soundProfile, depth: (options.depth ?? defaults.depth) / 100,
                          airflow: (options.airflow ?? defaults.airflow) / 100, hum: (options.hum ?? defaults.hum) / 100,
                          flutter: (options.flutter ?? defaults.flutter) / 100, drift: (options.drift ?? defaults.drift) / 100)
        renderer.fadeIn()
        let frames = Int(seconds * options.sampleRate)
        func run(_ count: Int) {
            var remaining = count
            buffer.withUnsafeMutableBufferPointer { pointer in
                while remaining > 0 {
                    let n = min(remaining, slice)
                    _ = renderer.render(into: pointer.baseAddress!, frameCount: n)
                    remaining -= n
                }
            }
        }
        run(Int(2 * options.sampleRate)) // settle past the fade-in
        // Best of five runs, to keep other work on the machine out of the figure.
        var perSample = Double.infinity
        for _ in 0 ..< 5 {
            let start = DispatchTime.now().uptimeNanoseconds
            run(frames / 5)
            perSample = min(perSample, Double(DispatchTime.now().uptimeNanoseconds - start) / Double(frames / 5))
        }
        totalNs += perSample
        let name = preset.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
        print("\(name) \(format(perSample, 1).padding(toLength: 11, withPad: " ", startingAt: 0)) \(format(1e9 / (perSample * options.sampleRate), 0))")
    }
    print("mean           \(format(totalNs / Double(options.presets.count), 1))")
    exit(0)
}

if CommandLine.arguments.contains("--predict") {
    for preset in options.presets {
        let defaults = preset.defaultControls
        for (label, depth, airflow) in [("default", defaults.depth, defaults.airflow), ("d0", 0, 50), ("d100", 100, 50),
                                        ("d100a0", 100, 0), ("d100a100", 100, 100)] {
            let p = NoiseRenderer.predict(preset.soundProfile, depth: depth / 100, airflow: airflow / 100,
                                          hum: defaults.hum / 100, compactSpeaker: options.compactSpeaker)
            print("\(preset.rawValue) \(label): rms \(format(Signal.decibels(Double(p.rms)))) weighted \(format(Signal.decibels(Double(p.weightedRMS))))")
        }
    }
    exit(0)
}

if options.matrix {
    for preset in options.presets {
        for depth in [0.0, 50, 100] {
            for airflow in [0.0, 50, 100] {
                let hum = options.hum ?? preset.defaultControls.hum
                let samples = renderSound(preset.soundProfile, depth: depth / 100, airflow: airflow / 100,
                                          hum: hum / 100, seconds: options.seconds, sampleRate: options.sampleRate,
                                          compactSpeaker: options.compactSpeaker)
                let name = "\(preset.rawValue)_d\(Int(depth))_a\(Int(airflow))_h\(Int(hum)).wav"
                try WAVFile.write16(samples, sampleRate: Int(options.sampleRate),
                                    to: options.output.appendingPathComponent(name))
            }
        }
    }
    print("Wrote matrix renders to \(options.output.path)")
    exit(0)
}

print("preset         rms dBFS  weighted  A-wt   peak   centroid Hz")
for preset in options.presets {
    let defaults = preset.defaultControls
    let depth = options.depth ?? defaults.depth
    let airflow = options.airflow ?? defaults.airflow
    let hum = options.hum ?? defaults.hum
    let flutter = options.flutter ?? defaults.flutter
    let drift = options.drift ?? defaults.drift
    let samples = renderSound(preset.soundProfile, depth: depth / 100, airflow: airflow / 100, hum: hum / 100,
                              flutter: flutter / 100, drift: drift / 100, seconds: options.seconds, sampleRate: options.sampleRate,
                              compactSpeaker: options.compactSpeaker)
    let spectrum = PowerSpectrum(samples, sampleRate: options.sampleRate)
    let name = preset.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
    print("\(name) \(format(Signal.decibels(Signal.rms(samples))))     \(format(Signal.decibels(spectrum.weightedRMS)))"
        + "    \(format(Signal.decibels(spectrum.aWeightedRMS)))  \(format(Double(Signal.peak(samples)), 2))   \(format(spectrum.centroid, 0))")
    if options.writeFiles {
        let url = options.output.appendingPathComponent("\(preset.rawValue).wav")
        try WAVFile.write16(samples, sampleRate: Int(options.sampleRate), to: url)
    }
}
if options.writeFiles { print("Wrote WAV files to \(options.output.path)") }
