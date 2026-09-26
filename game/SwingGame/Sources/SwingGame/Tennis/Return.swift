import Foundation
import SwingCore

/// Where your ball landed on the far side, if it did.
public struct Placement: Hashable, Sendable {
    /// Metres from the centre line, positive to your right.
    public var lateral: Double
    /// 0 at the net, 1 on their baseline.
    public var depth: Double
    /// m/s off your racket.
    public var speed: Double
    /// How good a shot it was for the opponent to deal with, 0...1.
    public var quality: Double
}

public enum StrokeOutcome: Hashable, Sendable {
    /// Swung and missed, or did not swing.
    case miss
    case net
    case outLong
    case outWide
    case inPlay(Placement)

    public var isIn: Bool {
        if case .inPlay = self { return true }
        return false
    }
}

public struct StrokeResult: Hashable, Sendable {
    public var outcome: StrokeOutcome
    public var timing: Timing?
    public var announcement: String
    public var haptic: HapticScript
}

/// Racket meets ball. Pure.
///
/// Depth is **power**: how hard you swung, as a fraction of a full swing.
/// A gentle swing drops it short, a full one lands on the baseline, and only
/// swinging *past* full capacity puts it long. The racket-face angle nudges
/// that and a steep downward face finds the net; it does not decide depth on
/// its own, because the face angle a phone reports mid-swing is the least
/// reliable thing it knows, and the first version sent every ball long on it.
///
/// Line is forgiving for the same reason: it takes forty-five degrees off the
/// target line to go wide.
public enum Stroke {

    /// Hand speed, m/s, that counts as a full swing. About 22 rad/s with a
    /// phone at arm's length: a proper hit, not a waggle.
    static let fullSwingSpeed = 13.0
    /// A serve is hit harder; the box is shorter.
    static let fullServeSpeed = 16.0
    /// Power below this drops into the net; above the upper bound is long.
    static let netPower = 0.22
    static let longPower = 1.05
    /// Degrees of face elevation per unit of power. Fifteen degrees up adds
    /// about a seventh of a swing's worth of depth — a nudge, not a decision.
    static let elevationPerPower = 100.0
    /// A face steeper than this downward goes into the net regardless.
    static let netFace = -28.0
    /// Degrees of yaw for a ball to reach the sideline.
    static let yawToSideline = 45.0
    /// Metres of lateral steer per unit of timing error. Early on a forehand
    /// goes cross-court, late goes down the line.
    static let steerPerTolerance = 1.0
    /// Ball speed off a full swing, m/s. For the opponent's difficulty and
    /// the screen, not for where it lands.
    static let racketToBall = 1.4

    public static func returnBall(
        shot: Shot?,
        ball: IncomingBall,
        cue: Cue,
        handedness: Handedness = .right
    ) -> StrokeResult {
        guard let shot else {
            return StrokeResult(outcome: .miss, timing: nil, announcement: "Let it go.", haptic: HapticVocabulary.miss)
        }
        let timing = cue.timing(of: shot)
        if timing.missed {
            let words = timing.grade == .tooEarly ? "Too early. Missed it." : "Too late. Missed it."
            return StrokeResult(outcome: .miss, timing: timing, announcement: words, haptic: HapticVocabulary.miss)
        }

        // Make "dominant side" positive so a left-hander plays the same game.
        let s = handedness.asRightHanded(shot)

        // Note what is *not* checked: whether the swing was a forehand or a
        // backhand. The direction of travel cannot tell them apart from an
        // angled shot. `Shot.attitude` probably can, once there are recorded
        // forehands and backhands to look at.

        // Forehand early → toward the non-dominant side (cross-court), late →
        // dominant side (down the line). Backhand is mirrored.
        let sideSign = ball.side == .forehand ? 1.0 : -1.0
        let steer = (timing.error / timing.tolerance) * steerPerTolerance * sideSign

        let power = power(of: s, timing: timing, full: fullSwingSpeed)
        return land(shot: s, power: power, steer: steer, timing: timing, boxOnly: false)
    }

    /// Your serve. Must land in the far service box.
    public static func serve(shot: Shot?, cue: Cue, handedness: Handedness = .right) -> StrokeResult {
        guard let shot else {
            return StrokeResult(outcome: .miss, timing: nil, announcement: "Missed the toss. Fault.", haptic: HapticVocabulary.miss)
        }
        let timing = cue.timing(of: shot)
        if timing.missed {
            return StrokeResult(outcome: .miss, timing: timing, announcement: "Missed the toss. Fault.", haptic: HapticVocabulary.miss)
        }
        let s = handedness.asRightHanded(shot)
        let power = power(of: s, timing: timing, full: fullServeSpeed)
        var result = land(shot: s, power: power, steer: 0, timing: timing, boxOnly: true)
        switch result.outcome {
        case .outLong: result.announcement = "Long. Fault."
        case .outWide: result.announcement = "Wide. Fault."
        case .net: result.announcement = "Net. Fault."
        case .inPlay(let p) where p.quality > 0.85: result.announcement = "Big serve."
        case .inPlay: result.announcement = "Good serve."
        case .miss: break
        }
        return result
    }

    // MARK: -

    /// How much of a full swing this was, after timing, face angle and spin.
    private static func power(of shot: Shot, timing: Timing, full: Double) -> Double {
        // A mistimed hit is a weaker hit.
        let swing = (shot.releaseSpeed / full) * (0.6 + 0.4 * timing.quality)
        let face = shot.direction.elevation.degrees / elevationPerPower
        // Topspin dips, so the same swing lands shorter; slice floats it.
        let spin = 1 - 0.35 * Ballistics.topspin(of: shot)
        return max(0, (swing + face) * spin)
    }

    private static func land(shot: Shot, power: Double, steer: Double, timing: Timing, boxOnly: Bool) -> StrokeResult {
        if shot.direction.elevation.degrees < netFace || power < netPower {
            return StrokeResult(outcome: .net, timing: timing, announcement: "Into the net.", haptic: HapticVocabulary.mishit)
        }
        if power > longPower {
            return StrokeResult(outcome: .outLong, timing: timing, announcement: "Long.", haptic: HapticVocabulary.mishit)
        }

        let yaw = (shot.direction.horizontalAngle ?? 0).degrees
        let lateral = (yaw / yawToSideline).clamped(to: -1...1) * IncomingBall.halfWidth * 1.1 + steer
        if abs(lateral) > IncomingBall.halfWidth {
            return StrokeResult(outcome: .outWide, timing: timing, announcement: "Wide.", haptic: HapticVocabulary.mishit)
        }

        // 0 at the net, 1 at the far edge of the target area.
        let reach = (power - netPower) / (longPower - netPower)
        // A serve's target is the service box, which ends 6.4 m past the net
        // on an 11.9 m half.
        let depth = boxOnly ? reach * (6.4 / IncomingBall.netDistance) : reach
        let exitSpeed = shot.releaseSpeed * racketToBall

        // Deep and hard is difficult; short and soft is a gift.
        let quality = (timing.quality * (0.5 + 0.5 * reach) * (0.6 + 0.4 * min(power, 1))).clamped(to: 0...1)

        let placement = Placement(lateral: lateral, depth: depth, speed: exitSpeed, quality: quality)
        let words: String
        switch quality {
        case 0.8...: words = "Great shot."
        case 0.5...: words = "In."
        default: words = "In, but short."
        }
        return StrokeResult(
            outcome: .inPlay(placement),
            timing: timing,
            announcement: words,
            haptic: quality < 0.35 ? HapticVocabulary.mishit : HapticVocabulary.cleanStrike
        )
    }
}
