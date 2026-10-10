import Foundation
@main struct ConfigurationTests {
    static func main() {
        for ip in ["0.0.0.0", "8.8.8.8", "192.168.1.x.2", "192.168..1", "192.168.1.300", "10.1.2.3.4", "127.0.0.2"] { precondition(!Configuration.isPrivateAddress(ip), "accepted \(ip)") }
        for ip in ["127.0.0.1", "192.168.1.2", "10.0.0.5", "172.16.0.1", "172.31.255.254"] { precondition(Configuration.isPrivateAddress(ip)) }
        var c = Configuration(); c.address = "127.0.0.1"
        precondition(c.validationError() == nil)
        c.port = 80; precondition(c.validationError() != nil); c.port = 1935
        for path in ["../x", "/live", "live/test;touch", "live/a b", ""] { c.streamPath = path; precondition(c.validationError() != nil) }
        c.streamPath = "live/test"
        let preview = c.receiverArguments(capture: nil)
        precondition(!preview.contains("copy")); precondition(preview.last == "pipe:1")
        let record = c.receiverArguments(capture: URL(fileURLWithPath: "/tmp/a file.mkv"))
        precondition(record.contains("/tmp/a file.mkv")); precondition(record.contains("0:a?"))
        c.includeAudio = false; precondition(!c.receiverArguments(capture: URL(fileURLWithPath: "/tmp/a.mkv")).contains("0:a?"))
        c.mode = .rtsp; c.rtspURL = "rtsp://user:secret@192.168.1.2/live"; precondition(c.validationError() != nil)
        c.rtspURL = "rtsp://192.168.1.2/live"; precondition(c.validationError() == nil)
        print("Configuration checks passed")
    }
}
