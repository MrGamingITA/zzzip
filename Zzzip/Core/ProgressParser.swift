import Foundation

enum ProgressParser {
    private static let regex = try! NSRegularExpression(pattern: #"(\d{1,3})%"#)

    /// Last `NN%` in a chunk of `-bsp1` output, as 0…1.
    static func lastPercent(in chunk: String) -> Double? {
        let ns = chunk as NSString
        guard let m = regex.matches(in: chunk, range: NSRange(location: 0, length: ns.length)).last,
              let v = Int(ns.substring(with: m.range(at: 1))) else { return nil }
        return min(Double(v), 100) / 100
    }
}
