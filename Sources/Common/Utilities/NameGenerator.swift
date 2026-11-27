import Foundation

enum NameGenerator {
    static func generateNextName(existingNames: [String], baseName: String = "NoName") -> String {
        var counter = 1
        while true {
            let suffix = String(format: "%02d", counter)
            let candidate = "\(baseName)_\(suffix)"
            let exists = existingNames.contains { $0.compare(candidate, options: .caseInsensitive) == .orderedSame }
            if !exists {
                return candidate
            }
            counter += 1
        }
    }
}
