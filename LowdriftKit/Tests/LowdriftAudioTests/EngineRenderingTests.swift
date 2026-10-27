#if canImport(AVFoundation)
import AVFoundation
import LowdriftAudio
import LowdriftDSP
import XCTest

/// Runs the real source node inside a real AVAudioEngine (offline manual
/// rendering), so the render block and graph are exercised without hardware.
final class EngineRenderingTests: XCTestCase {
    private struct Harness {
        let engine: AVAudioEngine
        let renderer: NoiseRenderer
        let buffer: AVAudioPCMBuffer

        init(sampleRate: Double) throws {
            renderer = NoiseRenderer(sampleRate: sampleRate, seed: 9)
            engine = AVAudioEngine()
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
            let node = try XCTUnwrap(ProceduralSource.makeNode(renderer: renderer, sampleRate: sampleRate))
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: node.outputFormat(forBus: 0))
            try engine.start()
            buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4_096))
        }

        /// Renders `seconds` of stereo output.
        func render(seconds: Double) throws -> (left: [Float], right: [Float]) {
            var left: [Float] = [], right: [Float] = []
            let total = Int(seconds * engine.manualRenderingFormat.sampleRate)
            while left.count < total {
                let status = try engine.renderOffline(AVAudioFrameCount(min(4_096, total - left.count)), to: buffer)
                XCTAssertEqual(status, .success)
                let channels = try XCTUnwrap(buffer.floatChannelData)
                let n = Int(buffer.frameLength)
                left += UnsafeBufferPointer(start: channels[0], count: n)
                right += UnsafeBufferPointer(start: channels[1], count: n)
            }
            return (left, right)
        }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        (samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(samples.count, 1))).squareRoot()
    }

    func testSourceNodePlaysThroughTheEngine() throws {
        for rate in [44_100.0, 48_000] {
            let harness = try Harness(sampleRate: rate)
            harness.renderer.setSound(.basementAC, depth: 0.8, airflow: 0.7, hum: 0.35)

            let before = try harness.render(seconds: 0.5)
            XCTAssertTrue(before.left.allSatisfy { $0 == 0 }, "Silent until Play")

            harness.renderer.fadeIn()
            let playing = try harness.render(seconds: 3)
            XCTAssertTrue(playing.left.allSatisfy { $0.isFinite && abs($0) < 1 })
            let level = 20 * log10(rms(playing.left.suffix(Int(rate))))
            XCTAssertGreaterThan(level, -40, "Audible through the mixer at \(rate) Hz")
            XCTAssertLessThan(level, -10)
            XCTAssertEqual(playing.left, playing.right, "Mono source reaches both channels identically")

            harness.renderer.fadeOut()
            let paused = try harness.render(seconds: 1)
            XCTAssertTrue(paused.left.suffix(4_096).allSatisfy { $0 == 0 }, "Fades to true silence")
            XCTAssertFalse(harness.renderer.isAudible)
            harness.engine.stop()
        }
    }

    func testOddRenderSizesThroughTheEngine() throws {
        let harness = try Harness(sampleRate: 48_000)
        harness.renderer.setSound(.towerFan, depth: 0.45, airflow: 0.55, hum: 0.25)
        harness.renderer.fadeIn()
        for frames in [1, 15, 512, 4_096, 333] {
            let status = try harness.engine.renderOffline(AVAudioFrameCount(frames), to: harness.buffer)
            XCTAssertEqual(status, .success)
            XCTAssertEqual(Int(harness.buffer.frameLength), frames)
        }
        harness.engine.stop()
    }
}
#endif
