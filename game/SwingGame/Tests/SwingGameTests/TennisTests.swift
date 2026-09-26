import Foundation
import Testing
import SwingCore
@testable import SwingGame

@Suite("Tennis strokes")
struct StrokeTests {

    let forehand = IncomingBall(side: .forehand, pace: 25, depth: 0.7)
    let backhand = IncomingBall(side: .backhand, pace: 25, depth: 0.7)

    /// A rally-ball swing: forward, a little up, slight cross-body drift.
    func swing(at offset: TimeInterval = 0, speed: Double = 11, up: Double = 0.12, across: Double = -0.1, spinAxis: Vector3 = Vector3(0, 0, 1), spinRate: Double = 2) -> Shot {
        TestShots.straightSwing(at: offset, speed: speed, direction: Vector3(1, up, across), spinAxis: spinAxis, spinRate: spinRate)
    }

    @Test("no swing lets the ball go")
    func noSwing() {
        let r = Stroke.returnBall(shot: nil, ball: forehand, cue: TestShots.cue())
        #expect(r.outcome == .miss)
    }

    @Test("a clean, on-time forehand lands in")
    func cleanReturn() {
        let r = Stroke.returnBall(shot: swing(), ball: forehand, cue: TestShots.cue())
        #expect(r.outcome.isIn)
        #expect(r.haptic == HapticVocabulary.cleanStrike)
    }

    @Test("far too late is a miss")
    func late() {
        let r = Stroke.returnBall(shot: swing(at: 0.3), ball: forehand, cue: TestShots.cue())
        #expect(r.outcome == .miss)
        #expect(r.announcement.hasPrefix("Too late"))
    }

    @Test("a steep downward face goes into the net, and so does a swing with nothing on it")
    func net() {
        #expect(Stroke.returnBall(shot: swing(up: -0.7), ball: forehand, cue: TestShots.cue()).outcome == .net)
        #expect(Stroke.returnBall(shot: swing(speed: 1.5, up: 0), ball: forehand, cue: TestShots.cue()).outcome == .net)
    }

    @Test("depth is power: a soft swing is short, a full one is deep, only past full is long")
    func depthIsPower() {
        func depth(_ speed: Double) -> Double? {
            if case .inPlay(let p) = Stroke.returnBall(shot: swing(speed: speed, up: 0), ball: forehand, cue: TestShots.cue()).outcome { return p.depth }
            return nil
        }
        let soft = depth(6), medium = depth(9), full = depth(Stroke.fullSwingSpeed)
        #expect(soft != nil && medium != nil && full != nil)
        #expect(soft! < medium! && medium! < full!)
        #expect(full! > 0.85)
        #expect(Stroke.returnBall(shot: swing(speed: Stroke.fullSwingSpeed * 1.25, up: 0), ball: forehand, cue: TestShots.cue()).outcome == .outLong)
    }

    @Test("swung too hard and high goes long")
    func long() {
        let r = Stroke.returnBall(shot: swing(speed: 22, up: 0.3), ball: forehand, cue: TestShots.cue())
        #expect(r.outcome == .outLong)
    }

    @Test("topspin lets the same hard swing stay in")
    func topspinKeepsItIn() {
        // Topspin: rotation about the horizontal axis perpendicular to travel,
        // such that ω × v points down. Travel is +x; ω about −z gives (−z)×(x) = −y.
        let flat = Stroke.returnBall(shot: swing(speed: 17, up: 0.2), ball: forehand, cue: TestShots.cue())
        let spun = Stroke.returnBall(shot: swing(speed: 17, up: 0.2, spinAxis: Vector3(0, 0, -1), spinRate: 25), ball: forehand, cue: TestShots.cue())
        #expect(flat.outcome == .outLong)
        #expect(spun.outcome.isIn)
    }

    @Test("Magnus sign: ω about −z with travel +x is topspin, +z is backspin")
    func magnusSign() {
        let top = swing(spinAxis: Vector3(0, 0, -1), spinRate: 25)
        let back = swing(spinAxis: Vector3(0, 0, 1), spinRate: 25)
        #expect(Ballistics.topspin(of: top) > 0.5)
        #expect(Ballistics.topspin(of: back) < -0.5)
    }

    @Test("it takes forty-five degrees off the line to go wide; thirty is still in")
    func wide() {
        #expect(Stroke.returnBall(shot: swing(across: 1.5), ball: forehand, cue: TestShots.cue()).outcome == .outWide)
        #expect(Stroke.returnBall(shot: swing(across: 0.55), ball: forehand, cue: TestShots.cue()).outcome.isIn)
    }

    @Test("early on a forehand goes cross-court, late goes down the line")
    func steer() {
        let early = Stroke.returnBall(shot: swing(at: -0.05, across: 0), ball: forehand, cue: TestShots.cue())
        let late = Stroke.returnBall(shot: swing(at: 0.05, across: 0), ball: forehand, cue: TestShots.cue())
        guard case .inPlay(let e) = early.outcome, case .inPlay(let l) = late.outcome else {
            Issue.record("expected both in: \(early.outcome) \(late.outcome)"); return
        }
        #expect(e.lateral < 0)
        #expect(l.lateral > 0)
    }

    @Test("the backhand mirrors the forehand's steer")
    func backhandMirror() {
        let fh = Stroke.returnBall(shot: swing(at: -0.05, across: 0), ball: forehand, cue: TestShots.cue())
        let bh = Stroke.returnBall(shot: swing(at: -0.05, across: 0), ball: backhand, cue: TestShots.cue())
        guard case .inPlay(let f) = fh.outcome, case .inPlay(let b) = bh.outcome else {
            Issue.record("expected both in"); return
        }
        #expect(abs(f.lateral + b.lateral) < 1e-9)
    }

    @Test("a deep, fast, on-time ball is a better shot than a short soft one")
    func quality() {
        let strong = Stroke.returnBall(shot: swing(speed: 11, up: 0.15), ball: forehand, cue: TestShots.cue())
        let weak = Stroke.returnBall(shot: swing(at: 0.07, speed: 7, up: 0.15), ball: forehand, cue: TestShots.cue())
        guard case .inPlay(let s) = strong.outcome, case .inPlay(let w) = weak.outcome else {
            Issue.record("expected both in: \(strong.outcome) \(weak.outcome)"); return
        }
        #expect(s.quality > w.quality)
        #expect(s.depth > w.depth)
        #expect(weak.announcement == "In, but short.")
    }

    @Test("a left-hander's forehand is a mirror image")
    func handedness() {
        let shot = swing(across: -0.15)
        let r = Stroke.returnBall(shot: shot, ball: forehand, cue: TestShots.cue(), handedness: .right)
        let l = Stroke.returnBall(shot: shot, ball: forehand, cue: TestShots.cue(), handedness: .left)
        guard case .inPlay(let rp) = r.outcome else { Issue.record("right not in: \(r.outcome)"); return }
        guard case .inPlay(let lp) = l.outcome else { Issue.record("left not in: \(l.outcome)"); return }
        #expect(abs(rp.lateral + lp.lateral) < 1e-9)
    }

    @Test("a serve must land in the service box")
    func serve() {
        // Hit downward from 2.5 m, hard: the box is 6.4 m past the net.
        let good = Stroke.serve(shot: swing(speed: 14, up: -0.08), cue: TestShots.cue(tolerance: Serve.tolerance(for: .default)))
        #expect(good.outcome.isIn, "\(good.outcome)")
        let long = Stroke.serve(shot: swing(speed: 17, up: 0.25), cue: TestShots.cue(tolerance: Serve.tolerance(for: .default)))
        #expect(long.outcome == .outLong)
        #expect(long.announcement == "Long. Fault.")
        let netted = Stroke.serve(shot: swing(speed: 14, up: -0.6), cue: TestShots.cue(tolerance: Serve.tolerance(for: .default)))
        #expect(netted.outcome == .net)
    }
}

@Suite("Tennis scoring")
struct TennisScoreTests {

    @Test("love, fifteen, thirty, forty, game")
    func basic() {
        var s = TennisScore(server: .you, gamesToWin: 6)
        #expect(s.pointAnnouncement == "Love all.")
        s.point(to: .you)
        #expect(s.pointAnnouncement == "Fifteen, love.")
        s.point(to: .opponent)
        #expect(s.pointAnnouncement == "Fifteen all.")
        s.point(to: .you); s.point(to: .you)
        #expect(s.pointAnnouncement == "Forty, fifteen.")
        #expect(s.point(to: .you) == .game(.you))
        #expect(s.games[.you] == 1)
        #expect(s.server == .opponent)
    }

    @Test("deuce and advantage")
    func deuce() {
        var s = TennisScore()
        for _ in 0..<3 { s.point(to: .you); s.point(to: .opponent) }
        #expect(s.pointAnnouncement == "Deuce.")
        s.point(to: .opponent)
        #expect(s.pointAnnouncement == "Advantage them.")
        s.point(to: .you)
        #expect(s.pointAnnouncement == "Deuce.")
        s.point(to: .you)
        #expect(s.pointAnnouncement == "Advantage you.")
        #expect(s.point(to: .you) == .game(.you))
    }

    @Test("a set needs the games and a two-game margin, or seven")
    func set() {
        var s = TennisScore(gamesToWin: 6)
        func game(_ p: Player) { for _ in 0..<4 { if !s.isOver { s.point(to: p) } } }
        for _ in 0..<5 { game(.you); game(.opponent) }
        #expect(s.games == [.you: 5, .opponent: 5])
        game(.you)
        #expect(!s.isOver)
        game(.you)
        #expect(s.winner == .you)
    }

    @Test("seven–six ends it without a tiebreak, for now")
    func sevenSix() {
        var s = TennisScore(gamesToWin: 6)
        func game(_ p: Player) { for _ in 0..<4 { if !s.isOver { s.point(to: p) } } }
        for _ in 0..<6 { game(.you); game(.opponent) }
        game(.you)
        #expect(s.winner == .you)
    }
}

@Suite("Tennis match")
struct TennisMatchTests {

    func swing(at offset: TimeInterval = 0, speed: Double = 11) -> Shot {
        TestShots.straightSwing(at: offset, speed: speed, direction: Vector3(1, 0.12, -0.1))
    }

    @Test("it opens on your serve when you serve, and their serve when they do")
    func opening() {
        let you = TennisMatch(server: .you)
        #expect(you.state == .yourServe(second: false))
        #expect(you.prompt == "Your serve.")
        let them = TennisMatch(server: .opponent)
        if case .incoming(let ball, 0) = them.state {
            #expect(ball.isServe)
        } else {
            Issue.record("expected an incoming serve")
        }
    }

    @Test("a fault gives a second serve; two faults lose the point")
    func doubleFault() {
        var m = TennisMatch(server: .you)
        let cue = TestShots.cue(tolerance: Serve.tolerance(for: .default))
        let first = m.play(nil, cue: cue)
        #expect(m.state == .yourServe(second: true))
        #expect(first.event == nil)
        let second = m.play(nil, cue: cue)
        #expect(second.event == .point)
        #expect(second.stroke.announcement.hasSuffix("Double fault."))
        #expect(m.score.points[.opponent] == 1)
        #expect(second.announcement == "Love, fifteen.")
    }

    @Test("missing their ball loses the point and the next serve is set up")
    func missLosesPoint() {
        var m = TennisMatch(server: .opponent)
        let step = m.play(nil, cue: TestShots.cue())
        #expect(step.event == .point)
        #expect(!step.rallyContinues)
        if case .incoming(let ball, _) = m.state {
            #expect(ball.isServe)
        } else {
            Issue.record("they should still be serving")
        }
    }

    @Test("a rally: your ball in play brings a reply or wins the point")
    func rally() {
        var m = TennisMatch(server: .opponent)
        var strokes = 0
        while case .incoming(let ball, _) = m.state, strokes < 50 {
            let cue = Cue(contactTime: TestShots.contactTime, tolerance: ball.tolerance(for: .default))
            let step = m.play(swing(), cue: cue)
            strokes += 1
            if !step.rallyContinues {
                #expect(step.event != nil)
                break
            }
        }
        #expect(strokes > 0)
        #expect(m.pointIndex == 1)
    }

    @Test("the same seed plays the same match")
    func deterministic() {
        func run() -> TennisMatch {
            var m = TennisMatch(server: .opponent, seed: 5)
            for _ in 0..<10 {
                if case .over = m.state { break }
                let tol = m.nextScript(for: .default)?.tolerance ?? 0.1
                m.play(swing(), cue: Cue(contactTime: TestShots.contactTime, tolerance: tol))
            }
            return m
        }
        #expect(run() == run())
    }

    @Test("a whole set can be played to a finish by letting every ball go")
    func playsToEnd() {
        var m = TennisMatch(server: .you, gamesToWin: 4)
        var steps = 0
        while !m.score.isOver, steps < 500 {
            m.play(nil, cue: TestShots.cue())
            steps += 1
        }
        #expect(m.score.winner == .opponent)
        if case .over(let p) = m.state { #expect(p == .opponent) } else { Issue.record("not over") }
    }
}
