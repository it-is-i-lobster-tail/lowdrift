#if os(iOS)
import AVFoundation
import LowdriftCore

/// Turns audio session and engine notifications into playback controller events:
/// interruptions (calls, Siri, alarms), lost routes (headphones unplugged),
/// hardware configuration changes and media services resets.
@MainActor
public final class AudioSessionCoordinator {
    private let controller: PlaybackController
    private let output: AudioEngineOutput
    private var observers: [NSObjectProtocol] = []

    public init(controller: PlaybackController, output: AudioEngineOutput) {
        self.controller = controller
        self.output = output
    }

    public func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        // These notifications can arrive on background threads; delivering them on
        // the main queue keeps all playback state on the main actor.
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
                let event = InterruptionEvent(note.userInfo)
                guard let self else { return }
                MainActor.assumeIsolated { self.handle(event) }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                    .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                guard let self else { return }
                MainActor.assumeIsolated { self.handleRouteChange(reason) }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated { self.controller.mediaServicesWereReset() }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated { self.controller.engineConfigurationChanged() }
            },
        ]
    }

    private func handle(_ event: InterruptionEvent) {
        switch event {
        case .began:
            controller.interruptionBegan()
        case let .ended(shouldResume):
            controller.interruptionEnded(shouldResume: shouldResume)
        case .unknown:
            break
        }
    }

    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason?) {
        // Headphones unplugged, Bluetooth disconnected or AirPlay ended: pause
        // rather than continue out of the phone's speaker.
        if reason == .oldDeviceUnavailable {
            controller.outputRouteLost()
        }
        output.updateRoute()
    }
}

private enum InterruptionEvent: Sendable {
    case began
    case ended(shouldResume: Bool)
    case unknown

    init(_ userInfo: [AnyHashable: Any]?) {
        guard let raw = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else {
            self = .unknown
            return
        }
        switch type {
        case .began:
            self = .began
        case .ended:
            let options = (userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            self = .ended(shouldResume: options.contains(.shouldResume))
        @unknown default:
            self = .unknown
        }
    }
}
#endif
