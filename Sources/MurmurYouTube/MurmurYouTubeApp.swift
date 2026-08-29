import AppKit
import ServiceManagement
import SwiftUI

@main
struct MurmurYouTubeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The main window. A `Window` rather than a `WindowGroup`: this app has one front
        // panel, and letting ⌘N spawn a second copy of a tape deck makes no sense.
        Window("Murmur", id: "main") {
            MainWindow(controller: delegate.controller)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: Set(["main", "open"]))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Reveal Dictionary File") {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close Window") {
                    AppDelegate.closeAllWindowsAndHideFromDock()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }

        // Fully qualified: this app has its own `Settings` type, which otherwise shadows
        // SwiftUI's settings scene.
        SwiftUI.Settings {
            SettingsWindow(controller: delegate.controller)
        }

        // Secondary now: status and the hotkey while you're working in another app.
        MenuBarExtra {
            MenuContent(controller: delegate.controller)
        } label: {
            Image(systemName: delegate.controller.state.isActive ? "waveform.circle.fill" : "waveform")
        }

        Window("Engine comparison", id: "comparison") {
            ComparisonWindow(controller: delegate.controller)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    private var hud: HUDPanel?
    private var stateObservation: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--benchmark-cleanup") {
            Task {
                await CleanupBenchmark.run()
                exit(0)
            }
            return
        }

        // Enable open at login by default on first launch
        if !UserDefaults.standard.bool(forKey: "hasConfiguredLaunchAtLogin") {
            UserDefaults.standard.set(true, forKey: "hasConfiguredLaunchAtLogin")
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.register()
            }
        }

        // A regular app on initial launch with standard windows and dock icon.
        NSApp.setActivationPolicy(.regular)

        hud = HUDPanel(controller: controller)

        if !controller.activate() {
            Permissions.promptForAccessibility()
            // The tap can only be created once the user grants Accessibility, and there's
            // no notification for that — poll until it takes.
            retryActivation()
        }

        // Write the dashboard up front so the menu item always opens something, even
        // before the first dictation.
        RunLog.regenerate()

        // Parakeet's models take a moment to load from disk, and that cost lands on whichever
        // dictation touches them first — so the first hold after every launch would stall
        // with the HUD showing nothing. Warm them in the background instead, or trigger
        // auto-download if a Parakeet engine is chosen.
        let willUseParakeet = Settings.shared.compareMode || Settings.shared.engine.requiresParakeetModel
        if willUseParakeet {
            if ParakeetModels.isDownloaded {
                Task.detached(priority: .utility) {
                    _ = try? await ParakeetModels.shared.models()
                }
            } else {
                ParakeetDownloadManager.shared.startDownloadIfNeeded()
            }
        }

        // Every `make install` relaunches the app and drops its windows. Restoring the
        // window when it was open last time keeps it from vanishing on each rebuild.
        if UserDefaults.standard.bool(forKey: "comparisonWindowOpen") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                Self.showComparisonWindow()
            }
        }

        observeState()
        observeWindowVisibility()
        Log.app.info("Murmur ready — hold \(Settings.shared.pushToTalkKey.displayName) to dictate")
    }

    /// Listens for window close notifications to switch to background accessory mode when no windows remain.
    private func observeWindowVisibility() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                self?.checkVisibleWindowsAndAdjustPolicy()
            }
        }
    }

    @MainActor
    func checkVisibleWindowsAndAdjustPolicy() {
        let visibleWindows = NSApp.windows.filter { window in
            !(window is NSPanel) && window.isVisible && window.canBecomeMain
        }
        if visibleWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Closes all open document windows and hides the app from the Dock and ⌘Tab switcher.
    @MainActor
    static func closeAllWindowsAndHideFromDock() {
        for window in NSApp.windows where !(window is NSPanel) {
            window.close()
        }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Raises the main window and restores regular Dock and ⌘Tab presence.
    @MainActor
    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if let existing = NSApp.windows.first(where: { !($0 is NSPanel) && ($0.title.contains("Murmur") || $0.identifier?.rawValue == "main") }) {
            existing.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.showMainWindow()
        return true
    }

    /// `murmuryt://clear` and `murmuryt://show`, used by the legacy HTML dashboard and
    /// as a scriptable way to raise the window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "murmuryt" {
            switch url.host {
            case "clear":
                RunLog.clear()
                RunStore.shared.reload()
            case "show":
                Self.showComparisonWindow()
            case "main", "open":
                Self.showMainWindow()
            default:
                break
            }
        }
    }

    /// Raises the comparison window without needing SwiftUI's `openWindow` environment
    /// value — usable from the app delegate and from a URL handler.
    static func showComparisonWindow() {
        NSApp.setActivationPolicy(.regular)
        RunStore.shared.reload()
        if let existing = NSApp.windows.first(where: { $0.title == "Engine comparison" }) {
            existing.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let isOpen = NSApp.windows.contains { $0.title == "Engine comparison" && $0.isVisible }
        UserDefaults.standard.set(isOpen, forKey: "comparisonWindowOpen")
        controller.deactivate()
    }

    /// Shows and hides the HUD in step with the controller's state.
    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.state.isActive {
                    self.hud?.present()
                } else {
                    self.hud?.dismiss()
                }
                self.observeState()
            }
        }
    }

    private func retryActivation() {
        Task { @MainActor in
            while !Permissions.hasAccessibility {
                try? await Task.sleep(for: .seconds(1))
            }
            controller.activate()
            Log.app.info("Accessibility granted — hotkey armed")
        }
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @Environment(\.openWindow) private var openWindow
    @State private var downloadManager = ParakeetDownloadManager.shared

    private var parakeetStatus: String {
        switch downloadManager.status {
        case .downloading(let progress, _):
            return "Downloading Parakeet (\(Int(progress * 100))%)…"
        case .downloaded:
            return "Parakeet models installed ✓"
        case .notDownloaded:
            return "Download Parakeet models (~470 MB)…"
        case .failed:
            return "Download failed — Retry"
        }
    }

    var body: some View {
        Button("Open Murmur") {
            AppDelegate.showMainWindow()
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")

        Text("Hold \(settings.pushToTalkKey.displayName) to dictate")

        Divider()

        Picker("Push-to-talk key", selection: Binding(
            get: { settings.pushToTalkKey },
            set: { key in
                settings.pushToTalkKey = key
                controller.reloadHotkey()
            }
        )) {
            ForEach(PushToTalkKey.allCases, id: \.self) { key in
                Text(key.displayName).tag(key)
            }
        }

        Toggle("Compare mode (all engines)", isOn: $settings.compareMode)

        if !settings.compareMode {
            Picker("Engine", selection: Binding(
                get: { settings.engine },
                set: { choice in
                    settings.engine = choice
                    if choice.requiresParakeetModel {
                        downloadManager.startDownloadIfNeeded()
                    }
                }
            )) {
                ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
        }

        Toggle("Clean up text", isOn: $settings.cleanupEnabled)

        if settings.cleanupEnabled {
            Toggle("Smart AI cleanup (Experimental)", isOn: $settings.smartCleanup)
                .disabled(!FoundationModelFormatter.isAvailable)
            if let reason = FoundationModelFormatter.unavailableReason {
                Text(reason).font(.caption)
            }
        }

        Toggle("Sound", isOn: $settings.soundEnabled)

        Toggle("Open at login", isOn: Binding(
            get: { settings.launchAtLogin },
            set: { settings.launchAtLogin = $0 }
        ))

        Divider()

        Button("Show comparison window") {
            RunStore.shared.reload()
            openWindow(id: "comparison")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("d")

        if settings.engine.requiresParakeetModel {
            Button(parakeetStatus) {
                downloadManager.startDownloadIfNeeded()
            }
            .disabled(downloadManager.status == .downloaded || downloadManager.status.isDownloading)
        }

        if !Permissions.hasAccessibility {
            Button("Grant Accessibility…") { Permissions.openAccessibilitySettings() }
        }
        if !Permissions.hasMicrophone {
            Button("Grant Microphone…") { Permissions.openMicrophoneSettings() }
        }

        Button("Quit Murmur") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
