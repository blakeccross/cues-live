import Foundation
import SwiftData

enum TimecodeSettingsStore {
    static func ensureConfig(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<TimecodeSettings>())) ?? []
        guard existing.isEmpty else { return }
        context.insert(TimecodeSettings())
        try? context.save()
    }

    static func settings(in context: ModelContext) -> TimecodeSettings {
        ensureConfig(in: context)
        if let existing = (try? context.fetch(FetchDescriptor<TimecodeSettings>()))?.first {
            return existing
        }
        let created = TimecodeSettings()
        context.insert(created)
        try? context.save()
        return created
    }

    static func snapshot(in context: ModelContext) -> TimecodeSettingsSnapshot {
        TimecodeSettingsSnapshot(settings(in: context))
    }

    static func save(_ mutate: (TimecodeSettings) -> Void, in context: ModelContext) {
        let model = settings(in: context)
        mutate(model)
        model.startingHour = TimecodeSettings.clampedHour(model.startingHour)
        try? context.save()
    }
}
