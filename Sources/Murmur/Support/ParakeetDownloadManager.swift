import FluidAudio
import Foundation
import Observation

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
        activeTask = Task {
            do {
                Log.speech.info("ParakeetDownloadManager: starting download and load...")
                let models = try await AsrModels.downloadAndLoad(
                    version: .v3,
                    encoderPrecision: .int8,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
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
                            self?.status = .downloading(progress: fraction, stage: stage)
                        }
                    }
                )

                // Cache in memory so next dictation is instantaneous
                await ParakeetModels.shared.setLoadedModels(models)

                self.status = .downloaded
                Log.speech.info("ParakeetDownloadManager: download and initialization complete")
            } catch {
                Log.speech.error("ParakeetDownloadManager failed: \(error.localizedDescription)")
                self.status = .failed(error.localizedDescription)
            }
            self.activeTask = nil
        }
    }
}
