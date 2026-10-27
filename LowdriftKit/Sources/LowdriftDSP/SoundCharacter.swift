/// The six built-in sounds the engine knows how to generate.
public enum SoundProfile: Int, CaseIterable, Sendable {
    case softFan = 0
    case boxFan
    case basementAC
    case airVent
    case towerFan
    case deepDrift

    /// The tuned timbre for this profile. Read on the main thread only; the
    /// renderer copies the table once at creation.
    public var character: SoundCharacter {
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

/// Everything that makes one sound identity different from another.
///
/// Values describe the sound at neutral control positions (Depth 50, Airflow 50);
/// the `depth…` and `airflow…` fields say how far each slider moves it. The
/// engine combines these with the user's three slider values, then matches
/// perceived loudness analytically, so a character can be retuned by ear without
/// re-balancing levels by hand. All fields are plain numbers: the struct is
/// trivially copyable and safe to read on the audio thread.
public struct SoundCharacter: Sendable, Equatable {
    // MARK: Airflow layer: pink-ish noise → high-pass → two resonant bands → low-pass

    /// Low-frequency limit of the air layer (the rumble layer lives below it).
    public var airHighpassHz: Float
    /// Main darkness control of the air layer.
    public var lowpassHz: Float
    /// Q of each of the two low-pass stages (lower is softer).
    public var lowpassQ: Float
    /// Second low-pass stage cutoff as a multiple of the first; 1 is steep, 2–3 is velvety.
    public var lowpassSpread: Float
    /// Broad "whoosh" body band.
    public var whooshHz: Float
    public var whooshQ: Float
    /// Linear amount of whoosh band added to the air path (1 ≈ +6 dB at the peak).
    public var whooshBoost: Float
    /// Upper-air "presence" band (grille hiss, blade tips).
    public var presenceHz: Float
    public var presenceQ: Float
    public var presenceBoost: Float

    // MARK: Low body / rumble layer (independent noise)

    public var rumbleHz: Float
    /// Rumble power relative to the air layer, in dB.
    public var rumbleLevelDb: Float

    // MARK: Motor / blade coloration

    /// Fundamental of the motor hum. Harmonics 2–8 are phase-locked to it, so
    /// they never beat; the upper ones carry the hum on small speakers that
    /// cannot reproduce the fundamental.
    public var humHz: Float
    /// Relative prominence of harmonics 1–8, in dB.
    public var humHarmonicsDb: SIMD8<Float>
    /// Tone-to-noise ratio (within one critical band) of a partial at 0 dB relative
    /// prominence when Hum is at 100. About +8 dB reads as present but restrained.
    public var humPeakTNR: Float
    /// Narrow-band motor "whirr" centre as a multiple of `humHz`.
    public var humNoiseRatio: Float
    public var humNoiseQ: Float
    /// Prominence of the whirr relative to `humPeakTNR`, in dB. Very low values disable it.
    public var humNoiseDb: Float

    // MARK: Texture and natural variation

    /// Blade-pass amplitude texture rate. Kept in the roughness range, never a slow pulse.
    public var bladeHz: Float
    /// Blade-pass modulation depth at Airflow 50 (0.05 = ±5 %).
    public var bladeDepth: Float
    /// Standard deviation of the gentle flutter of the whoosh/presence bands at Airflow 50.
    public var turbulence: Float
    /// Amount of very slow, non-periodic drift in tone and balance (0…1).
    public var drift: Float

    // MARK: Slider sensitivity

    /// Low-pass movement across the whole Depth range, in octaves (deeper is darker).
    public var depthLowpassOctaves: Float
    public var depthWhooshOctaves: Float
    public var depthHighpassOctaves: Float
    /// Rumble change across the Depth range, in dB.
    public var depthRumbleDb: Float
    /// Presence reduction across the Depth range, in dB.
    public var depthPresenceDb: Float
    /// Low-pass movement across the Airflow range, in octaves (stronger is a little brighter).
    public var airflowLowpassOctaves: Float
    /// Whoosh band change across the Airflow range, in dB.
    public var airflowWhooshDb: Float
    /// Whoosh bandwidth change across the Airflow range, in octaves of Q (stronger is broader).
    public var airflowWidthOctaves: Float
    public var airflowPresenceDb: Float
    /// Rumble change across the Airflow range, in dB (stronger air masks the body a little).
    public var airflowRumbleDb: Float

    /// Final level trim after loudness matching, for by-ear balancing between presets.
    public var levelTrimDb: Float

    public init(
        airHighpassHz: Float,
        lowpassHz: Float,
        lowpassQ: Float = 0.62,
        lowpassSpread: Float = 1.6,
        whooshHz: Float,
        whooshQ: Float,
        whooshBoost: Float,
        presenceHz: Float,
        presenceQ: Float = 0.9,
        presenceBoost: Float,
        rumbleHz: Float,
        rumbleLevelDb: Float,
        humHz: Float,
        humHarmonicsDb: SIMD8<Float>,
        humPeakTNR: Float,
        humNoiseRatio: Float = 2,
        humNoiseQ: Float = 6,
        humNoiseDb: Float = -60,
        bladeHz: Float = 0,
        bladeDepth: Float = 0,
        turbulence: Float,
        drift: Float,
        depthLowpassOctaves: Float = 1.6,
        depthWhooshOctaves: Float = 0.8,
        depthHighpassOctaves: Float = 0.5,
        depthRumbleDb: Float = 8,
        depthPresenceDb: Float = 10,
        airflowLowpassOctaves: Float = 0.1,
        airflowWhooshDb: Float = 12,
        airflowWidthOctaves: Float = 0.8,
        airflowPresenceDb: Float = 8,
        airflowRumbleDb: Float = 0,
        levelTrimDb: Float = 0
    ) {
        self.airHighpassHz = airHighpassHz
        self.lowpassHz = lowpassHz
        self.lowpassQ = lowpassQ
        self.lowpassSpread = lowpassSpread
        self.whooshHz = whooshHz
        self.whooshQ = whooshQ
        self.whooshBoost = whooshBoost
        self.presenceHz = presenceHz
        self.presenceQ = presenceQ
        self.presenceBoost = presenceBoost
        self.rumbleHz = rumbleHz
        self.rumbleLevelDb = rumbleLevelDb
        self.humHz = humHz
        self.humHarmonicsDb = humHarmonicsDb
        self.humPeakTNR = humPeakTNR
        self.humNoiseRatio = humNoiseRatio
        self.humNoiseQ = humNoiseQ
        self.humNoiseDb = humNoiseDb
        self.bladeHz = bladeHz
        self.bladeDepth = bladeDepth
        self.turbulence = turbulence
        self.drift = drift
        self.depthLowpassOctaves = depthLowpassOctaves
        self.depthWhooshOctaves = depthWhooshOctaves
        self.depthHighpassOctaves = depthHighpassOctaves
        self.depthRumbleDb = depthRumbleDb
        self.depthPresenceDb = depthPresenceDb
        self.airflowLowpassOctaves = airflowLowpassOctaves
        self.airflowWhooshDb = airflowWhooshDb
        self.airflowWidthOctaves = airflowWidthOctaves
        self.airflowPresenceDb = airflowPresenceDb
        self.airflowRumbleDb = airflowRumbleDb
        self.levelTrimDb = levelTrimDb
    }
}

// MARK: - Tuned characters
//
// Starting points chosen from the spectra of real fans and HVAC systems heard
// across a room. Change them by listening: render previews with
// `swift run -c release lowdrift-render` from the LowdriftKit folder.

extension SoundCharacter {
    /// Soft, restrained, smooth; almost no motor.
    public static let softFan = SoundCharacter(
        airHighpassHz: 70,
        lowpassHz: 1_900,
        lowpassQ: 0.58,
        lowpassSpread: 2.4,
        whooshHz: 420,
        whooshQ: 0.6,
        whooshBoost: 0.55,
        presenceHz: 2_200,
        presenceBoost: 0.08,
        rumbleHz: 85,
        rumbleLevelDb: -15,
        humHz: 62,
        humHarmonicsDb: SIMD8(0, -4, -9, -13, -17, -21, -26, -32),
        humPeakTNR: 6,
        bladeHz: 31,
        bladeDepth: 0.012,
        turbulence: 0.05,
        drift: 0.5
    )

    /// Broad, steady fan rush with a trace of mechanical colour.
    public static let boxFan = SoundCharacter(
        airHighpassHz: 60,
        lowpassHz: 2_900,
        lowpassQ: 0.68,
        lowpassSpread: 1.5,
        whooshHz: 640,
        whooshQ: 0.5,
        whooshBoost: 0.95,
        presenceHz: 1_800,
        presenceQ: 0.8,
        presenceBoost: 0.22,
        rumbleHz: 95,
        rumbleLevelDb: -13,
        humHz: 55,
        humHarmonicsDb: SIMD8(0, -2, -5, -7, -9, -12, -15, -19),
        humPeakTNR: 9,
        humNoiseRatio: 2,
        humNoiseQ: 5,
        humNoiseDb: -8,
        bladeHz: 55,
        bladeDepth: 0.045,
        turbulence: 0.12,
        drift: 0.45
    )

    /// Signature sound: deep WHOOOSH, distant low HVAC presence, subtle motor.
    public static let basementAC = SoundCharacter(
        airHighpassHz: 42,
        lowpassHz: 1_150,
        lowpassQ: 0.66,
        lowpassSpread: 1.35,
        whooshHz: 255,
        whooshQ: 0.85,
        whooshBoost: 1.3,
        presenceHz: 1_100,
        presenceQ: 0.7,
        presenceBoost: 0,
        rumbleHz: 62,
        rumbleLevelDb: -5,
        humHz: 58,
        humHarmonicsDb: SIMD8(0, -1, -4, -6, -8, -11, -14, -18),
        humPeakTNR: 8,
        humNoiseRatio: 2,
        humNoiseQ: 7,
        humNoiseDb: -6,
        bladeHz: 23,
        bladeDepth: 0.01,
        turbulence: 0.09,
        drift: 1,
        depthLowpassOctaves: 1.8,
        depthWhooshOctaves: 0.9,
        depthRumbleDb: 9
    )

    /// Airier, slightly brighter diffuse ventilation; minimal motor.
    public static let airVent = SoundCharacter(
        airHighpassHz: 95,
        lowpassHz: 4_600,
        lowpassQ: 0.6,
        lowpassSpread: 1.8,
        whooshHz: 900,
        whooshQ: 0.45,
        whooshBoost: 0.45,
        presenceHz: 3_100,
        presenceQ: 0.7,
        presenceBoost: 0.3,
        rumbleHz: 105,
        rumbleLevelDb: -19,
        humHz: 92,
        humHarmonicsDb: SIMD8(0, -5, -10, -14, -19, -24, -30, -36),
        humPeakTNR: 5,
        turbulence: 0.15,
        drift: 0.35,
        depthLowpassOctaves: 1.4,
        depthWhooshOctaves: 0.7,
        depthPresenceDb: 9
    )

    /// Tighter, more focused fan texture with mild upper-air presence.
    public static let towerFan = SoundCharacter(
        airHighpassHz: 120,
        lowpassHz: 3_500,
        lowpassQ: 0.72,
        lowpassSpread: 1.3,
        whooshHz: 1_050,
        whooshQ: 1.15,
        whooshBoost: 1.5,
        presenceHz: 2_600,
        presenceQ: 1.2,
        presenceBoost: 0.28,
        rumbleHz: 115,
        rumbleLevelDb: -21,
        humHz: 98,
        humHarmonicsDb: SIMD8(0, -3, -7, -10, -14, -18, -23, -28),
        humPeakTNR: 7,
        humNoiseRatio: 3,
        humNoiseQ: 9,
        humNoiseDb: -10,
        bladeHz: 0,
        bladeDepth: 0,
        turbulence: 0.1,
        drift: 0.4,
        depthLowpassOctaves: 1.5,
        depthWhooshOctaves: 0.6,
        airflowWidthOctaves: 0.6
    )

    /// Dark, velvety low airflow; nearly no tonal motor.
    public static let deepDrift = SoundCharacter(
        airHighpassHz: 40,
        lowpassHz: 560,
        lowpassQ: 0.55,
        lowpassSpread: 2.6,
        whooshHz: 175,
        whooshQ: 0.55,
        whooshBoost: 0.7,
        presenceHz: 950,
        presenceQ: 0.6,
        presenceBoost: 0.14,
        rumbleHz: 52,
        rumbleLevelDb: -9,
        humHz: 46,
        humHarmonicsDb: SIMD8(0, -8, -16, -24, -32, -40, -48, -56),
        humPeakTNR: 7,
        turbulence: 0.05,
        drift: 0.7,
        depthLowpassOctaves: 1.6,
        depthWhooshOctaves: 0.7,
        depthRumbleDb: 6
    )
}
