import AppIntents
import LowdriftCore

/// The six sounds as Shortcuts and Siri see them.
enum SoundOption: String, AppEnum {
    case softFan
    case boxFan
    case basementAC
    case airVent
    case towerFan
    case deepDrift

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sound"

    static let caseDisplayRepresentations: [SoundOption: DisplayRepresentation] = [
        .softFan: "Soft Fan",
        .boxFan: "Box Fan",
        .basementAC: "Basement AC",
        .airVent: "Air Vent",
        .towerFan: "Tower Fan",
        .deepDrift: "Deep Drift",
    ]

    var preset: Preset {
        switch self {
        case .softFan: return .softFan
        case .boxFan: return .boxFan
        case .basementAC: return .basementAC
        case .airVent: return .airVent
        case .towerFan: return .towerFan
        case .deepDrift: return .deepDrift
        }
    }
}

/// Reported to Shortcuts when audio could not start, so the shortcut fails
/// honestly instead of claiming playback.
struct PlaybackIntentError: Error, CustomLocalizedStringResourceConvertible {
    let failure: PlaybackFailure

    var localizedStringResource: LocalizedStringResource {
        switch failure {
        case .audioBusy: return "Audio is in use by another app or a call."
        case .couldNotStart: return "Lowdrift couldn’t start audio."
        case .stoppedUnexpectedly: return "Playback stopped unexpectedly."
        }
    }
}

struct PlayIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Lowdrift"

    @MainActor
    func perform() async throws -> some IntentResult {
        let controller = AppEnvironment.shared.controller
        controller.play()
        if !controller.isPlaying {
            throw PlaybackIntentError(failure: controller.failure ?? .couldNotStart)
        }
        return .result()
    }
}

struct PauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Pause Lowdrift"

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.shared.controller.pause()
        return .result()
    }
}

struct PlaySoundIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play a Lowdrift Sound"

    @Parameter(title: "Sound")
    var sound: SoundOption

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$sound)")
    }

    init() {}

    init(sound: SoundOption) {
        self.sound = sound
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let controller = AppEnvironment.shared.controller
        controller.select(sound.preset)
        controller.play()
        if !controller.isPlaying {
            throw PlaybackIntentError(failure: controller.failure ?? .couldNotStart)
        }
        return .result()
    }
}

struct LowdriftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayIntent(),
            phrases: ["Play \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Play",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PauseIntent(),
            phrases: ["Pause \(.applicationName)", "Stop \(.applicationName)"],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: PlaySoundIntent(),
            phrases: ["Play \(\.$sound) in \(.applicationName)", "Start \(\.$sound) in \(.applicationName)"],
            shortTitle: "Play Sound",
            systemImageName: "wind"
        )
    }
}
