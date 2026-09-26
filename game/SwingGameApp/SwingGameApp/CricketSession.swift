import Foundation
import SwingCore
import SwingGame

/// Drives a `CricketMatch` on a real clock. Every ball begins from the
/// stance: the player hangs the phone down and holds still, it buzzes, the
/// count-in plays, they hit on the fifth beat. Bat an over, then bowl one.
@MainActor
@Observable
final class CricketSession {
    private(set) var match: CricketMatch
    private(set) var headline = "Cricket"
    private(set) var detail = ""
    private(set) var isRunning = false
    private(set) var stage = Stage.idle
    private(set) var activeScript: ActiveScript?
    private(set) var lastDelivery: Delivery?
    private(set) var lastBatting: BattingResult?
    private(set) var lastBowling: BowlingResult?
    private(set) var lastResultAt: TimeInterval = 0
    private(set) var profile = SwingProfile.default

    let handedness: Handedness
    private let source: any ShotSource
    private let inbox = ShotInbox()
    private let haptics: HapticPlayer
    private let clicks: ClickPlayer
    private let announcer: Announcer
    private let fixtures = FixtureStore.shared
    private var loop: Task<Void, Never>?

    init(source: any ShotSource, haptics: HapticPlayer, clicks: ClickPlayer, announcer: Announcer, handedness: Handedness) {
        self.match = CricketMatch(oversPerSide: 1, wicketsPerSide: 3, seed: UInt64(Date().timeIntervalSince1970))
        self.source = source
        self.haptics = haptics
        self.clicks = clicks
        self.announcer = announcer
        self.handedness = handedness
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        source.profile = profile
        source.handler = { [weak self] shot, trace in
            self?.inbox.push(shot, trace: trace)
        }
        loop = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        isRunning = false
        activeScript = nil
        stage = .idle
        announcer.stop()
        headline = "Stopped"
    }

    func restart() {
        stop()
        match = CricketMatch(oversPerSide: 1, wicketsPerSide: 3, seed: UInt64(Date().timeIntervalSince1970))
        lastBatting = nil
        lastBowling = nil
        start()
    }

    // MARK: - The flow

    private func run() async {
        headline = "Take your stance"
        detail = "Hang the phone down like a bat, screen facing the bowler. Hold still."
        announcer.sayNow("Cricket. Hang the phone down like a bat, with the screen facing the bowler, and hold still. When it buzzes, you'll hear five beats. Hit the ball on the fifth, the high one.")
        stage = .stance
        try? await Task.sleep(for: .seconds(1))

        while !Task.isCancelled {
            switch match.phase {
            case .batting:
                await bat()
            case .bowling:
                await bowl()
            case .finished:
                stage = .finished
                headline = match.scoreAnnouncement
                detail = "Restart from the menu to play again."
                announcer.say(match.scoreAnnouncement)
                isRunning = false
                return
            }
        }
    }

    /// Return to the stance. Buzzes when set.
    private func stance() async -> Bool {
        stage = .stance
        headline = "Back to your stance"
        guard await source.awaitStance(timeout: 300), !Task.isCancelled else { return false }
        haptics.play(ReadyCue.haptic)
        return true
    }

    private func bat() async {
        let delivery = match.nextDelivery()
        lastDelivery = delivery
        detail = "\(delivery.bowler.spoken.capitalized), \(Int(delivery.pace * 2.237)) mph"
        guard await stance() else { return }
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { return }

        let script = delivery.script(for: profile)
        let start = Date.timeIntervalSinceReferenceDate + 0.3
        let cue = Cue(script: script, startingAt: start, tolerance: delivery.tolerance(for: profile))
        inbox.clear()
        stage = .countIn
        activeScript = ActiveScript(script: script, start: start)
        headline = "Here it comes"
        haptics.play(script, at: start)
        clicks.schedule(script, at: start)
        let answer = await inbox.shot(for: cue, notBefore: start)
        activeScript = nil
        if Task.isCancelled { return }

        let result = Batting.play(shot: answer?.shot, delivery: delivery, cue: cue, handedness: handedness)
        stage = .result
        lastResultAt = Date.timeIntervalSinceReferenceDate
        lastBatting = result
        haptics.play(result.haptic)
        announcer.sayNow([result.announcement, result.timing?.feedback].compactMap { $0 }.joined(separator: " "))
        match.record(result)
        headline = result.announcement
        detail = describe(result, delivery: delivery)

        if let answer {
            fixtures.save(
                answer.shot, trace: answer.trace, prefix: "cricket-bat",
                note: "Batting vs \(delivery.bowler.rawValue) \(delivery.length.rawValue) at \(Int(delivery.pace)) m/s, line \(String(format: "%.2f", delivery.line)). "
                    + "Timing \(result.timing.map { String(format: "%+.3f s", $0.error) } ?? "n/a"). Game said: \(result.announcement)"
            )
        }

        try? await Task.sleep(for: .seconds(2.5))
        if match.phase != .batting {
            headline = "Now bowl"
            detail = "Stance, buzz, then bowl when you're ready."
            announcer.say(match.phaseAnnouncement)
            try? await Task.sleep(for: .seconds(4))
        } else if match.yours.balls % 2 == 0 {
            announcer.say(match.scoreAnnouncement)
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    private func bowl() async {
        guard await stance() else { return }
        stage = .bowling
        inbox.clear()
        let armed = Date.timeIntervalSinceReferenceDate + 0.3
        headline = "Bowl when ready"
        detail = "Ball \(match.theirs.balls + 1) of \(match.ballsPerInnings)"
        // A bowling action is several strokes — the arm going back, the arm
        // coming over. Collect them all and take the fastest as the release,
        // rather than the first, which is the wind-up.
        let swings = await inbox.swings(notBefore: armed, firstWithin: 300, window: 0.9)
        guard let answer = swings.max(by: { $0.shot.spinRate < $1.shot.spinRate }), !Task.isCancelled else { return }
        let ball = Bowling.ball(from: answer.shot)
        let result = Bowling.face(ball, batter: match.batter, ballIndex: match.nextBowlingIndex, seed: match.seed)
        stage = .result
        lastResultAt = Date.timeIntervalSinceReferenceDate
        lastBowling = result
        haptics.play(result.haptic)
        announcer.sayNow(result.announcement)
        match.record(result)
        headline = result.announcement
        if let ball {
            let side = abs(ball.line) < 0.15 ? "at the stumps" : String(format: "%.1f m %@", abs(ball.line), ball.line > 0 ? "outside off" : "down leg")
            detail = "\(Int(ball.pace * 2.237)) mph, \(ball.length.spoken), \(side)"
        } else {
            detail = "That motion was not read as a bowl."
        }
        fixtures.save(
            answer.shot, trace: answer.trace, prefix: "cricket-bowl",
            note: "Bowling. Read as \(ball.map { "\($0.length.rawValue) at \(Int($0.pace)) m/s, line \(String(format: "%.2f", $0.line))" } ?? "not a bowl"). Game said: \(result.announcement)"
        )
        try? await Task.sleep(for: .seconds(2.5))
        if match.phase == .bowling {
            announcer.say(match.scoreAnnouncement)
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    private func describe(_ r: BattingResult, delivery: Delivery) -> String {
        var parts: [String] = []
        if let t = r.timing {
            parts.append(String(format: "%+.0f ms", t.error * 1000))
        }
        if let f = r.flight {
            parts.append(String(format: "%.0f m at %.0f°", f.total, f.angle))
        }
        parts.append("\(delivery.length.spoken) ball")
        return parts.joined(separator: " · ")
    }
}
