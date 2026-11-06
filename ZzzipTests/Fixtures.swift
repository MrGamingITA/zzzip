import Foundation
@testable import Zzzip

enum Fixtures {
    static func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("zzzip-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Writes files into a temp source dir, then archives them with 7zz. Returns the archive URL.
    @discardableResult
    static func make(_ format: String, files: [String: String], name: String = "test", password: String? = nil,
                     encryptHeaders: Bool = false, extraArgs: [String] = [], in dir: URL? = nil) throws -> URL {
        let base = dir ?? tempDir()
        let src = base.appendingPathComponent("src-\(UUID().uuidString)")
        for (path, content) in files {
            let u = src.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: u, atomically: true, encoding: .utf8)
        }
        let out = base.appendingPathComponent("\(name).\(format)")
        var args = ["a", "-t\(format)", out.path, "-spd"]
        if let password { args.append("-p\(password)") }
        if encryptHeaders { args.append("-mhe=on") }
        args += extraArgs
        args.append("--")
        args += try FileManager.default.contentsOfDirectory(atPath: src.path)
        try run7zz(args, cwd: src)
        try FileManager.default.removeItem(at: src)
        return out
    }

    @discardableResult
    static func run7zz(_ args: [String], cwd: URL? = nil) throws -> Int32 {
        let p = Process()
        p.executableURL = SevenZip.bundledExecutable
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    static func listing(_ dir: URL) -> [String] {
        let fm = FileManager.default
        guard let e = fm.enumerator(atPath: dir.path) else { return [] }
        return (e.allObjects as! [String]).sorted()
    }
}
