import Foundation
import Observation

/// The section names offered when editing a marker on the timeline. The list is the user's own,
/// shared by every song, ordered as they arrange it, and kept in user defaults.
@MainActor
@Observable
final class SectionNameLibrary {
    static let shared = SectionNameLibrary()

    static let defaultNames = [
        "Intro", "Verse", "Pre-Chorus", "Chorus", "Bridge", "Tag",
        "Ending", "Interlude", "Instrumental", "Outro", "Solo",
    ]

    static let storageKey = "sectionNameLibrary"

    private(set) var names: [String]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = defaults.stringArray(forKey: Self.storageKey) ?? Self.defaultNames
    }

    /// Whether `name` is non-empty and not already in the list, ignoring case. `index` is the
    /// entry being renamed, which may keep its own name.
    func isNameAvailable(_ name: String, excluding index: Int? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !names.indices.contains { other in
            other != index && names[other].caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    /// Appends `name`. Returns `false`, leaving the list unchanged, when it is empty or a duplicate.
    @discardableResult
    func add(_ name: String) -> Bool {
        guard isNameAvailable(name) else { return false }
        names.append(name.trimmingCharacters(in: .whitespacesAndNewlines))
        save()
        return true
    }

    /// Renames the entry at `index`. Returns `false` when the new name is empty or a duplicate.
    @discardableResult
    func rename(at index: Int, to name: String) -> Bool {
        guard names.indices.contains(index), isNameAvailable(name, excluding: index) else { return false }
        names[index] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
        return true
    }

    func remove(atOffsets offsets: IndexSet) {
        names.remove(atOffsets: offsets)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        names.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func restoreDefaults() {
        names = Self.defaultNames
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func save() {
        defaults.set(names, forKey: Self.storageKey)
    }
}
