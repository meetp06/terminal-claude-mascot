// Spawns and supervises the Python `agentd` sidecar, and resolves the
// WebSocket URL + token to connect with.
//
// Resolution order:
//   1. If a sidecar is already reachable (token file exists), just use it.
//   2. Otherwise spawn one, discovering a Python interpreter, and parse the
//      `PETOS_READY ws://... token=...` line it prints on stdout.
//   3. If spawning fails, fall back to the default URL + token file.
import Foundation

final class SidecarManager {
    private var process: Process?
    private let tokenPath = ("~/.petos/token" as NSString).expandingTildeInPath
    private let defaultURL = "ws://127.0.0.1:8765"

    /// Called once with a ready-to-use `ws://host:port/ws?token=...` URL.
    func start(_ onReady: @escaping (String) -> Void) {
        // Already-running sidecar? Use its token immediately.
        if let tok = existingToken() {
            onReady(wsURL(base: defaultURL, token: tok))
            // still (re)spawn in background if not running, but don't block
        }
        spawn(onReady: onReady)
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func existingToken() -> String? {
        guard let s = try? String(contentsOfFile: tokenPath, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func wsURL(base: String, token: String) -> String {
        "\(base)/ws?token=\(token)"
    }

    private func discoverPython() -> String? {
        if let p = ProcessInfo.processInfo.environment["PETOS_PYTHON"], !p.isEmpty {
            return p
        }
        var candidates: [String] = []
        // Prefer the venv vendored inside the .app bundle (packaged builds).
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("agentd-venv/bin/python3").path)
            candidates.append(res.appendingPathComponent("agentd-venv/bin/python").path)
        }
        candidates += [
            repoRoot().appendingPathComponent("agentd/.venv/bin/python").path,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    // Where the `agentd` package lives: bundled Resources first, else repo.
    private func srcPath() -> String {
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("agentd/src")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled.path }
        }
        return repoRoot().appendingPathComponent("agentd/src").path
    }

    // Best-effort repo root: the app runs from .build/... during `swift run`.
    private func repoRoot() -> URL {
        if let env = ProcessInfo.processInfo.environment["PETOS_REPO"] {
            return URL(fileURLWithPath: env)
        }
        // Walk up from the executable looking for an `agentd` sibling folder.
        var dir = URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
            .deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("agentd").path) {
                return dir
            }
            dir.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func spawn(onReady: @escaping (String) -> Void) {
        guard let python = discoverPython() else {
            NSLog("PetOS: no Python interpreter found; expecting an already-running sidecar")
            return
        }
        let root = repoRoot()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = ["-m", "agentd"]
        var env = ProcessInfo.processInfo.environment
        // Make the package importable whether or not it was pip-installed.
        env["PYTHONPATH"] = srcPath() + ":" + (env["PYTHONPATH"] ?? "")
        // Do not write __pycache__ into the signed app bundle at runtime.
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        proc.environment = env
        proc.currentDirectoryURL = root

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = outPipe

        var delivered = false
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            for line in s.split(separator: "\n") {
                if line.contains("PETOS_READY"), !delivered,
                   let tok = Self.parseToken(String(line)),
                   let base = Self.parseBase(String(line)) {
                    delivered = true
                    DispatchQueue.main.async { onReady(base + "?token=" + tok) }
                }
            }
        }

        do {
            try proc.run()
            process = proc
            NSLog("PetOS: launched sidecar via \(python)")
        } catch {
            NSLog("PetOS: failed to launch sidecar: \(error)")
        }
    }

    // Parses "PETOS_READY ws://127.0.0.1:8765/ws token=abc"
    static func parseToken(_ line: String) -> String? {
        guard let r = line.range(of: "token=") else { return nil }
        return String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
    static func parseBase(_ line: String) -> String? {
        guard let r = line.range(of: "ws://") else { return nil }
        let rest = line[r.lowerBound...]
        guard let sp = rest.firstIndex(of: " ") else { return nil }
        return String(rest[..<sp])  // e.g. ws://127.0.0.1:8765/ws
    }
}
