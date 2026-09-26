import Foundation
import SwingCore

/// A ball the player has bowled, read off their arm.
public struct Ball: Hashable, Sendable {
    /// Metres from middle stump at the batter, positive to the batter's off
    /// side. Includes any turn or swing.
    public var line: Double
    public var length: Delivery.Length
    /// m/s. What the phone in the hand becomes when it is a cricket ball.
    public var pace: Double
    /// Lateral movement after pitching, metres. Positive away from a
    /// right-hander (off-spin from a right-arm bowler goes the other way).
    public var turn: Double
    public var isSpin: Bool

    public var isWide: Bool { abs(line) > 0.95 }
    public var isStraight: Bool { abs(line) <= 0.15 }
}

public enum BowlingOutcome: Hashable, Sendable {
    case wide
    case noBall
    case dot
    case runs(Int)
    case four
    case six
    case bowled
    case caught(by: String)

    public var runsConceded: Int {
        switch self {
        case .wide, .noBall: 1
        case .runs(let n): n
        case .four: 4
        case .six: 6
        case .dot, .bowled, .caught: 0
        }
    }

    public var isWicket: Bool {
        switch self {
        case .bowled, .caught: true
        default: false
        }
    }

    public var countsAsBall: Bool {
        switch self {
        case .wide, .noBall: false
        default: true
        }
    }
}

public struct BowlingResult: Hashable, Sendable {
    public var ball: Ball?
    public var outcome: BowlingOutcome
    public var announcement: String
    public var haptic: HapticScript
}

/// The batter the phone plays when you bowl. Skill 0...1.
public struct Batter: Hashable, Sendable {
    public var skill: Double
    public init(skill: Double) { self.skill = skill.clamped(to: 0...1) }

    public static let club = Batter(skill: 0.45)
    public static let county = Batter(skill: 0.7)
}

/// Arm meets air. What comes out of the hand, and what the batter does with it.
public enum Bowling {

    /// Hand speed with a phone in it to ball speed. A real fast bowler's hand
    /// is doing about 30 m/s at release; a person swinging a phone in a
    /// garden manages perhaps a third of that and should still get to bowl
    /// quick.
    static let handToBall = 2.6
    /// Batter-to-stumps distance the line is projected over.
    static let projection = Delivery.flightDistance

    /// What the player bowled. `nil` when the motion was not a bowl at all —
    /// a roll, say — which the game calls a no-ball rather than guessing.
    ///
    /// No handedness here, deliberately. The bowler's arm does not change
    /// where the batter's off side is, and the spin the phone measures is the
    /// spin the ball has, whichever hand put it there. (The *batter's*
    /// handedness would flip the line; the phone's batter is right-handed.)
    public static func ball(from shot: Shot) -> Ball? {
        guard shot.kind == .swing || shot.kind == .throw else { return nil }

        let pace = (shot.releaseSpeed * handToBall).clamped(to: 14...42)

        // Line, from the release direction's yaw off the calibrated line.
        // Deliberately forgiving: a hand a few degrees off is still at the
        // stumps, and it takes sixty degrees to bowl a wide. A real bowler
        // corrects line by feel over many balls; a person with a phone gets
        // one go and no run-up, and the first version made every ball wide.
        // The bowler's right (+z) is the right-handed batter's leg side, so
        // "off side positive" is the negative of it.
        let yaw = (shot.direction.horizontalAngle ?? 0).degrees
        var line = -(yaw / 60).clamped(to: -1...1) * 1.0

        // Length from the release angle, in wide bands centred on a good
        // length, so most balls land somewhere a batter has to play.
        let elevation = shot.direction.elevation.degrees
        let length: Delivery.Length
        switch elevation {
        case 30...: length = .fullToss
        case 12..<30: length = .yorker
        case 0..<12: length = .full
        case -25..<0: length = .good
        default: length = .short
        }

        // Spin: fast rotation about a roughly vertical axis. Which way it
        // turns follows the sign of that rotation.
        let spinning = shot.spinRate > 10 && abs(shot.spinAxis.y) > 0.6
        var turn = 0.0
        if spinning {
            let amount = min(shot.spinRate / 30, 1) * 0.35
            turn = amount * (shot.spinAxis.y > 0 ? 1 : -1)
            line += turn
        }

        return Ball(line: line, length: length, pace: pace, turn: turn, isSpin: spinning)
    }

    /// The batter's reply. `ballIndex` and `seed` make the "luck" repeatable.
    public static func face(
        _ ball: Ball?,
        batter: Batter = .club,
        ballIndex: Int,
        seed: UInt64
    ) -> BowlingResult {
        guard let ball else {
            return BowlingResult(
                ball: nil, outcome: .noBall,
                announcement: "No ball. That wasn't a bowl.",
                haptic: HapticVocabulary.miss
            )
        }
        if ball.isWide {
            return BowlingResult(
                ball: ball, outcome: .wide,
                announcement: "Wide.",
                haptic: HapticVocabulary.mishit
            )
        }

        let luck = Luck(seed: seed).draw(ballIndex, stream: 7)
        let skill = batter.skill
        let quick = ball.pace >= 33
        let outcome: BowlingOutcome
        var words: String

        switch ball.length {
        case .fullToss:
            outcome = luck < 0.35 ? .six : .four
            words = outcome == .six ? "Full toss, and that's six." : "Full toss. Put away for four."

        case .yorker:
            if ball.isStraight, luck > skill * 0.9 {
                outcome = .bowled
                words = "Yorker! Bowled him!"
            } else if ball.isStraight {
                outcome = .dot
                words = "Dug out. Dot ball."
            } else {
                outcome = .runs(1)
                words = "Squeezed away for one."
            }

        case .full:
            if ball.isStraight, quick, luck > 0.88 {
                outcome = .bowled
                words = "Through the gate! Bowled!"
            } else if luck < 0.3 - skill * 0.2 {
                outcome = .runs(2)
                words = "Driven. Two runs."
            } else if luck > 0.6 + (1 - skill) * 0.3 {
                outcome = .four
                words = "Driven for four."
            } else {
                outcome = .runs(1)
                words = "Driven for one."
            }

        case .good:
            let tight = abs(ball.line) <= 0.3
            if tight, luck > 0.86 - (1 - skill) * 0.15 {
                outcome = .caught(by: "slip")
                words = ball.isSpin ? "Turned, edged, and caught!" : "Edged, caught at slip!"
            } else if ball.isStraight, quick, luck > 0.76, luck <= 0.86 {
                outcome = .bowled
                words = "Bowled him!"
            } else if ball.isSpin, ball.isStraight, luck > 0.7 {
                outcome = .bowled
                words = "Turned past the bat. Bowled!"
            } else if tight, luck < 0.55 {
                outcome = .dot
                words = "Good length. Dot ball."
            } else if luck < 0.8 {
                outcome = .runs(1)
                words = "Worked away for one."
            } else {
                outcome = .runs(2)
                words = "Two runs."
            }

        case .short:
            if abs(ball.line) <= 0.4 {
                if luck > 0.85 - (1 - skill) * 0.2 {
                    outcome = .caught(by: "deep midwicket")
                    words = "Pulled — caught in the deep!"
                } else if luck < 0.4 + skill * 0.2 {
                    outcome = .four
                    words = "Short, pulled for four."
                } else {
                    outcome = .runs(2)
                    words = "Pulled for two."
                }
            } else {
                outcome = luck < 0.5 ? .dot : .runs(1)
                words = outcome == .dot ? "Short and wide, left alone." : "Cut away for one."
            }
        }

        if ball.isSpin, !words.contains("Turned") {
            words = "Spinning. " + words
        }

        let haptic: HapticScript
        switch outcome {
        case .bowled, .caught: haptic = HapticVocabulary.celebration
        case .four, .six: haptic = HapticVocabulary.miss
        case .dot: haptic = HapticVocabulary.cleanStrike
        default: haptic = HapticVocabulary.tick.script
        }
        return BowlingResult(ball: ball, outcome: outcome, announcement: words, haptic: haptic)
    }
}
