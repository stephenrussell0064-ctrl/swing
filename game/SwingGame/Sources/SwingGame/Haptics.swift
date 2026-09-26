import Foundation

/// One thing the hand feels. Data, not a call into Core Haptics — the app
/// target turns these into `CHHapticEvent`s (and into clicks through the
/// speaker). Keeping the vocabulary here means a whole delivery or rally can
/// be tested as a list of numbers.
public enum HapticEvent: Hashable, Sendable {
    /// A single transient click. `intensity` and `sharpness` are 0...1, as
    /// Core Haptics defines them.
    case tap(intensity: Double, sharpness: Double)
    /// A continuous buzz for `duration` seconds, ramping from `from` to `to`
    /// intensity. Used for outcomes, never for timing — a rumble has no edge
    /// to time against.
    case rumble(duration: TimeInterval, from: Double, to: Double)
}

/// A timed sequence of haptic events, relative to the script's own start.
///
/// The player cannot look at the phone while holding it, so this is the game's
/// entire way of saying *when*. Every incoming ball is a script that ends one
/// beat before the moment the player is meant to make contact.
public struct HapticScript: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public var at: TimeInterval
        public var event: HapticEvent

        public init(at: TimeInterval, event: HapticEvent) {
            self.at = at
            self.event = event
        }
    }

    public var entries: [Entry]
    /// When, relative to the script's start, contact is meant to happen.
    ///
    /// The script is a count-in on an even grid — beat, beat, beat, beat,
    /// **HIT** — and contact is *on* the last, accented beat. The player
    /// starts the swing on the fourth beat so the bat arrives as the fifth
    /// lands. A version with contact one silent beat after the last cue was
    /// tried and rejected: people want to hit the buzz, not the gap after it.
    public var contactAt: TimeInterval

    public init(entries: [Entry], contactAt: TimeInterval) {
        self.entries = entries.sorted { $0.at < $1.at }
        self.contactAt = contactAt
    }

    public var duration: TimeInterval {
        entries.map { entry in
            switch entry.event {
            case .tap: entry.at
            case .rumble(let d, _, _): entry.at + d
            }
        }.max() ?? 0
    }

    /// A count-in: `beats` evenly spaced clicks starting at `start`, the last
    /// one accented, and contact **on** that last beat.
    public static func countIn(
        beats: Int,
        interval: TimeInterval,
        startingAt start: TimeInterval = 0,
        leadIn: [Entry] = []
    ) -> HapticScript {
        precondition(beats >= 2)
        var entries = leadIn
        for i in 0..<beats {
            let last = i == beats - 1
            entries.append(.init(at: start + Double(i) * interval, event: last ? HapticVocabulary.accent : HapticVocabulary.beat))
        }
        return HapticScript(entries: entries, contactAt: start + Double(beats - 1) * interval)
    }
}

// MARK: - The shared vocabulary

/// Cues every sport reuses. A player who has learned the count-in in cricket
/// should find it means the same in tennis.
public enum HapticVocabulary {
    /// One beat of the count-in. Strong: the hand is gripping and about to
    /// move, and a faint tick is a tick it does not feel.
    public static let beat = HapticEvent.tap(intensity: 0.9, sharpness: 0.6)
    /// The hit beat. Contact is on this one.
    public static let accent = HapticEvent.tap(intensity: 1.0, sharpness: 1.0)
    /// A quiet tick outside the grid: a side call, a ready signal. Softer so
    /// it is never mistaken for a beat.
    public static let tick = HapticEvent.tap(intensity: 0.5, sharpness: 0.3)

    /// Outcome: you hit it cleanly. Crisp and short.
    public static let cleanStrike = HapticScript(
        entries: [.init(at: 0, event: .tap(intensity: 1.0, sharpness: 0.9))],
        contactAt: 0
    )
    /// Outcome: you got something on it, but not the middle.
    public static let mishit = HapticScript(
        entries: [
            .init(at: 0, event: .tap(intensity: 0.7, sharpness: 0.2)),
            .init(at: 0.06, event: .rumble(duration: 0.18, from: 0.5, to: 0.1)),
        ],
        contactAt: 0
    )
    /// Outcome: you missed. A low, long buzz the hand cannot mistake for a hit.
    public static let miss = HapticScript(
        entries: [.init(at: 0, event: .rumble(duration: 0.45, from: 0.4, to: 0.4))],
        contactAt: 0
    )
    /// Outcome: something good happened that is bigger than one hit — a
    /// boundary, a winner, a wicket when bowling.
    public static let celebration = HapticScript(
        entries: [
            .init(at: 0.00, event: .tap(intensity: 0.8, sharpness: 0.8)),
            .init(at: 0.12, event: .tap(intensity: 0.9, sharpness: 0.8)),
            .init(at: 0.24, event: .tap(intensity: 1.0, sharpness: 0.9)),
        ],
        contactAt: 0
    )

    /// The timing window for a grid of `interval`. A third of a beat either
    /// side, clamped so a spinner's slow count is not a free hit and a quick's
    /// is still humanly possible.
    public static func tolerance(forBeat interval: TimeInterval) -> TimeInterval {
        (interval * 0.33).clamped(to: 0.14...0.24)
    }
}
