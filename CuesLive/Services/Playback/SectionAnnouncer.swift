import AVFoundation
import Foundation

/// Pre-renders section names from bundled guide samples and plays them through the shared audio engine.
@Observable
@MainActor
final class SectionAnnouncer {
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var preparedNames: Set<String> = []
    private var pendingNames: [String] = []
    private var pendingNameSet: Set<String> = []
    private var playbackRequests: Set<String> = []
    private var renderTask: Task<Void, Never>?

    func prepare(names: [String]) {
        let unique = Set(
            names
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        preparedNames = unique

        let staleKeys = cache.keys.filter { !unique.contains($0) }
        for key in staleKeys {
            cache.removeValue(forKey: key)
        }

        pendingNames.removeAll {
            !unique.contains($0) && !playbackRequests.contains($0)
        }
        pendingNameSet = Set(pendingNames)

        for name in unique where cache[name] == nil {
            enqueue(name)
        }
        startRenderingIfNeeded()
    }

    func announce(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let buffer = cache[trimmed] {
            AudioEngineManager.shared.playAnnouncement(buffer)
            return
        }

        playbackRequests.insert(trimmed)
        enqueue(trimmed, prioritized: true)
        startRenderingIfNeeded()
    }

    func clearCache() {
        preparedNames.removeAll()
        pendingNames.removeAll()
        pendingNameSet.removeAll()
        playbackRequests.removeAll()
        cache.removeAll()
    }

    private func enqueue(_ name: String, prioritized: Bool = false) {
        guard cache[name] == nil, pendingNameSet.insert(name).inserted else { return }
        if prioritized {
            pendingNames.insert(name, at: 0)
        } else {
            pendingNames.append(name)
        }
    }

    private func startRenderingIfNeeded() {
        guard renderTask == nil, !pendingNames.isEmpty else { return }
        renderTask = Task { @MainActor [weak self] in
            await self?.processRenderQueue()
        }
    }

    private func processRenderQueue() async {
        while !pendingNames.isEmpty {
            let name = pendingNames.removeFirst()
            pendingNameSet.remove(name)

            if cache[name] == nil,
               let buffer = await SpeechSampleRenderer.renderAnnouncementBuffer(for: name),
               preparedNames.contains(name) || playbackRequests.contains(name) {
                cache[name] = buffer
            }

            if let buffer = cache[name], playbackRequests.remove(name) != nil {
                AudioEngineManager.shared.playAnnouncement(buffer)
            }
        }
        renderTask = nil
    }
}
