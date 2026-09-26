import Foundation
import Testing
import SwingCore
@testable import SwingGame

@Suite("Cricket bowling")
struct BowlingTests {

    /// Overarm, straight at the stumps, released a little downward.
    func bowl(speed: Double = 12, elevation: Double = -10, yaw: Double = 0, spin: Double = 0, spinAxis: Vector3 = Vector3(0, 1, 0), kind: Shot.Kind = .swing) -> Shot {
        let e = elevation.radians, y = yaw.radians
        return TestShots.straightSwing(
            speed: speed,
            direction: Vector3(cos(e) * cos(y), sin(e), cos(e) * sin(y)),
            spinAxis: spinAxis,
            spinRate: spin,
            kind: kind
        )
    }

    @Test("a roll is not a bowl: no ball")
    func rollIsNoBall() {
        #expect(Bowling.ball(from: bowl(kind: .roll)) == nil)
        let r = Bowling.face(nil, ballIndex: 0, seed: 1)
        #expect(r.outcome == .noBall)
        #expect(r.outcome.runsConceded == 1)
        #expect(!r.outcome.countsAsBall)
    }

    @Test("hand speed becomes ball speed, within cricket's range")
    func pace() {
        #expect(Bowling.ball(from: bowl(speed: 13))!.pace == 13 * Bowling.handToBall)
        #expect(Bowling.ball(from: bowl(speed: 40))!.pace == 42)
        #expect(Bowling.ball(from: bowl(speed: 1))!.pace == 14)
    }

    @Test("release angle sets the length")
    func length() {
        #expect(Bowling.ball(from: bowl(elevation: -30))!.length == .short)
        #expect(Bowling.ball(from: bowl(elevation: -10))!.length == .good)
        #expect(Bowling.ball(from: bowl(elevation: 5))!.length == .full)
        #expect(Bowling.ball(from: bowl(elevation: 20))!.length == .yorker)
        #expect(Bowling.ball(from: bowl(elevation: 35))!.length == .fullToss)
    }

    @Test("straight at the calibrated line is middle stump; yawing off it drifts the line")
    func line() {
        #expect(Bowling.ball(from: bowl())!.isStraight)
        #expect(Bowling.ball(from: bowl(yaw: 5))!.isStraight)
        let drift = Bowling.ball(from: bowl(yaw: 20))!
        #expect(!drift.isStraight)
        #expect(!drift.isWide)
        let wide = Bowling.ball(from: bowl(yaw: 65))!
        #expect(wide.isWide)
        #expect(Bowling.face(wide, ballIndex: 0, seed: 1).outcome == .wide)
    }

    @Test("yawing toward the bowler's right is the right-handed batter's leg side")
    func lineSide() {
        // +z in the play frame is the bowler's right; the batter faces the
        // other way, so that is their leg side, and "off side" is negative.
        #expect(Bowling.ball(from: bowl(yaw: 2))!.line < 0)
        #expect(Bowling.ball(from: bowl(yaw: -2))!.line > 0)
    }

    @Test("fast rotation about a vertical axis is spin, and it moves the line")
    func spin() {
        let flat = Bowling.ball(from: bowl())!
        let spun = Bowling.ball(from: bowl(spin: 20, spinAxis: Vector3(0, 1, 0)))!
        #expect(!flat.isSpin)
        #expect(spun.isSpin)
        #expect(spun.turn != 0)
        #expect(spun.line == flat.line + spun.turn)
        // Wrist rotation about the direction of travel is not spin bowling.
        let rifled = Bowling.ball(from: bowl(spin: 20, spinAxis: Vector3(1, 0, 0)))!
        #expect(!rifled.isSpin)
    }

    @Test("a full toss always goes to the boundary")
    func fullToss() {
        let ball = Bowling.ball(from: bowl(elevation: 35))!
        for i in 0..<20 {
            let o = Bowling.face(ball, ballIndex: i, seed: 99).outcome
            #expect(o == .four || o == .six)
        }
    }

    @Test("the same ball, index and seed always produce the same outcome")
    func deterministic() {
        let ball = Bowling.ball(from: bowl())!
        let a = Bowling.face(ball, ballIndex: 3, seed: 42)
        let b = Bowling.face(ball, ballIndex: 3, seed: 42)
        #expect(a == b)
    }

    @Test("over a long spell, good-length bowling takes wickets and concedes less than full tosses")
    func goodLengthPays() {
        let good = Bowling.ball(from: bowl(speed: 14, elevation: -10))!
        let tosses = Bowling.ball(from: bowl(speed: 14, elevation: 35))!
        var goodRuns = 0, goodWickets = 0, tossRuns = 0
        for i in 0..<120 {
            let g = Bowling.face(good, ballIndex: i, seed: 7).outcome
            goodRuns += g.runsConceded
            if g.isWicket { goodWickets += 1 }
            tossRuns += Bowling.face(tosses, ballIndex: i, seed: 7).outcome.runsConceded
        }
        #expect(goodWickets > 0)
        #expect(goodRuns < tossRuns / 2)
    }
}

@Suite("Cricket match")
struct CricketMatchTests {

    @Test("deliveries are deterministic per seed and never repeat within an over")
    func deliveries() {
        let m = CricketMatch(seed: 1)
        let a = m.nextDelivery()
        let b = CricketMatch(seed: 1).nextDelivery()
        #expect(a == b)
        let over = (0..<6).map { Delivery.generated(ballIndex: $0, seed: 1) }
        #expect(Set(over).count == 6)
    }

    @Test("an over of dots turns the innings over to bowling")
    func inningsTurns() {
        var m = CricketMatch(oversPerSide: 1)
        let dot = BattingResult(outcome: .dot, contact: .missed, timing: nil, flight: nil, announcement: "", haptic: HapticVocabulary.miss)
        for _ in 0..<5 {
            m.record(dot)
            #expect(m.phase == .batting)
        }
        m.record(dot)
        #expect(m.phase == .bowling)
        #expect(m.yours.balls == 6)
    }

    @Test("a wide does not count as a ball faced but adds a run")
    func wides() {
        var m = CricketMatch(oversPerSide: 1)
        m.record(BattingResult(outcome: .wide, contact: .noShot, timing: nil, flight: nil, announcement: "", haptic: HapticVocabulary.miss))
        #expect(m.yours.balls == 0)
        #expect(m.yours.runs == 1)
        #expect(m.yours.extras == 1)
    }

    @Test("losing all your wickets ends the innings early")
    func allOut() {
        var m = CricketMatch(oversPerSide: 2, wicketsPerSide: 2)
        let out = BattingResult(outcome: .bowled, contact: .missed, timing: nil, flight: nil, announcement: "", haptic: HapticVocabulary.miss)
        m.record(out)
        #expect(m.phase == .batting)
        m.record(out)
        #expect(m.phase == .bowling)
    }

    @Test("the chase ends the moment they pass you, and the result says so")
    func chase() {
        var m = CricketMatch(oversPerSide: 1)
        m.record(BattingResult(outcome: .four, contact: .middled, timing: nil, flight: nil, announcement: "", haptic: HapticVocabulary.celebration))
        for _ in 0..<5 {
            m.record(BattingResult(outcome: .dot, contact: .missed, timing: nil, flight: nil, announcement: "", haptic: HapticVocabulary.miss))
        }
        #expect(m.phase == .bowling)
        m.record(BowlingResult(ball: nil, outcome: .four, announcement: "", haptic: HapticVocabulary.miss))
        #expect(m.phase == .bowling)
        m.record(BowlingResult(ball: nil, outcome: .runs(1), announcement: "", haptic: HapticVocabulary.miss))
        #expect(m.phase == .finished)
        #expect(m.result == .theyWon(wicketsInHand: 3))
    }

    @Test("bowl them out for less and you win by the difference")
    func defend() {
        var m = CricketMatch(oversPerSide: 1, wicketsPerSide: 1)
        m.record(BattingResult(outcome: .runs(2), contact: .middled, timing: nil, flight: nil, announcement: "", haptic: HapticVocabulary.cleanStrike))
        m.record(BattingResult(outcome: .bowled, contact: .missed, timing: nil, flight: nil, announcement: "", haptic: HapticVocabulary.miss))
        #expect(m.phase == .bowling)
        m.record(BowlingResult(ball: nil, outcome: .bowled, announcement: "", haptic: HapticVocabulary.celebration))
        #expect(m.result == .youWon(by: 2))
        #expect(m.scoreAnnouncement == "You won by 2 runs.")
    }
}
