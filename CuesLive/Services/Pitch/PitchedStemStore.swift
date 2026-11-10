import Foundation

enum PitchedStemStore {
    static let folderName = "Pitched"

    static func directory(forProjectFile projectURL: URL) -> URL {
        projectURL
            .deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func fileURL(trackID: UUID, semitones: Int, projectURL: URL) -> URL {
        directory(forProjectFile: projectURL)
            .appendingPathComponent("\(trackID.uuidString)-\(semitones).caf")
    }

    static func removeAll(projectURL: URL) {
        let directory = directory(forProjectFile: projectURL)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
