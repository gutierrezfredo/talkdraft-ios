import Foundation

struct TranscriptSpeakerDetector {
    static func detectedSpeakers(in content: String, speakerNames: [String: String]?) -> [String] {
        let lines = content.components(separatedBy: "\n")
        var seen: [String] = []

        if let speakerNames, !speakerNames.isEmpty {
            for index in lines.indices {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                if isTranscriptSpeakerLine(in: lines, index: index), !seen.contains(trimmed) {
                    seen.append(trimmed)
                }
            }
            if !seen.isEmpty {
                return seen
            }
            return speakerNames.keys.sorted().map { speakerNames[$0] ?? $0 }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.range(of: #"^Speaker \d+$"#, options: .regularExpression) != nil,
               !seen.contains(trimmed) {
                seen.append(trimmed)
            }
        }
        if !seen.isEmpty {
            return seen
        }

        let pattern = /\[([^\]]+)\]:/
        for match in content.matches(of: pattern) {
            let key = String(match.output.1)
            if !seen.contains(key) {
                seen.append(key)
            }
        }
        return seen
    }

    static func isTranscriptSpeakerLine(in lines: [String], index: Int) -> Bool {
        let current = lines[index].trimmingCharacters(in: .whitespaces)
        guard !current.isEmpty else { return false }

        let previousIsSeparator = index == 0 || lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty
        guard previousIsSeparator else { return false }

        guard index + 1 < lines.count else { return false }
        let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard !next.isEmpty else { return false }

        if current.hasPrefix("• ") || current.hasPrefix("☐ ") || current.hasPrefix("☑ ") || current.hasPrefix("[") {
            return false
        }

        return true
    }
}
