import SwiftUI

/// One soft wave line, used by the header decoration and the card motifs.
struct WaveLine {
    /// Vertical position of the line's centre, as a fraction of the height.
    var baseline: Double
    /// Peak displacement, as a fraction of the height.
    var amplitude: Double
    /// Length of one cycle, as a fraction of the width.
    var wavelength: Double
    /// Starting phase in radians.
    var phase: Double = 0

    func path(in rect: CGRect, shift: Double = 0) -> Path {
        var path = Path()
        let width = Double(rect.width), height = Double(rect.height)
        guard width > 1, height > 1 else { return path }
        let minX = Double(rect.minX), minY = Double(rect.minY)
        let cycle = max(width * wavelength, 1)
        func point(_ x: Double) -> CGPoint {
            let t = x / cycle * 2 * Double.pi + phase + shift
            // A second, slower component keeps the line from looking like a pure sine.
            let shape = (sin(t) + 0.35 * sin(0.53 * t + 1.3)) / 1.35
            return CGPoint(x: minX + x, y: minY + height * (baseline + amplitude * shape))
        }
        path.move(to: point(0))
        var x = 0.0
        while x < width {
            x = min(x + 3, width)
            path.addLine(to: point(x))
        }
        return path
    }
}

/// The airy layered waves under the wordmark. Purely decorative: hidden from
/// VoiceOver and never an analyzer. It drifts slowly only while sound is playing,
/// the app is in the foreground and Reduce Motion is off; otherwise the timeline
/// is paused and nothing is redrawn.
struct WaveDecoration: View {
    var isAnimating: Bool

    @State private var restingShift: Double = 0
    @State private var animationStart: Date?

    private struct Layer {
        var line: WaveLine
        var speed: Double
        var opacity: Double
        var width: CGFloat
    }

    private static let layers: [Layer] = [
        Layer(line: WaveLine(baseline: 0.34, amplitude: 0.12, wavelength: 1.25, phase: 0.4), speed: 0.10, opacity: 0.20, width: 1.5),
        Layer(line: WaveLine(baseline: 0.46, amplitude: 0.16, wavelength: 0.95, phase: 2.1), speed: 0.16, opacity: 0.34, width: 2),
        Layer(line: WaveLine(baseline: 0.58, amplitude: 0.14, wavelength: 1.5, phase: 4.0), speed: 0.07, opacity: 0.55, width: 2.5),
        Layer(line: WaveLine(baseline: 0.70, amplitude: 0.10, wavelength: 0.8, phase: 5.2), speed: 0.12, opacity: 0.26, width: 1.5),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            let elapsed = elapsedSeconds(at: timeline.date)
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                // A faint wash below the strongest line gives the waves some body.
                let strongest = Self.layers[2]
                var fill = strongest.line.path(in: rect, shift: elapsed * strongest.speed)
                fill.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                fill.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                fill.closeSubpath()
                context.fill(fill, with: .linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0.10), Theme.accent.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: rect.height * 0.45),
                    endPoint: CGPoint(x: 0, y: rect.maxY)
                ))
                for layer in Self.layers {
                    context.stroke(
                        layer.line.path(in: rect, shift: elapsed * layer.speed),
                        with: .color(Theme.accent.opacity(layer.opacity)),
                        style: StrokeStyle(lineWidth: layer.width, lineCap: .round)
                    )
                }
            }
        }
        .onChange(of: isAnimating, initial: true) { _, animating in
            // Accumulate motion only while animating, so pausing and resuming
            // never makes the waves jump.
            let now = Date()
            if animating {
                animationStart = now
            } else if let start = animationStart {
                restingShift += now.timeIntervalSince(start)
                animationStart = nil
            }
        }
        .accessibilityHidden(true)
    }

    private func elapsedSeconds(at date: Date) -> Double {
        guard let start = animationStart else { return restingShift }
        return restingShift + max(0, date.timeIntervalSince(start))
    }
}

/// A small static wave glyph that hints at each sound's character.
struct WaveMotif: View {
    let lines: [WaveLine]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            for (index, line) in lines.enumerated() {
                context.stroke(
                    line.path(in: rect),
                    with: .color(Theme.accent.opacity(index == 0 ? 0.9 : 0.4)),
                    style: StrokeStyle(lineWidth: index == 0 ? 2 : 1.5, lineCap: .round)
                )
            }
        }
        .accessibilityHidden(true)
    }
}
