import Foundation
import SwingCore
import SwingGame

/// Drives a `TennisMatch` on a real clock. Every stroke begins from the
/// ready position: hang the phone down, hold still, buzz, side call, five
/// beats, hit on the fifth. The rally continues as long as the ball does.
@MainActor
@Observable
final class TennisSession {
    private(set) var match: TennisMatch
    private(set) var headline = "Tennis"
    private(set) var detail = ""
    private(set) var isRunning = false
    private(set) var stage = Stage.idle
    private(set) var activeScript: ActiveScript?
    /// The ball on its way to the player during the current count.
    private(set) var incoming: IncomingBall?
    private(set) var lastStep: TennisMatch.Step?
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
        self.match = TennisMatch(opponent: .clubPlayer, handedness: handedness, server: .you, gamesToWin: 4, seed: UInt64(Date().timeIntervalSince1970))
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
        incoming = nil
        stage = .idle
        announcer.stop()
        headline = "Stopped"
    }

    func restart() {
        stop()
        match = TennisMatch(opponent: .clubPlayer, handedness: handedness, server: .you, gamesToWin: 4, seed: UInt64(Date().timeIntervalSince1970))
        lastStep = nil
        start()
    }

    private func run() async {
        headline = "Ready position"
        detail = "Hang the phone down like a racket, screen facing the net. Hold still."
        announcer.sayNow("Tennis. First to four games. Hang the phone down like a racket, screen facing the net, and hold still. One tick is forehand, two is backhand. Then five beats: hit the ball on the fifth, the high one.")
        stage = .stance
        try? await Task.sleep(for: .seconds(1))

        while !Task.isCancelled {
            guard let (script, tolerance) = match.nextScript(for: profile) else {
                if case .over = match.state {
                    stage = .finished
                    headline = match.score.gameAnnouncement
                    detail = "Restart from the menu to play again."
                    isRunning = false
                }
                return
            }

            stage = .stance
            headline = "Ready position"
            guard await source.awaitStance(timeout: 300), !Task.isCancelled else { return }
            haptics.play(ReadyCue.haptic)
            try? await Task.sleep(for: .milliseconds(400))

            if let prompt = match.prompt {
                announcer.sayNow(prompt)
                headline = prompt
            }
            if case .incoming(let ball, _) = match.state {
                incoming = ball
                detail = String(format: "%@ · %.0f mph", ball.side.rawValue.capitalized, ball.pace * 2.237)
            } else {
                incoming = nil
                detail = "Five beats. Serve on the fifth."
            }
            let start = Date.timeIntervalSinceReferenceDate + 0.3
            let cue = Cue(script: script, startingAt: start, tolerance: tolerance)
            inbox.clear()
            stage = .countIn
            activeScript = ActiveScript(script: script, start: start)
            haptics.play(script, at: start)
            clicks.schedule(script, at: start)

            let answer = await inbox.shot(for: cue, notBefore: start)
            activeScript = nil
            if Task.isCancelled { return }
            let stateBefore = match.state
            let step = match.play(answer?.shot, cue: cue)
            stage = .result
            lastResultAt = Date.timeIntervalSinceReferenceDate
            lastStep = step
            incoming = nil
            haptics.play(step.stroke.haptic)
            announcer.sayNow([step.stroke.announcement, step.stroke.timing?.feedback].compactMap { $0 }.joined(separator: " "))
            headline = step.stroke.announcement
            detail = describe(step)

            if let answer {
                let what: String
                switch stateBefore {
                case .yourServe: what = "Serve"
                case .incoming(let ball, let n): what = "\(ball.side.rawValue.capitalized) return, stroke \(n), ball at \(Int(ball.pace)) m/s"
                case .over: what = ""
                }
                fixtures.save(
                    answer.shot, trace: answer.trace, prefix: "tennis",
                    note: "\(what). Timing \(step.stroke.timing.map { String(format: "%+.3f s", $0.error) } ?? "n/a"). Game said: \(step.stroke.announcement)"
                )
            }

            if step.rallyContinues {
                try? await Task.sleep(for: .seconds(1.2))
            } else {
                if let announcement = step.announcement {
                    try? await Task.sleep(for: .seconds(1.2))
                    announcer.say(announcement)
                    headline = announcement
                }
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
    }

    private func describe(_ step: TennisMatch.Step) -> String {
        var parts: [String] = []
        if let t = step.stroke.timing {
            parts.append(String(format: "%+.0f ms", t.error * 1000))
        }
        if case .inPlay(let p) = step.stroke.outcome {
            parts.append(String(format: "%.1f m %@, depth %.0f%%", abs(p.lateral), p.lateral < 0 ? "left" : "right", p.depth * 100))
        }
        parts.append(match.score.pointAnnouncement)
        return parts.joined(separator: " · ")
    }
}
