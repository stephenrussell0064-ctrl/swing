import Foundation
import SwingCore

/// One ball, bowled at the player.
///
/// The player cannot see it. What they get is a count-in: five evenly spaced
/// beats, the last one accented, and contact on that last beat. The beat
/// is the player's own swing duration (see ``SwingProfile``), scaled by the
/// bowler: a quick bowler's beat is shorter, a spinner's longer.
public struct Delivery: Hashable, Sendable {

    public enum Bowler: String, Hashable, Sendable, CaseIterable {
        case fast, medium, spin

        /// How the player's own beat is scaled for this bowler.
        public var beatFactor: Double {
            switch self {
            case .fast: 0.85
            case .medium: 1.0
            case .spin: 1.2
            }
        }

        public var spoken: String {
            switch self {
            case .fast: "fast bowler"
            case .medium: "medium pacer"
            case .spin: "spinner"
            }
        }
    }

    public enum Length: String, Hashable, Sendable, CaseIterable {
        case short, good, full, yorker, fullToss

        /// For the screen and the voice.
        public var spoken: String {
            switch self {
            case .short: "short"
            case .good: "good length"
            case .full: "full"
            case .yorker: "yorker"
            case .fullToss: "full toss"
            }
        }
    }

    public var bowler: Bowler
    /// Metres from middle stump at the batter, positive toward the batter's
    /// off side. Stumps are 0.23 m wide; anything within ±0.15 hits them.
    public var line: Double
    public var length: Length
    /// m/s at release. Fast 35–40, medium 28–33, spin 18–24. Affects how hard
    /// the ball comes off the bat; the *timing* is the beat.
    public var pace: Double

    public init(bowler: Bowler, line: Double, length: Length, pace: Double) {
        self.bowler = bowler
        self.line = line
        self.length = length
        self.pace = pace
    }

    /// Distance from the bowler's hand to the bat, metres. A 20.12 m pitch,
    /// less the bowler's stride and the batter's stance.
    static let flightDistance = 17.5

    /// Beats in the count-in, including the accented hit beat. Five, always:
    /// four to hear the interval, and the fifth is the ball.
    public static let beats = 5

    public func beat(for profile: SwingProfile) -> TimeInterval {
        profile.beat(scaledBy: bowler.beatFactor)
    }

    public func tolerance(for profile: SwingProfile) -> TimeInterval {
        HapticVocabulary.tolerance(forBeat: beat(for: profile))
    }

    public var isStraight: Bool { abs(line) <= 0.15 }

    /// Wide enough that the umpire calls it: no shot needed, one run to you.
    public var isWide: Bool { abs(line) > 0.95 }

    /// What the hand feels between "here it comes" and the moment to swing.
    public func script(for profile: SwingProfile) -> HapticScript {
        HapticScript.countIn(beats: Delivery.beats, interval: beat(for: profile))
    }

    /// The ball to learn the grid on: medium pace, straight, good length.
    public static let practice = Delivery(bowler: .medium, line: 0, length: .good, pace: 30)
}

extension Delivery {
    /// The over the phone bowls at you. Deterministic from the seed, so the
    /// same match can be replayed and the same ball can be argued about.
    public static func generated(ballIndex: Int, seed: UInt64) -> Delivery {
        let luck = Luck(seed: seed)
        let a = luck.draw(ballIndex, stream: 1)
        let b = luck.draw(ballIndex, stream: 2)
        let c = luck.draw(ballIndex, stream: 3)

        let bowler: Bowler = a < 0.45 ? .fast : (a < 0.75 ? .medium : .spin)
        let pace: Double
        switch bowler {
        case .fast: pace = 34 + b * 6
        case .medium: pace = 28 + b * 5
        case .spin: pace = 18 + b * 6
        }
        let length: Length
        switch c {
        case ..<0.20: length = .short
        case ..<0.65: length = .good
        case ..<0.88: length = .full
        case ..<0.97: length = .yorker
        default: length = .fullToss
        }
        // Mostly at or around the stumps, occasionally straying.
        let lineDraw = luck.draw(ballIndex, stream: 4)
        let line = (lineDraw - 0.5) * 1.4
        return Delivery(bowler: bowler, line: line, length: length, pace: pace)
    }
}
