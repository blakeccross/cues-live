import Foundation

/// Maps imported section locator names onto canonical preset labels when possible.
enum SongSectionNameNormalizer {
    private static var presetByKeyCache: [String: String]?

    private static let abbreviationExpansions: [String: String] = [
        "v": "verse",
        "c": "chorus",
        "ch": "chorus",
        "pc": "pre chorus",
        "pre": "pre chorus",
        "prechorus": "pre chorus",
        "post": "post chorus",
        "postchorus": "post chorus",
        "br": "bridge",
        "inst": "instrumental",
    ]

    static func canonicalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let key = lookupKey(trimmed)
        let presetByKey = presetsByKey()
        if let exact = presetByKey[key] {
            return exact
        }

        let (baseKey, number) = parseBaseAndNumber(from: key)
        let expandedBase = abbreviationExpansions[baseKey] ?? baseKey

        if let number {
            let numberedKey = "\(expandedBase) \(number)"
            if let match = presetByKey[numberedKey] {
                return match
            }
            return trimmed
        }

        if let match = presetByKey[expandedBase] {
            return match
        }

        return trimmed
    }

    /// Normalized lookup key used for preset matching and guide-sample filenames.
    static func lookupKey(_ raw: String) -> String {
        normalizeKey(raw)
    }

    private static func presetsByKey() -> [String: String] {
        if let presetByKeyCache {
            return presetByKeyCache
        }

        var lookup: [String: String] = [:]
        for name in SongSectionPresets.allCanonicalNames {
            lookup[normalizeKey(name)] = name
        }
        presetByKeyCache = lookup
        return lookup
    }

    private static func normalizeKey(_ raw: String) -> String {
        let camelExpanded = insertSpacesBeforeCapitals(raw)
        let separatorsNormalized = camelExpanded
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        return separatorsNormalized
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private static func insertSpacesBeforeCapitals(_ string: String) -> String {
        var result = ""
        for (index, character) in string.enumerated() {
            if index > 0, character.isUppercase {
                let previousIndex = string.index(string.startIndex, offsetBy: index - 1)
                let previous = string[previousIndex]
                if previous.isLowercase {
                    result.append(" ")
                }
            }
            result.append(character)
        }
        return result
    }

    private static func parseBaseAndNumber(from key: String) -> (base: String, number: Int?) {
        let parts = key.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 2, let last = parts.last, let number = Int(last) {
            let base = parts.dropLast().joined(separator: " ")
            return (base, number)
        }

        if let range = key.range(of: #"\d+$"#, options: .regularExpression) {
            let numberText = String(key[range])
            let base = String(key[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if let number = Int(numberText), !base.isEmpty {
                return (base, number)
            }
        }

        return (key, nil)
    }
}
