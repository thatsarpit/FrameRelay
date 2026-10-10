import Foundation
import Darwin

enum LoginManager {
    static let label = "media.voyd.FrameRelay"
    static var agentURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var enabled: Bool { FileManager.default.fileExists(atPath: agentURL.path) }
    private static func launchctl(_ args: [String]) throws -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = args
        p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit(); return p.terminationStatus
    }
    static func setEnabled(_ enabled: Bool) throws {
        let domain = "gui/\(getuid())"
        if !enabled {
            _ = try launchctl(["disable", "\(domain)/\(label)"])
            if FileManager.default.fileExists(atPath: agentURL.path) { try FileManager.default.removeItem(at: agentURL) }
            return
        }
        guard Bundle.main.bundleURL.pathExtension == "app", let executable = Bundle.main.executableURL else { throw NSError(domain: label, code: 1, userInfo: [NSLocalizedDescriptionKey: "Install FrameRelay.app before enabling login startup."]) }
        let dict: [String: Any] = ["Label": label, "ProgramArguments": [executable.path], "RunAtLoad": true, "KeepAlive": false, "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive"]
        try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try launchctl(["enable", "\(domain)/\(label)"])
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: agentURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: agentURL.path)
        let loaded = try launchctl(["print", "\(domain)/\(label)"]) == 0
        guard try loaded || launchctl(["bootstrap", domain, agentURL.path]) == 0 else { try? FileManager.default.removeItem(at: agentURL); throw NSError(domain: label, code: 2, userInfo: [NSLocalizedDescriptionKey: "macOS did not load the login agent. Check Login Items in System Settings."]) }
    }
}
