import Foundation

struct OCRHeuristics {
    static func parseCandidate(from lines: [String]) -> (artist: String?, album: String?, catno: String?) {
        let cleaned = lines.map { line -> String in
            line.replacingOccurrences(of: "(Deluxe)", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "(Remastered)", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return (nil, nil, nil) }
        if cleaned.count >= 2 {
            return (cleaned[0], cleaned[1], findCatalogNumber(in: cleaned))
        } else {
            let components = cleaned[0].components(separatedBy: "-")
            if components.count >= 2 {
                return (components[0].trimmingCharacters(in: .whitespaces), components[1].trimmingCharacters(in: .whitespaces), findCatalogNumber(in: cleaned))
            }
        }
        return (cleaned.first, cleaned.dropFirst().first, findCatalogNumber(in: cleaned))
    }

    private static func findCatalogNumber(in lines: [String]) -> String? {
        let pattern = #"[A-Z]{2,}-?\d{3,}"#
        let regex = try? NSRegularExpression(pattern: pattern)
        for line in lines {
            let range = NSRange(location: 0, length: line.utf16.count)
            if let match = regex?.firstMatch(in: line, options: [], range: range), let swiftRange = Range(match.range, in: line) {
                return String(line[swiftRange])
            }
        }
        return nil
    }
}
