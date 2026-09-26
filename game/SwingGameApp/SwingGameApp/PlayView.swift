import SwiftUI
import SwingCore
import SwingGame

/// The one screen you see while playing, and mostly you do not see it: you
/// glance at it between balls. The scene fills the screen; one big line and
/// one small line sit over it; the beats pulse along the bottom.
struct PlayView: View {
    let sport: Sport
    let handedness: Handedness

    @State private var model: PlayModel?

    var body: some View {
        Group {
            if let model {
                PlayScreen(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(sport.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            if model == nil {
                let m = PlayModel(sport: sport, handedness: handedness)
                model = m
                m.play()
            }
        }
        .onDisappear {
            model?.tearDown()
        }
    }
}

/// Owns the source, the players and whichever session the sport needs.
@MainActor
@Observable
final class PlayModel {
    let sport: Sport
    let handedness: Handedness
    let haptics = HapticPlayer()
    let announcer = Announcer()
    let clicks = ClickPlayer()
    let detector: StandInDetector
    let tap = TapShotSource()
    /// Simulator has no motion sensors; a button stands in for the hand.
    var useTap: Bool {
        didSet { if oldValue != useTap { restart() } }
    }
    var cricket: CricketSession?
    var tennis: TennisSession?

    var source: any ShotSource { useTap ? tap : detector }

    init(sport: Sport, handedness: Handedness) {
        self.sport = sport
        self.handedness = handedness
        self.detector = StandInDetector()
        #if targetEnvironment(simulator)
        useTap = true
        #else
        useTap = false
        #endif
        detector.start()
    }

    var headline: String { cricket?.headline ?? tennis?.headline ?? sport.title }
    var detail: String { cricket?.detail ?? tennis?.detail ?? "" }
    var stage: Stage { cricket?.stage ?? tennis?.stage ?? .idle }
    var activeScript: ActiveScript? { cricket?.activeScript ?? tennis?.activeScript }
    var isRunning: Bool { cricket?.isRunning ?? tennis?.isRunning ?? false }

    func play() {
        switch sport {
        case .cricket:
            if cricket == nil {
                cricket = CricketSession(source: source, haptics: haptics, clicks: clicks, announcer: announcer, handedness: handedness)
            }
            cricket?.start()
        case .tennis:
            if tennis == nil {
                tennis = TennisSession(source: source, haptics: haptics, clicks: clicks, announcer: announcer, handedness: handedness)
            }
            tennis?.start()
        default:
            break
        }
    }

    func stop() {
        cricket?.stop()
        tennis?.stop()
    }

    func restart() {
        stop()
        cricket = nil
        tennis = nil
        play()
    }

    func tearDown() {
        stop()
        detector.stop()
        announcer.stop()
    }
}

private struct PlayScreen: View {
    @Bindable var model: PlayModel

    var body: some View {
        ZStack {
            sceneBackground.ignoresSafeArea()

            VStack(spacing: 8) {
                banner
                    .padding(.top, 4)
                scene
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 14)
                bottomPanel
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if model.isRunning {
                        Button("Stop", systemImage: "stop.fill", role: .destructive) { model.stop() }
                    }
                    Button("Restart", systemImage: "arrow.counterclockwise") { model.restart() }
                    Divider()
                    Toggle("Tap instead of swing", isOn: $model.useTap)
                    Toggle("Mute voice", isOn: Binding(
                        get: { model.announcer.isMuted },
                        set: { model.announcer.isMuted = $0 }
                    ))
                    Toggle("Mute clicks", isOn: Binding(
                        get: { model.clicks.isMuted },
                        set: { model.clicks.isMuted = $0 }
                    ))
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.white)
                }
            }
        }
    }

    @ViewBuilder
    private var scene: some View {
        if let c = model.cricket {
            CricketFieldView(session: c)
        } else if let t = model.tennis {
            TennisCourtView(session: t)
        } else {
            Color.black
        }
    }

    private var sceneBackground: Color {
        switch model.sport {
        case .cricket: Color(red: 0.06, green: 0.16, blue: 0.08)
        case .tennis: Color(red: 0.08, green: 0.22, blue: 0.16)
        default: .black
        }
    }

    private var banner: some View {
        VStack(spacing: 6) {
            Text(model.headline)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: model.headline)
            if !model.detail.isEmpty {
                Text(model.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14)
    }

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            scoreboard
            BeatPulseView(active: model.activeScript, stage: model.stage)
            if model.useTap {
                TapControls(tap: model.tap, enabled: model.isRunning)
            } else {
                stanceIndicator
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var stanceIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: model.detector.inStance ? "checkmark.circle.fill" : "iphone.gen3")
                .foregroundStyle(model.detector.inStance ? .green : .white.opacity(0.7))
            Text(model.detector.inStance ? "Set" : model.detector.status)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Gauge(value: min(model.detector.liveRotation, 20), in: 0...20) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(.orange)
                .frame(width: 90)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var scoreboard: some View {
        if let c = model.cricket {
            HStack(spacing: 28) {
                score("You", "\(c.match.yours.runs)/\(c.match.yours.wickets)", "\(c.match.yours.overs) ov")
                score("Them", c.match.phase == .batting ? "—" : "\(c.match.theirs.runs)/\(c.match.theirs.wickets)", c.match.phase == .batting ? "to bat" : "\(c.match.theirs.overs) ov")
            }
        } else if let t = model.tennis {
            HStack(spacing: 28) {
                score("You", "\(t.match.score.games[.you] ?? 0)", pointWord(t.match.score.points[.you] ?? 0, t.match.score.points[.opponent] ?? 0))
                score("Them", "\(t.match.score.games[.opponent] ?? 0)", pointWord(t.match.score.points[.opponent] ?? 0, t.match.score.points[.you] ?? 0))
            }
        }
    }

    private func pointWord(_ mine: Int, _ theirs: Int) -> String {
        if mine >= 3 && theirs >= 3 { return mine == theirs ? "40" : (mine > theirs ? "AD" : "") }
        return ["0", "15", "30", "40"][min(mine, 3)]
    }

    private func score(_ who: String, _ big: String, _ small: String) -> some View {
        VStack(spacing: 0) {
            Text(who).font(.caption2).foregroundStyle(.white.opacity(0.6))
            Text(big).font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
            Text(small).font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
        }
        .frame(minWidth: 80)
    }

    private struct TapControls: View {
        @Bindable var tap: TapShotSource
        let enabled: Bool

        var body: some View {
            VStack(spacing: 6) {
                Button {
                    tap.swingNow()
                } label: {
                    Text("Swing now")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!enabled)

                HStack {
                    Text("Speed \(Int(tap.speed))").frame(width: 80, alignment: .leading)
                    Slider(value: $tap.speed, in: 3...25)
                }
                HStack {
                    Text("Up \(Int(tap.elevation))°").frame(width: 80, alignment: .leading)
                    Slider(value: $tap.elevation, in: -30...60)
                }
                HStack {
                    Text("Aim \(Int(tap.yaw))°").frame(width: 80, alignment: .leading)
                    Slider(value: $tap.yaw, in: -60...60)
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
        }
    }

}
