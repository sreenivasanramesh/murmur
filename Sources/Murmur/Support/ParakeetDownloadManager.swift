import FluidAudio
import Foundation
import Observation
import os

/// Rate-limits high-frequency progress callbacks to a smooth UI frame cadence (~12 fps)
/// while guaranteeing immediate emission on phase / stage transitions.
private final class ProgressThrottler: @unchecked Sendable {
    private let interval: TimeInterval
    private var lastEmission: ContinuousClock.Instant = .now - .seconds(10)
    private var lastFraction: Double = -1
    private var lastStage: String = ""
    private let lock = NSLock()

    init(interval: TimeInterval = 0.08) {
        self.interval = interval
    }

    func shouldEmit(fraction: Double, stage: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if stage != lastStage {
            lastStage = stage
            lastEmission = .now
            lastFraction = fraction
            return true
        }

        let elapsed = ContinuousClock.now - lastEmission
        if elapsed >= .milliseconds(Int(interval * 1000)) && abs(fraction - lastFraction) >= 0.005 {
            lastEmission = .now
            lastFraction = fraction
            return true
        }
        return false
    }
}

/// Manages background download and initialization of Parakeet CoreML models.
@MainActor
@Observable
final class ParakeetDownloadManager {
    static let shared = ParakeetDownloadManager()

    enum Status: Equatable {
        case notDownloaded
        case downloading(progress: Double, stage: String)
        case downloaded
        case failed(String)

        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }
    }

    private(set) var status: Status

    private var activeTask: Task<Void, Never>?

    private init() {
        if ParakeetModels.isDownloaded {
            status = .downloaded
        } else {
            status = .notDownloaded
        }
    }

    /// Checks the current disk state and updates status.
    func refreshStatus() {
        if case .downloading = status { return }
        if ParakeetModels.isDownloaded {
            status = .downloaded
        } else {
            status = .notDownloaded
        }
    }

    /// Initiates background download if models are missing.
    func startDownloadIfNeeded() {
        if ParakeetModels.isDownloaded {
            status = .downloaded
            return
        }
        if case .downloading = status { return }

        startDownload()
    }

    func retry() {
        startDownload()
    }

    private func startDownload() {
        status = .downloading(progress: 0.05, stage: "Starting download (~470 MB)...")

        activeTask?.cancel()
        let manager = self
        activeTask = Task.detached(priority: .utility) {
            let throttler = ProgressThrottler(interval: 0.08)
            do {
                Log.speech.info("ParakeetDownloadManager: starting download and load...")
                let models = try await AsrModels.downloadAndLoad(
                    version: .v3,
                    encoderPrecision: .int8,
                    progressHandler: { progress in
                        let fraction = max(0.05, min(0.95, progress.fractionCompleted))
                        let stage: String
                        switch progress.phase {
                        case .listing:
                            stage = "Connecting to repository..."
                        case .downloading(let completed, let total):
                            stage = total > 0 ? "Downloading files (\(completed)/\(total))..." : "Downloading model weights..."
                        case .compiling(let modelName):
                            stage = "Compiling \(modelName) on Neural Engine..."
                        }

                        if throttler.shouldEmit(fraction: fraction, stage: stage) {
                            Task { @MainActor in
                                manager.status = .downloading(progress: fraction, stage: stage)
                            }
                        }
                    }
                )

                guard !Task.isCancelled else { return }

                // Cache in memory so next dictation is instantaneous
                await ParakeetModels.shared.setLoadedModels(models)

                await MainActor.run {
                    manager.status = .downloaded
                    manager.activeTask = nil
                }
                Log.speech.info("ParakeetDownloadManager: download and initialization complete")
            } catch {
                guard !Task.isCancelled else { return }
                Log.speech.error("ParakeetDownloadManager failed: \(error.localizedDescription)")
                await MainActor.run {
                    manager.status = .failed(error.localizedDescription)
                    manager.activeTask = nil
                }
            }
        }
    }
}
