import Foundation

@MainActor
@Observable
final class InputMappingStore {
    static let shared = InputMappingStore()

    private enum Keys {
        static let mappings = "inputMapping.mappings"
    }

    private let defaults: UserDefaults
    private(set) var mappings: [InputMapping]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mappings = Self.load(from: defaults)
    }

    func mapping(for action: MappableLiveAction) -> InputMapping? {
        mappings.first { $0.action == action }
    }

    func action(forKey key: KeyBinding) -> MappableLiveAction? {
        mappings.first { mapping in
            mapping.key.map { key.matches($0) } ?? false
        }?.action
    }

    func action(forMIDI midi: MIDINoteBinding) -> MappableLiveAction? {
        mappings.first { mapping in
            mapping.midi.map { midi.matches($0) } ?? false
        }?.action
    }

    @discardableResult
    func assignKey(_ key: KeyBinding, to target: MappableLiveAction) -> MappableLiveAction? {
        let displaced = action(forKey: key)
        if let displaced, displaced != target {
            clearKey(for: displaced)
        }
        upsert(target) { mapping in
            mapping.key = key
        }
        return displaced == target ? nil : displaced
    }

    @discardableResult
    func assignMIDI(_ midi: MIDINoteBinding, to target: MappableLiveAction) -> MappableLiveAction? {
        let displaced = action(forMIDI: midi)
        if let displaced, displaced != target {
            clearMIDI(for: displaced)
        }
        upsert(target) { mapping in
            mapping.midi = midi
        }
        return displaced == target ? nil : displaced
    }

    func clearKey(for action: MappableLiveAction) {
        upsert(action) { mapping in
            mapping.key = nil
        }
        removeIfEmpty(action)
    }

    func clearMIDI(for action: MappableLiveAction) {
        upsert(action) { mapping in
            mapping.midi = nil
        }
        removeIfEmpty(action)
    }

    func remove(_ action: MappableLiveAction) {
        mappings.removeAll { $0.action == action }
        persist()
    }

    var songMappings: [InputMapping] {
        mappings
            .filter { $0.action.songIndex != nil }
            .sorted { $0.action.sortOrder < $1.action.sortOrder }
    }

    private func upsert(_ action: MappableLiveAction, mutate: (inout InputMapping) -> Void) {
        if let index = mappings.firstIndex(where: { $0.action == action }) {
            mutate(&mappings[index])
        } else {
            var mapping = InputMapping(action: action)
            mutate(&mapping)
            mappings.append(mapping)
        }
        persist()
    }

    private func removeIfEmpty(_ action: MappableLiveAction) {
        mappings.removeAll { $0.action == action && $0.isEmpty }
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(mappings)
            defaults.set(data, forKey: Keys.mappings)
        } catch {
            assertionFailure("Failed to encode input mappings: \(error)")
        }
    }

    private static func load(from defaults: UserDefaults) -> [InputMapping] {
        guard let data = defaults.data(forKey: Keys.mappings) else {
            return defaultMappings
        }
        return (try? JSONDecoder().decode([InputMapping].self, from: data)) ?? []
    }

    static var defaultMappings: [InputMapping] {
        [
            InputMapping(action: .playPause, key: .unmodified(keyCode: 49, character: " ", keyName: "Space")),
            InputMapping(action: .stop, key: .unmodified(keyCode: 1, character: "s", keyName: "S")),
            InputMapping(action: .fade, key: .unmodified(keyCode: 3, character: "f", keyName: "F")),
            InputMapping(action: .loop, key: .unmodified(keyCode: 37, character: "l", keyName: "L")),
        ]
    }
}
