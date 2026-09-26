import SwiftUI
import SwingGame

/// The count-in, drawn: one lamp per beat that lights as the beat lands, the
/// last — the hit — bigger and orange. Mostly for whoever is watching; the
/// player's eyes are elsewhere.
struct BeatPulseView: View {
    let active: ActiveScript?
    let stage: Stage

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: active == nil)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 14) {
                if let active {
                    let beats = active.script.entries.filter { $0.event == HapticVocabulary.beat || $0.event == HapticVocabulary.accent }
                    ForEach(Array(beats.enumerated()), id: \.offset) { _, entry in
                        let elapsed = now - (active.start + entry.at)
                        lamp(lit: elapsed >= 0, accent: entry.event == HapticVocabulary.accent, age: elapsed)
                    }
                } else {
                    ForEach(0..<5, id: \.self) { i in
                        lamp(lit: stage == .result && i == 4, accent: i == 4, age: 1)
                    }
                }
            }
            .frame(height: 44)
        }
    }

    private func lamp(lit: Bool, accent: Bool, age: TimeInterval) -> some View {
        let size: CGFloat = accent ? 32 : 22
        let flash = lit ? max(0, 1 - age / 0.25) : 0
        return ZStack {
            Circle()
                .fill(lit ? (accent ? Color.orange : Color.white) : Color.white.opacity(0.18))
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            if accent {
                Image(systemName: "figure.cricket")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(lit ? .black : .white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: (accent ? Color.orange : Color.white).opacity(0.8 * flash), radius: 12 * (1 + flash))
        .scaleEffect(1 + 0.35 * flash)
    }
}
