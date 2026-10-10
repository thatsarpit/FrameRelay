import Foundation
import Darwin

enum InputMode: String, Codable, CaseIterable, Identifiable {
    case rtmp = "RTMP listener"
    case rtsp = "RTSP camera"
    var id: String { rawValue }
}

struct NetworkInterface: Identifiable, Hashable {
    let name: String
    let address: String
    var id: String { name + address }
    var title: String { "\(name) · \(address)" }
    static func available() -> [NetworkInterface] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        var result: [NetworkInterface] = []
        var p = list
        while let current = p {
            let v = current.pointee
            if let a = v.ifa_addr, a.pointee.sa_family == UInt8(AF_INET), v.ifa_flags & UInt32(IFF_UP) != 0 {
                var value = UnsafeRawPointer(a).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var bytes = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &value, &bytes, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let ip = String(cString: bytes)
                    if Configuration.isPrivateAddress(ip) {
                        result.append(.init(name: String(cString: v.ifa_name), address: ip))
                    }
                }
            }
            p = v.ifa_next
        }
        return result.sorted { $0.name < $1.name }
    }
}

struct Configuration: Codable, Equatable {
    var cameraName = "My camera"
    var mode: InputMode = .rtmp
    var address = NetworkInterface.available().first?.address ?? ""
    var port = 1935
    var streamPath = "live/camera"
    var rtspURL = ""
    var recordClips = false
    var includeAudio = true
    var mirrorPreview = false
    var autoReconnect = true
    var startAtLogin = false
    var autoStartReceiver = false
    var recordingFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/FrameRelay").path
    var ffmpegPath = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") ? "/opt/homebrew/bin/ffmpeg" : "/usr/local/bin/ffmpeg"
    var minimumFreeGB = 2

    var endpoint: String { mode == .rtmp ? "rtmp://\(address):\(port)/\(streamPath)" : rtspURL }
    static func isPrivateAddress(_ ip: String) -> Bool {
        let segments = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 4, segments.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return false }
        let p = segments.compactMap { Int($0) }
        guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }) else { return false }
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1])) || ip == "127.0.0.1"
    }
    func validationError() -> String? {
        if !FileManager.default.isExecutableFile(atPath: ffmpegPath) { return "Choose an installed FFmpeg executable in Settings." }
        if mode == .rtmp {
            if !Self.isPrivateAddress(address) { return "Choose a private LAN address. Public and wildcard listeners are not supported." }
            if !(1024...65535).contains(port) { return "Use a port between 1024 and 65535." }
            if streamPath.isEmpty || streamPath.hasPrefix("/") || streamPath.contains("..") || streamPath.contains(where: { !$0.isASCII || !($0.isLetter || $0.isNumber || "/_-".contains($0)) }) {
                return "Use a path such as live/camera, with letters, numbers, /, _ or -."
            }
        } else {
            guard let u = URLComponents(string: rtspURL), ["rtsp", "rtsps"].contains(u.scheme ?? ""), u.host != nil else { return "Enter a complete rtsp:// or rtsps:// camera URL." }
            if u.user != nil || u.password != nil { return "Credential-bearing URLs are not supported in this preview. Use a credential-free trusted LAN endpoint." }
        }
        if recordClips && !recordingFolder.hasPrefix("/") { return "Choose a local recording folder." }
        if minimumFreeGB < 1 { return "Keep at least 1 GB of free space reserved." }
        return nil
    }
    func receiverArguments(capture: URL?) -> [String] {
        var args = ["-hide_banner", "-nostdin", "-nostats", "-loglevel", "info", "-rw_timeout", "15000000"]
        args += mode == .rtmp ? ["-listen", "1"] : ["-rtsp_transport", "tcp"]
        args += ["-i", endpoint]
        if let capture = capture {
            args += ["-map", "0:v:0"]
            if includeAudio { args += ["-map", "0:a?"] }
            args += ["-c", "copy", capture.path]
        }
        // Fixed BGRA frames for the virtual-camera sink; preview consumes the same frames.
        args += ["-map", "0:v:0", "-an", "-vf", "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30", "-pix_fmt", "bgra", "-f", "rawvideo", "pipe:1"]
        return args
    }
}
