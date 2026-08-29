import AppKit
import Carbon.HIToolbox
import MurmurDictionary
import SwiftUI

/// The app's main window — modern minimalist interface with Transcriptions, Dictionary, and Settings.
struct MainWindow: View {
    @Bindable var controller: DictationController
    @State private var section: Section = .transcriptions

    enum Section: String, CaseIterable, Identifiable {
        case transcriptions
        case dictionary
        case settings

        var id: String { rawValue }
        var title: String {
            switch self {
            case .transcriptions: "Transcriptions"
            case .dictionary: "Dictionary"
            case .settings: "Settings"
            }
        }
        var iconName: String {
            switch self {
            case .transcriptions: "waveform.and.mic"
            case .dictionary: "character.book.closed.fill"
            case .settings: "gearshape.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                Divider()
                    .background(DS.Color.border)

                Group {
                    switch section {
                    case .transcriptions:
                        TranscriptionListView()
                    case .dictionary:
                        DictionaryPanel()
                    case .settings:
                        SettingsPanelView(controller: controller)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    // MARK: - Modern Header Bar

    private var headerBar: some View {
        ZStack {
            // Pinned Centered Navigation Tabs (Static and fixed in position)
            HStack(spacing: 3) {
                ForEach(Section.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            section = item
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.iconName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(section == item ? DS.Color.accent : DS.Color.inkSecondary)

                            Text(item.title)
                                .font(.system(size: 12, weight: section == item ? .semibold : .medium))
                                .foregroundStyle(section == item ? DS.Color.ink : DS.Color.inkSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if section == item {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(DS.Color.tabActive)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.Color.cardBorder, lineWidth: 1))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.Color.tabBorder, lineWidth: 1))

            // Left & Right Header Items
            HStack(alignment: .center) {
                // App Branding (Pinned to Left, directly below the traffic lights)
                HStack(spacing: DS.Space.snug) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(DS.Color.accent.opacity(0.12))
                            .frame(width: 26, height: 26)
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DS.Color.accent)
                    }

                    Text("Murmur")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                }
                .padding(.leading, DS.Space.roomy)

                Spacer()

                // Push to talk shortcut indicator (Fixed on Right)
                HStack(spacing: 6) {
                    Text("Hold")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.inkMuted)

                    Text(Settings.shared.pushToTalkHotkey.displayString)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.Color.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(DS.Color.card, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.Color.cardBorder, lineWidth: 1))

                    Text("to dictate")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.inkMuted)
                }
                .padding(.trailing, DS.Space.roomy)
            }
        }
        .padding(.vertical, 10)
        .background(DS.Color.header)
        .background(WindowAccessor { window in
            window.isMovableByWindowBackground = true
        })
    }
}

// MARK: - Transcriptions Section

struct TranscriptionListView: View {
    @State private var store = RunStore.shared
    @State private var query = ""
    @State private var isConfirmingClear = false

    private var runs: [DictationRun] {
        let all = store.runs.reversed().map { $0 }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.text.localizedStandardContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Modern Search & Actions Header
            HStack(spacing: DS.Space.snug) {
                ModernSearchField(text: $query, placeholder: "Search transcriptions...")
                    .frame(maxWidth: 340)

                Spacer()

                Text("\(store.runs.count) recording\(store.runs.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkMuted)

                if !store.runs.isEmpty {
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.roomy)
            .padding(.vertical, 12)
            .background(DS.Color.header)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.Color.border).frame(height: 1)
            }

            if runs.isEmpty {
                ModernEmptyPanel(
                    icon: "waveform.and.mic",
                    title: store.runs.isEmpty ? "No transcriptions yet" : "No matching transcriptions",
                    message: store.runs.isEmpty
                        ? "Hold \(Settings.shared.pushToTalkHotkey.displayString) anywhere on your Mac to dictate."
                        : "Try searching for a different word or phrase."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(runs) { run in
                            ModernTranscriptionCard(run: run) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    RunLog.delete(run)
                                }
                            }
                        }
                    }
                    .padding(DS.Space.roomy)
                }
            }
        }
        .confirmationDialog(
            "Delete all \(store.runs.count) recordings?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { RunLog.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all stored transcription history.")
        }
    }
}

private struct ModernTranscriptionCard: View {
    let run: DictationRun
    let onDelete: () -> Void

    @State private var didCopy = false
    @State private var isHovering = false

    private var isParakeet: Bool {
        run.engine.localizedCaseInsensitiveContains("parakeet")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row
            HStack(spacing: 8) {
                // Engine Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(isParakeet ? DS.Color.accent : DS.Color.info)
                        .frame(width: 5, height: 5)
                    Text(run.engine)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isParakeet ? DS.Color.accent : DS.Color.info)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((isParakeet ? DS.Color.accent : DS.Color.info).opacity(0.10), in: RoundedRectangle(cornerRadius: 6))

                // Duration & speed
                Text(String(format: "%.2fs", run.processSeconds))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.Color.inkMuted)

                Spacer()

                // Timestamp
                Text(run.date, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkMuted)

                // Copy Button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.text, forType: .string)
                    withAnimation { didCopy = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation { didCopy = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(didCopy ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(didCopy ? DS.Color.success : DS.Color.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Delete Button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.inkMuted)
                        .padding(5)
                        .background(isHovering ? DS.Color.tabBg : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Delete transcription")
                .opacity(isHovering ? 1 : 0.6)
            }

            // Transcript Text
            Text(run.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DS.Color.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(3)

            // Correction Tags
            if let corrections = run.corrections, !corrections.isEmpty {
                HStack(spacing: 6) {
                    Text("Corrected:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Color.inkMuted)

                    ForEach(corrections, id: \.self) { correction in
                        HStack(spacing: 4) {
                            Text(correction.from)
                                .strikethrough()
                                .foregroundStyle(DS.Color.inkMuted)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(DS.Color.inkMuted)
                            Text(correction.to)
                                .foregroundStyle(DS.Color.success)
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.Color.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.Color.success.opacity(0.18), lineWidth: 1))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(isHovering ? DS.Color.cardHover : DS.Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DS.Color.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Settings Embedded Section

struct SettingsPanelView: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @State private var downloadManager = ParakeetDownloadManager.shared

    @State private var editingHotkeyTarget: HotkeyEditorTarget?

    enum HotkeyEditorTarget: Identifiable {
        case pushToTalk
        case handsFree

        var id: String {
            switch self {
            case .pushToTalk: "ptt"
            case .handsFree: "hf"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // Group 1: Push to Talk (Single Hotkey, Live Recording on Edit)
                settingCard(
                    title: "Push to talk",
                    description: "Hold to say something short"
                ) {
                    hotkeyRowView(
                        hotkey: settings.pushToTalkHotkey,
                        onEdit: { editingHotkeyTarget = .pushToTalk }
                    )
                }

                // Group 2: Hands-Free Mode (Single Hotkey, Live Recording on Edit)
                settingCard(
                    title: "Hands-free mode",
                    description: "Dictate hands-free by pressing this hotkey to start and stop"
                ) {
                    hotkeyRowView(
                        hotkey: settings.handsFreeHotkey,
                        onEdit: { editingHotkeyTarget = .handsFree }
                    )
                }

                // Group 3: Speech Recognition Engine
                settingCard(title: "Speech Recognition Engine", description: "Choose between on-device live streaming or Neural Engine batch accuracy.") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            // Apple Speech Card
                            engineCard(
                                title: "Apple Speech",
                                badge: "Live Streaming",
                                badgeColor: DS.Color.info,
                                description: "Streams partial words into the HUD pill in real-time as you speak. Built into macOS.",
                                isSelected: settings.engine == .apple
                            ) {
                                settings.engine = .apple
                            }

                            // Parakeet Batch Card
                            engineCard(
                                title: "Parakeet (Batch)",
                                badge: "ANE Batch • 100×",
                                badgeColor: DS.Color.accent,
                                description: "Transcribes complete utterance in ~0.1s on Apple Neural Engine on release with maximal accuracy.",
                                isSelected: settings.engine == .parakeet
                            ) {
                                settings.engine = .parakeet
                                downloadManager.startDownloadIfNeeded()
                            }

                            // Parakeet Streaming Card
                            engineCard(
                                title: "Parakeet (Stream)",
                                badge: "ANE Stream • Beta",
                                badgeColor: DS.Color.accent,
                                description: "Streams partial words in real-time on Apple Neural Engine using sliding-window inference.",
                                isSelected: settings.engine == .parakeetStreaming
                            ) {
                                settings.engine = .parakeetStreaming
                                downloadManager.startDownloadIfNeeded()
                            }
                        }

                        if settings.engine.requiresParakeetModel {
                            downloadStatusView
                        }
                    }
                }

                // Group 4: Formatting & Audio (Strictly Left-Aligned)
                settingCard(title: "Formatting & Audio", description: "Configure text formatting rules and audio feedback.") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Clean up text")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(DS.Color.ink)
                                Text("Strips filler words ('um', 'uh') and standardizes punctuation.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.Color.inkSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $settings.cleanupEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        Divider().background(DS.Color.border)

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Smart AI cleanup (Experimental)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(DS.Color.ink)
                                Text("\(Text("Uses on-device Apple Foundation Models to improve grammar and formatting. ").foregroundStyle(DS.Color.inkSecondary))\(Text("Increases latency.").foregroundStyle(settings.smartCleanup ? DS.Color.record : DS.Color.inkSecondary))")
                                    .font(.system(size: 11))
                            }
                            Spacer()
                            Toggle("", isOn: $settings.smartCleanup)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(!FoundationModelFormatter.isAvailable || !settings.cleanupEnabled)
                        }

                        Divider().background(DS.Color.border)

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Audio feedback chime")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(DS.Color.ink)
                                Text("Plays subtle start and stop audio feedback chimes.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.Color.inkSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $settings.soundEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }
            }
            .padding(DS.Space.roomy)
        }
        .sheet(item: $editingHotkeyTarget) { target in
            HotkeyLiveRecorderSheet(
                target: target,
                onSave: { updated in
                    switch target {
                    case .pushToTalk:
                        settings.pushToTalkHotkey = updated
                    case .handsFree:
                        settings.handsFreeHotkey = updated
                    }
                    controller.reloadHotkey()
                }
            )
        }
        .onAppear {
            downloadManager.refreshStatus()
        }
    }

    private func hotkeyRowView(
        hotkey: CustomHotkey,
        onEdit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            // Key badges with '+' between them
            HStack(spacing: 6) {
                ForEach(Array(hotkey.keys.enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Text("+")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DS.Color.inkMuted)
                    }
                    Text(key.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.Color.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Color.cardBorder, lineWidth: 1))
                }
            }

            Spacer()

            // Pencil Edit Button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkSecondary)
                    .padding(6)
                    .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Record new hotkey combination")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.Color.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.Color.cardBorder, lineWidth: 1))
    }

    private func settingCard<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkSecondary)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.Color.cardBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
    }

    private func engineCard(
        title: String,
        badge: String,
        badgeColor: SwiftUI.Color,
        description: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    Spacer()
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isSelected ? DS.Color.accent.opacity(0.06) : DS.Color.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? DS.Color.accent : DS.Color.cardBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var downloadStatusView: some View {
        switch downloadManager.status {
        case .notDownloaded:
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(DS.Color.inkSecondary)
                Text("Parakeet model weights not yet downloaded (~470 MB)")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkSecondary)
                Spacer()
                Button("Download Now") {
                    downloadManager.startDownloadIfNeeded()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(10)
            .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 8))

        case .downloading(let progress, let stage):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Downloading Parakeet models (\(Int(progress * 100))%) — \(stage)")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.ink)
                }
                ProgressView(value: progress)
                    .tint(DS.Color.accent)
            }
            .padding(10)
            .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 8))

        case .downloaded:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DS.Color.success)
                    .font(.system(size: 12))
                Text("Parakeet models ready on Neural Engine ✓")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkSecondary)
            }
            .padding(8)

        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
                Text("Download error: \(message)")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Spacer()
                Button("Retry") {
                    downloadManager.retry()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Interactive Live Hotkey Recording Sheet

struct HotkeyLiveRecorderSheet: View {
    let target: SettingsPanelView.HotkeyEditorTarget
    let onSave: (CustomHotkey) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var currentlyHeld: [HotkeyKeyItem] = []
    @State private var maxChord: [HotkeyKeyItem] = []
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 4) {
                Text(titleText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Text("Press any key combination on your keyboard, then let go to save.")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            // Live Keys Display Area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Color.tabBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(!maxChord.isEmpty ? DS.Color.accent : DS.Color.cardBorder, lineWidth: !maxChord.isEmpty ? 2 : 1)
                    )

                if maxChord.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 18))
                            .foregroundStyle(DS.Color.inkMuted)
                        Text("Waiting for keys...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Color.inkMuted)
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(Array(maxChord.enumerated()), id: \.offset) { index, key in
                            if index > 0 {
                                Text("+")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(DS.Color.inkMuted)
                            }
                            Text(key.displayName)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(DS.Color.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(DS.Color.card, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.Color.accent.opacity(0.4), lineWidth: 1))
                                .shadow(color: DS.Color.accent.opacity(0.15), radius: 4, y: 2)
                        }
                    }
                    .padding(10)
                }
            }
            .frame(height: 80)
            .padding(.horizontal, 4)

            // Status message
            if !maxChord.isEmpty {
                Text("Release keys to save hotkey")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)
                    .transition(.opacity)
            } else {
                Text("Press Esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkMuted)
            }

            // Cancel Button
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(24)
        .frame(width: 440)
        .background(DS.Color.card)
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    private var titleText: String {
        switch target {
        case .pushToTalk: "Record Push-to-Talk Hotkey"
        case .handsFree: "Record Hands-Free Hotkey"
        }
    }

    private func startMonitoring() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            let keyCode = Int64(event.keyCode)

            // Allow pressing Escape to cancel
            if event.type == .keyDown && keyCode == Int64(kVK_Escape) && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                dismiss()
                return nil
            }

            // Extract active modifiers and pressed key
            var activeKeys: [HotkeyKeyItem] = []

            let flags = event.modifierFlags
            if flags.contains(.control) { activeKeys.append(.control) }
            if flags.contains(.option) {
                if keyCode == Int64(kVK_RightOption) || event.modifierFlags.rawValue & 0x40 != 0 {
                    activeKeys.append(.rightOption)
                } else {
                    activeKeys.append(.leftOption)
                }
            }
            if flags.contains(.command) {
                if keyCode == Int64(kVK_RightCommand) || event.modifierFlags.rawValue & 0x10 != 0 {
                    activeKeys.append(.rightCommand)
                } else {
                    activeKeys.append(.command)
                }
            }
            if flags.contains(.shift) { activeKeys.append(.shift) }
            if flags.contains(.function) { activeKeys.append(.fn) }

            // Add non-modifier key if keyDown
            if event.type == .keyDown {
                let keyItem = HotkeyKeyItem.from(keyCode: keyCode, character: event.charactersIgnoringModifiers)
                if !activeKeys.contains(where: { $0.keyCode == keyItem.keyCode }) {
                    activeKeys.append(keyItem)
                }
            }

            currentlyHeld = activeKeys

            if !activeKeys.isEmpty {
                // Merge into max chord
                for key in activeKeys {
                    if !maxChord.contains(where: { $0.name == key.name }) {
                        maxChord.append(key)
                    }
                }
            } else {
                // All keys released! If we recorded a chord, save and dismiss!
                if !maxChord.isEmpty {
                    let finalChord = maxChord
                    DispatchQueue.main.async {
                        onSave(CustomHotkey(keys: finalChord))
                        dismiss()
                    }
                }
            }

            return nil // Consume event inside recording modal
        }
    }

    private func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Modern Shared Components

struct ModernSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Color.inkSecondary)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Color.inkMuted)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Color.ink)
            }

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.Color.cardBorder, lineWidth: 1))
    }
}

struct ModernEmptyPanel: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.Color.card)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(DS.Color.cardBorder, lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(DS.Color.inkSecondary)
            }
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Window Accessor Helper

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

