import Foundation

public enum GhError: Error, Equatable {
    case loginFailed(String)
    case logoutFailed(String)
}

public struct GhBridge {
    public let ghPath: String

    public init(ghPath: String) {
        self.ghPath = ghPath
    }

    /// GUI apps get a minimal PATH, so look in the usual Homebrew locations.
    public static func discover(
        extraPaths: [String] = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    ) -> GhBridge? {
        for path in extraPaths where FileManager.default.isExecutableFile(atPath: path) {
            return GhBridge(ghPath: path)
        }
        return nil
    }

    struct ProcessResult {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    func run(_ args: [String], stdin input: String? = nil) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "GH_TOKEN")      // must not shadow the keychain
        env.removeValue(forKey: "GITHUB_TOKEN")
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let inPipe: Pipe? = input.map { _ in Pipe() }
        if let inPipe {
            process.standardInput = inPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        do {
            try process.run()
        } catch {
            return ProcessResult(status: 127, stdout: "", stderr: "\(error)")
        }
        if let input, let inPipe {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            inPipe.fileHandleForWriting.closeFile()
        }
        var stdoutData = Data()
        var stderrData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stdoutData = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            stderrData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.wait()
        process.waitUntilExit()
        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let stderr = String(decoding: stderrData, as: UTF8.self)
        return ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    public func isLoggedIn() -> Bool {
        run(["auth", "status", "--hostname", "github.com"]).status == 0
    }

    public func activate(token: String) throws {
        let result = run(["auth", "login", "--hostname", "github.com", "--with-token"], stdin: token)
        guard result.status == 0, isLoggedIn() else {
            throw GhError.loginFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func deactivate() throws {
        guard isLoggedIn() else { return }
        let result = run(["auth", "logout", "--hostname", "github.com"])
        guard result.status == 0, !isLoggedIn() else {
            throw GhError.logoutFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func currentToken() -> String? {
        let result = run(["auth", "token", "--hostname", "github.com"])
        guard result.status == 0 else { return nil }
        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
