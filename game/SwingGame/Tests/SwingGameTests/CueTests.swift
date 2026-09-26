import Foundation
import Testing
import SwingCore
@testable import SwingGame

@Suite("Cue and timing")
struct CueTests {

    @Test("a shot exactly on the cue is perfect")
    func perfect() {
        let t = TestShots.cue().timing(of: TestShots.straightSwing())
        #expect(t.error == 0)
        #expect(t.quality == 1)
        #expect(t.grade == .perfect)
        #expect(!t.missed)
        #expect(t.feedback == nil)
    }

    @Test("quality falls off quadratically, so a small error costs little")
    func quadratic() {
        let cue = TestShots.cue(tolerance: 0.1)
        let small = cue.timing(of: TestShots.straightSwing(at: 0.02)).quality
        let half = cue.timing(of: TestShots.straightSwing(at: 0.05)).quality
        let edge = cue.timing(of: TestShots.straightSwing(at: 0.1)).quality
        #expect(abs(small - 0.96) < 1e-9)
        #expect(abs(half - 0.75) < 1e-9)
        #expect(edge == 0)
    }

    @Test("early is negative and late is positive, and the phone says which")
    func sign() {
        let cue = TestShots.cue(tolerance: 0.1)
        #expect(cue.timing(of: TestShots.straightSwing(at: -0.05)).grade == .early)
        #expect(cue.timing(of: TestShots.straightSwing(at: 0.05)).grade == .late)
        #expect(cue.timing(of: TestShots.straightSwing(at: -0.2)).grade == .tooEarly)
        #expect(cue.timing(of: TestShots.straightSwing(at: 0.2)).grade == .tooLate)
        #expect(cue.timing(of: TestShots.straightSwing(at: 0.2)).missed)
        #expect(cue.timing(of: TestShots.straightSwing(at: 0.05)).feedback == "A touch late.")
        #expect(cue.timing(of: TestShots.straightSwing(at: -0.2)).feedback == "Too early, by 200 milliseconds.")
        #expect(cue.timing(of: TestShots.straightSwing(at: 0.6)).feedback == "Way too late.")
    }

    @Test("a cue built from a script lands on the script's contact moment")
    func fromScript() {
        let d = Delivery(bowler: .fast, line: 0, length: .good, pace: 36)
        let script = d.script(for: .default)
        let cue = Cue(script: script, startingAt: 500, tolerance: d.tolerance(for: .default))
        #expect(cue.contactTime == 500 + script.contactAt)
        #expect(cue.deadline > cue.contactTime)
    }
}

@Suite("Swing profile")
struct SwingProfileTests {

    @Test("the beat is the player's own swing, within what a hand can count")
    func beatIsTheSwing() {
        #expect(SwingProfile(swingDuration: 0.65, peakRotation: 9).beat == 0.65)
        #expect(SwingProfile(swingDuration: 0.2, peakRotation: 9).beat == 0.45)
        #expect(SwingProfile(swingDuration: 2.0, peakRotation: 9).beat == 1.0)
    }

    @Test("a quick bowler shortens a player's beat and a spinner lengthens it")
    func scaled() {
        let p = SwingProfile(swingDuration: 0.7, peakRotation: 9)
        let fast = Delivery(bowler: .fast, line: 0, length: .good, pace: 37).beat(for: p)
        let med = Delivery(bowler: .medium, line: 0, length: .good, pace: 30).beat(for: p)
        let spin = Delivery(bowler: .spin, line: 0, length: .good, pace: 20).beat(for: p)
        #expect(fast < med && med < spin)
        #expect(abs(med - 0.7) < 1e-9)
    }

    @Test("a practice swing that was too short or too still is not a profile")
    func measured() {
        let good = TestShots.straightSwing(spinRate: 11)
        #expect(SwingProfile.measured(from: good)?.swingDuration == 0.6)
        var still = good
        still.spinRate = 0.5
        #expect(SwingProfile.measured(from: still) == nil)
        var twitch = good
        twitch.tempo.back = 0.1
        #expect(SwingProfile.measured(from: twitch) == nil)
    }

    @Test("merging follows the newer swing")
    func merging() {
        let p = SwingProfile(swingDuration: 0.8, peakRotation: 8).merging(swingDuration: 0.6, peakRotation: 12)
        #expect(abs(p.swingDuration - 0.68) < 1e-9)
        #expect(abs(p.peakRotation - 10.4) < 1e-9)
    }
}

@Suite("Count-in scripts")
struct HapticScriptTests {

    let profile = SwingProfile.default

    @Test("beats are evenly spaced, the last is accented, and contact is on it")
    func grid() {
        for bowler in Delivery.Bowler.allCases {
            let d = Delivery(bowler: bowler, line: 0, length: .good, pace: 30)
            let s = d.script(for: profile)
            let interval = d.beat(for: profile)
            let times = s.entries.map(\.at)
            #expect(times.count == Delivery.beats)
            let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
            for g in gaps { #expect(abs(g - interval) < 1e-9) }
            #expect(s.entries.last!.event == HapticVocabulary.accent)
            #expect(s.entries.dropLast().allSatisfy { $0.event == HapticVocabulary.beat })
            #expect(abs(s.contactAt - times.last!) < 1e-9)
        }
    }

    @Test("the hit beat is played at the moment of contact: you hit the buzz, not the gap after it")
    func hitOnTheBeat() {
        let s = Delivery(bowler: .fast, line: 0, length: .yorker, pace: 38).script(for: profile)
        let hit = s.entries.first { abs($0.at - s.contactAt) < 1e-9 }
        #expect(hit?.event == HapticVocabulary.accent)
        #expect(s.entries.count == 5)
    }

    @Test("length does not move the grid — it is unlearnable at pace, so it only changes the outcome")
    func lengthDoesNotMoveGrid() {
        let scripts = Delivery.Length.allCases.map { Delivery(bowler: .fast, line: 0, length: $0, pace: 36).script(for: profile) }
        #expect(Set(scripts).count == 1)
    }

    @Test("the window is a third of a beat, within human limits")
    func tolerance() {
        let quick = Delivery(bowler: .fast, line: 0, length: .good, pace: 37)
        let spin = Delivery(bowler: .spin, line: 0, length: .good, pace: 20)
        #expect(quick.tolerance(for: profile) < spin.tolerance(for: profile))
        #expect(quick.tolerance(for: profile) >= 0.14)
        #expect(spin.tolerance(for: profile) <= 0.24)
    }

    @Test("tennis: forehand is one tick, backhand is two, then the same count-in")
    func tennisSideCue() {
        let fh = IncomingBall(side: .forehand, pace: 25, depth: 0.7)
        let bh = IncomingBall(side: .backhand, pace: 25, depth: 0.7)
        let fs = fh.script(for: profile), bs = bh.script(for: profile)
        #expect(fs.entries.filter { $0.event == HapticVocabulary.tick }.count == 1)
        #expect(bs.entries.filter { $0.event == HapticVocabulary.tick }.count == 2)
        #expect(fs.entries.filter { $0.event == HapticVocabulary.beat }.count == IncomingBall.beats - 1)
        #expect(fs.entries.last!.event == HapticVocabulary.accent)
        #expect(abs(fs.contactAt - fs.entries.last!.at) < 1e-9)
        // The beats start after the side call, with time to move the hand.
        #expect(fs.entries.first { $0.event == HapticVocabulary.beat }!.at == IncomingBall.sideLead)
    }

    @Test("a harder tennis ball is a shorter beat")
    func tennisBeat() {
        let soft = IncomingBall(side: .forehand, pace: 18, depth: 0.5)
        let hard = IncomingBall(side: .forehand, pace: 34, depth: 0.5)
        #expect(soft.beat(for: profile) > hard.beat(for: profile))
        #expect(abs(IncomingBall(side: .forehand, pace: 22, depth: 0.5).beat(for: profile) - profile.beat) < 1e-9)
    }

    @Test("their serve has no side call; every count is five beats")
    func serveScript() {
        let s = IncomingBall(side: .forehand, pace: 30, depth: 0.8, isServe: true).script(for: profile)
        #expect(!s.entries.contains { $0.event == HapticVocabulary.tick })
        #expect(s.entries.count == 5)
        let mine = Serve.script(for: profile)
        #expect(mine.entries.count == 5)
        #expect(mine.entries.last!.event == HapticVocabulary.accent)
        #expect(abs(mine.contactAt - 4 * profile.beat) < 1e-9)
    }

    @Test("script entries are kept in time order however they were given")
    func sorted() {
        let s = HapticScript(
            entries: [.init(at: 1, event: HapticVocabulary.tick), .init(at: 0, event: HapticVocabulary.accent)],
            contactAt: 2
        )
        #expect(s.entries.map(\.at) == [0, 1])
        #expect(s.duration == 1)
    }
}
