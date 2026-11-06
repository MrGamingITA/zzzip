import Foundation

struct SevenZip: Sendable {
    let executable: URL

    /// The `7zz` binary shipped in the app's Resources (tests are hosted in the app, so Bundle.main works there too).
    static var bundledExecutable: URL {
        Bundle.main.url(forResource: "7zz", withExtension: nil)!
    }

    static var bundled: SevenZip { SevenZip(executable: bundledExecutable) }

    static func passwordArgs(_ pw: String?) -> [String] { pw.map { ["-p\($0)"] } ?? [] }

    /// Runs 7zz. stdin is always /dev/null so password prompts fail instead of hanging.
    @discardableResult
    func run(_ args: [String], cwd: URL? = nil, stdoutTo: FileHandle? = nil, stdinFrom: FileHandle? = nil,
             progress: ((Double) -> Void)? = nil, cancel: CancelToken? = nil,
             failOnWarning: Bool = false, passwordProvided: Bool? = nil, archiveName: String = "") async throws -> (stdout: String, stderr: String) {
        if cancel?.isCancelled == true { throw EngineError.cancelled }
        let p = Process()
        p.executableURL = executable
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        p.standardInput = stdinFrom ?? FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = stdoutTo ?? outPipe
        p.standardError = errPipe

        let outBuf = Locked(Data()), errBuf = Locked(Data())
        if stdoutTo == nil {
            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty else { return }
                outBuf.mutate { $0.append(d) }
                if let progress, let v = ProgressParser.lastPercent(in: String(decoding: d, as: UTF8.self)) { progress(v) }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty { errBuf.mutate { $0.append(d) } }
        }

        let status: Int32 = try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { proc in cont.resume(returning: proc.terminationStatus) }
            do { try p.run() } catch { p.terminationHandler = nil; cont.resume(throwing: error); return }
            cancel?.onCancel { if p.isRunning { p.terminate() } }
        }
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        if stdoutTo == nil { outBuf.mutate { $0.append(outPipe.fileHandleForReading.readDataToEndOfFile()) } }
        errBuf.mutate { $0.append(errPipe.fileHandleForReading.readDataToEndOfFile()) }

        let out = String(decoding: outBuf.value, as: UTF8.self)
        let err = String(decoding: errBuf.value, as: UTF8.self)
        if cancel?.isCancelled == true { throw EngineError.cancelled }
        let switches = args.prefix { $0 != "--" }
        let pwGiven = passwordProvided ?? switches.contains { $0.hasPrefix("-p") && $0.count > 2 }
        if let e = ErrorMapper.map(exitCode: status, stderr: err, passwordProvided: pwGiven, archiveName: archiveName) { throw e }
        if status == 1 && failOnWarning {
            let msg = err.split(separator: "\n").filter { $0.contains("WARNING") || $0.contains("errno") }.joined(separator: "\n")
            throw EngineError.failed(code: 1, message: String(localized: "Some files could not be read:") + "\n" + (msg.isEmpty ? err : msg))
        }
        if status == 1 || status == 0 { progress?(1) }
        return (out, err)
    }

    func list(_ archive: URL, password: String?) async throws -> ArchiveInfo {
        let (out, _) = try await run(["l", "-slt", "-sccUTF-8"] + Self.passwordArgs(password) + ["--", archive.path],
                                     archiveName: archive.lastPathComponent)
        do { return try ListingParser.parse(out, archiveName: archive.lastPathComponent) } catch { throw EngineError.unsupportedFormat }
    }

    func test(_ archive: URL, password: String?, progress: ((Double) -> Void)? = nil, cancel: CancelToken? = nil) async throws {
        try await run(["t", "-bsp1", "-bb0"] + Self.passwordArgs(password) + ["--", archive.path],
                      progress: progress, cancel: cancel, archiveName: archive.lastPathComponent)
    }

    func extract(_ archive: URL, items: [String], to dir: URL, password: String?,
                 progress: ((Double) -> Void)? = nil, cancel: CancelToken? = nil) async throws {
        try await run(["x", "-y", "-bsp1", "-bb0", "-spd", "-o" + dir.path] + Self.passwordArgs(password) + ["--", archive.path] + items,
                      progress: progress, cancel: cancel, archiveName: archive.lastPathComponent)
    }
}

final class Locked<T>: @unchecked Sendable {
    private var v: T; private let l = NSLock()
    init(_ v: T) { self.v = v }
    var value: T { l.lock(); defer { l.unlock() }; return v }
    func mutate(_ f: (inout T) -> Void) { l.lock(); f(&v); l.unlock() }
}
