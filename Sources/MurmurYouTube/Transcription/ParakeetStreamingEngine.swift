import AVFoundation
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT 0.6B running in real-time streaming mode on Apple Neural Engine.
///
/// Delivers live streaming partial hypotheses to the HUD during capture by running fast
/// periodic incremental decoding passes on the Neural Engine (~100× realtime, ~20ms per pass).
actor ParakeetStreamingEngine: TranscriptionEngine {
    private var samples: [Float] = []
    private var continuation: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?
    private var streamingTask: Task<Void, Never>?
    private var hasFinished = false
    private var isTranscribing = false
    private var needsTranscribe = false

    /// Defaults to 16 kHz mono float32 — exactly what Parakeet is trained on.
    private let converter = AudioConverter()

    func preferredInputFormat() async -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        samples.removeAll(keepingCapacity: true)
        hasFinished = false
        isTranscribing = false
        needsTranscribe = false

        let (stream, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
        self.continuation = continuation

        // Force model load up-front so the first audio chunk doesn't stall
        _ = try await ParakeetModels.shared.manager()

        // Start background periodic transcription loop for live partials
        streamingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { break }
                await self.performPeriodicTranscription()
            }
        }

        Log.speech.info("ParakeetStreamingEngine started")
        return stream
    }

    func feed(_ chunk: AudioChunk) async {
        guard !hasFinished else { return }
        let buffer = chunk.buffer
        guard buffer.frameLength > 0 else { return }

        do {
            let newSamples = try converter.resampleBuffer(buffer)
            samples.append(contentsOf: newSamples)
            needsTranscribe = true
        } catch {
            Log.speech.error("ParakeetStreaming: audio conversion failed — \(error.localizedDescription)")
        }
    }

    private func performPeriodicTranscription() async {
        guard !hasFinished, needsTranscribe, !isTranscribing else { return }
        // Minimum window: Parakeet needs at least 0.25s of speech (4000 samples)
        guard samples.count >= 4_000 else { return }

        needsTranscribe = false
        isTranscribing = true
        let snapshot = samples

        do {
            let manager = try await ParakeetModels.shared.manager()
            var decoderState = try TdtDecoderState()
            let result = try await manager.transcribe(snapshot, decoderState: &decoderState)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if !hasFinished && !text.isEmpty {
                continuation?.yield(TranscriptionChunk(text: text, isFinal: false))
            }
        } catch {
            Log.speech.debug("ParakeetStreaming: interim pass skipped — \(error.localizedDescription)")
        }

        isTranscribing = false
    }

    func finish() async {
        guard !hasFinished else { return }
        hasFinished = true

        streamingTask?.cancel()
        streamingTask = nil

        defer {
            continuation?.finish()
            continuation = nil
            samples.removeAll(keepingCapacity: true)
        }

        // Parakeet's encoder needs a minimum window; a stray tap of the key isn't speech.
        guard samples.count >= 1_600 else {
            Log.speech.info("ParakeetStreaming: skipped — only \(self.samples.count) samples captured")
            return
        }

        do {
            let manager = try await ParakeetModels.shared.manager()
            var decoderState = try TdtDecoderState()
            let started = Date()
            let result = try await manager.transcribe(samples, decoderState: &decoderState)
            let elapsed = Date().timeIntervalSince(started)
            let audioSeconds = Double(samples.count) / 16_000

            Log.speech.info("""
                ParakeetStreaming: \(audioSeconds, format: .fixed(precision: 1))s audio in \
                \(elapsed, format: .fixed(precision: 2))s (\(audioSeconds / max(elapsed, 0.0001), format: .fixed(precision: 0))× realtime)
                """)

            continuation?.yield(
                TranscriptionChunk(
                    text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isFinal: true
                )
            )
        } catch {
            Log.speech.error("ParakeetStreaming finalize failed: \(error.localizedDescription)")
            continuation?.finish(throwing: error)
            continuation = nil
        }
    }
}
