#if canImport(AVFoundation)
import AVFoundation
import LowdriftDSP

/// Builds the AVAudioSourceNode that feeds the procedural renderer to the system.
public enum ProceduralSource {
    /// A mono Float32 source node at `sampleRate`.
    ///
    /// The render block captures only the renderer and calls nothing but
    /// `NoiseRenderer.render`: no allocation, locks, logging, I/O, Objective-C
    /// messaging, async work or main-actor calls happen on the audio thread.
    public static func makeNode(renderer: NoiseRenderer, sampleRate: Double) -> AVAudioSourceNode? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        return AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList in
            render(renderer, isSilence: isSilence, frameCount: frameCount, bufferList: bufferList)
        }
    }

    static func render(
        _ renderer: NoiseRenderer,
        isSilence: UnsafeMutablePointer<ObjCBool>,
        frameCount: AVAudioFrameCount,
        bufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard buffers.count > 0, let first = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
            return noErr
        }
        let capacity = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.stride
        let frames = min(Int(frameCount), capacity)
        let silent = renderer.render(into: first, frameCount: frames)
        // The format is mono, so there is one buffer; copy defensively if not.
        if buffers.count > 1 {
            for index in 1 ..< buffers.count {
                buffers[index].mData?.copyMemory(from: first, byteCount: frames * MemoryLayout<Float>.stride)
            }
        }
        isSilence.pointee = ObjCBool(silent)
        return noErr
    }
}
#endif
