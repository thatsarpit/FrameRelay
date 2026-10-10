import AppKit
import Foundation
let args = CommandLine.arguments
precondition(args.count == 4)
let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let status = URL(fileURLWithPath: args[2]); let stop = args[3]
let engine = ReceiverEngine()
var peak = 0; var stopping = false; let deadline = Date().addingTimeInterval(90)
engine.start(config)
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    peak = max(peak, engine.frames)
    let data: [String: Any] = ["state": engine.state, "frames": engine.frames, "peakFrames": peak, "active": engine.active, "busy": engine.isBusy, "recording": engine.recording, "latestClip": engine.latestClip?.path ?? "", "error": engine.lastError]
    if let bytes = try? JSONSerialization.data(withJSONObject: data) { try? bytes.write(to: status, options: .atomic) }
    if !stopping && (FileManager.default.fileExists(atPath: stop) || Date() > deadline) { stopping = true; engine.stop() }
    if stopping && !engine.isBusy { exit(0) }
}
RunLoop.main.run()
