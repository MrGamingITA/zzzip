import Foundation

enum EngineError: Error, Equatable {
    case passwordRequired
    case wrongPassword
    case corrupted(String)
    case diskFull
    case missingVolume(String)
    case cancelled
    case unsupportedFormat
    case failed(code: Int32, message: String)

    var userMessage: String {
        switch self {
        case .passwordRequired: return String(localized: "This archive is protected by a password.")
        case .wrongPassword: return String(localized: "The password is wrong.")
        case .corrupted(let d): return String(localized: "The archive is damaged: \(d)")
        case .diskFull: return String(localized: "There is not enough space on the disk.")
        case .missingVolume(let n): return String(localized: "A part of the multi-volume archive “\(n)” is missing.")
        case .cancelled: return String(localized: "The operation was cancelled.")
        case .unsupportedFormat: return String(localized: "This file is not an archive or its format is not supported.")
        case .failed(_, let m): return m.isEmpty ? String(localized: "The operation failed.") : m
        }
    }
}

extension EngineError: LocalizedError {
    var errorDescription: String? { userMessage }
}

enum ErrorMapper {
    static func isVolumeName(_ name: String) -> Bool {
        let l = name.lowercased()
        return l.range(of: #"\.(\d{3}|z\d{2}|r\d{2})$"#, options: .regularExpression) != nil
            || l.range(of: #"\.part\d+\.rar$"#, options: .regularExpression) != nil
    }

    static func map(exitCode: Int32, stderr: String, passwordProvided: Bool, archiveName: String) -> EngineError? {
        if exitCode == 0 || exitCode == 1 { return nil }
        let s = stderr
        let wrongPw = s.contains("Wrong password") || s.contains("Cannot open encrypted archive")
        if wrongPw { return passwordProvided ? .wrongPassword : .passwordRequired }
        if exitCode == 255 && s.contains("Break signaled") && !passwordProvided { return .passwordRequired }
        if exitCode == 255 { return .cancelled }
        if s.contains("No space left") || s.contains("not enough space") || s.contains("errno=28") { return .diskFull }
        if s.contains("Unexpected end of archive") || s.contains("Missing volume") {
            return isVolumeName(archiveName) ? .missingVolume(archiveName) : .corrupted(firstErrorLine(s))
        }
        if s.contains("Is not archive") || s.contains("Can not open the file as archive") || s.contains("Cannot open the file as") {
            return .unsupportedFormat
        }
        if s.contains("Data Error") || s.contains("CRC Failed") || s.contains("Headers Error") || s.contains("Unsupported Method") {
            return .corrupted(firstErrorLine(s))
        }
        return .failed(code: exitCode, message: s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func firstErrorLine(_ s: String) -> String {
        s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("ERROR") || $0.contains("Error") || $0.contains("Failed") || $0.contains("Unexpected") }
            .map { $0.replacingOccurrences(of: "ERROR: ", with: "") } ?? ""
    }
}
