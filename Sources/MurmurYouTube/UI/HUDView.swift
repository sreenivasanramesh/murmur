import SwiftUI

/// Brand palette. Deliberately minimal for the skeleton — this is the surface the real
/// branding pass will replace.
enum Brand {
    static let accent = Color(red: 0.42, green: 0.55, blue: 1.0)
    static let accentWarm = Color(red: 0.76, green: 0.47, blue: 1.0)

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentWarm],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct HUDView: View {
    @Bindable var controller: DictationController

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Waveform(level: controller.level, isActive: controller.state == .listening)
                .frame(width: 54, height: 24)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(label)
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundStyle(isError ? Color.red : Color(red: 0.1, green: 0.1, blue: 0.15))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .id("streamTextBottom")
                    }
                    .frame(minHeight: 56, alignment: .center)
                }
                .frame(height: 56)
                .onChange(of: controller.transcript) { _, _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("streamTextBottom", anchor: .bottom)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: 420, height: 80)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(white: 0.98).opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private var isError: Bool {
        if case .error = controller.state { return true }
        return false
    }

    private var label: String {
        switch controller.state {
        case .starting:
            if case .downloading(let progress, _) = ParakeetDownloadManager.shared.status,
               Settings.shared.engine.requiresParakeetModel {
                return "Downloading model (\(Int(progress * 100))%)…"
            }
            return "Listening…"
        case .listening:
            if !controller.transcript.isEmpty {
                return controller.transcript
            }
            if case .downloading(let progress, _) = ParakeetDownloadManager.shared.status,
               Settings.shared.engine.requiresParakeetModel {
                return "Downloading model (\(Int(progress * 100))%)…"
            }
            return "Listening…"
        case .finishing:
            return controller.transcript.isEmpty ? "Transcribing…" : controller.transcript
        case .error(let message):
            return message
        case .idle:
            return ""
        }
    }
}

/// Level-reactive bars. Each bar gets a fixed phase offset so the group ripples rather
/// than pumping in unison.
private struct Waveform: View {
    let level: Float
    let isActive: Bool

    private static let barCount = 12
    private static let phases: [Double] = (0..<barCount).map { index in
        // Irrational multiplier keeps the offsets from lining up into a visible period.
        (Double(index) * 0.618).truncatingRemainder(dividingBy: 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(Brand.gradient)
                        .frame(width: 3, height: height(for: index, at: t))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        let floorHeight: CGFloat = 3
        guard isActive else { return floorHeight }

        let phase = Self.phases[index]
        let wave = sin(time * 6.0 + phase * .pi * 2)
        let amplitude = CGFloat(max(0.04, level))
        // Wave rides on top of the level so bars still breathe during quiet passages.
        let scaled = amplitude * (0.55 + 0.45 * CGFloat(wave))
        return floorHeight + max(0, scaled) * 23
    }
}
