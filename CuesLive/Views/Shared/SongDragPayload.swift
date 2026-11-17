import Foundation

/// Carries library songs across a drag, into a song folder or the setlist. A tagged string keeps it
/// a plain `Transferable` without needing a custom exported UTType. One payload holds every song in
/// the drag, so dragging a multi-selection moves the whole selection.
enum SongDragPayload {
    private static let prefix = "cueslive-song:"
    private static let separator: Character = ","

    static func string(for songIDs: [UUID]) -> String {
        prefix + songIDs.map(\.uuidString).joined(separator: String(separator))
    }

    /// The songs in a payload, in drag order. Empty for any string that is not a song payload.
    static func songIDs(from string: String) -> [UUID] {
        guard string.hasPrefix(prefix) else { return [] }
        return string.dropFirst(prefix.count)
            .split(separator: separator)
            .compactMap { UUID(uuidString: String($0)) }
    }

    static func songIDs(from providers: [NSItemProvider]) async -> [UUID] {
        var ids: [UUID] = []
        for provider in providers where provider.canLoadObject(ofClass: String.self) {
            let string: String? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    continuation.resume(returning: value)
                }
            }
            if let string {
                ids.append(contentsOf: songIDs(from: string))
            }
        }
        return ids
    }
}
