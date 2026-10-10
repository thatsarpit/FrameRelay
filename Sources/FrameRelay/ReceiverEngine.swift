import AppKit
import Combine
import CoreVideo

final class ReceiverEngine: ObservableObject {
    @Published var state = "Offline"
    @Published var detail = "Choose your camera connection to begin."
    @Published var preview: NSImage?
    @Published var frames: Int = 0
    @Published var recording = false
    @Published var active = false
    @Published var latestClip: URL?
    @Published var lastError = ""
    @Published var recordingStarted: Date?
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onStateChange: (() -> Void)?
    static var processEnvironment: [String: String] {
        let allowed = ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL"]
        return ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
    }
    private var process: Process?
    private var config = Configuration()
    private var generation = 0
    private let decodeQueue = DispatchQueue(label: "FrameRelay.decode", qos: .userInitiated)
    private var output: Pipe?
    private var errors: Pipe?
    private var retry: DispatchWorkItem?
    private var diskTimer: Timer?
    private var log = ""
    private var pool: CVPixelBufferPool?
    private let frameBytes = 1920 * 1080 * 4
    private var converting = 0
    private let uiLock = NSLock()
    private var uiFramePending = false
    private var lastFrameAt = Date.distantPast
    var isBusy: Bool { process != nil || converting > 0 }

    init() {
        let attributes: [String: Any] = [kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080, kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
    }

    func start(_ configuration: Configuration) {
        guard !active, !isBusy else { return }
        if let error = configuration.validationError() { update("Needs setup", error); lastError = error; return }
        config = configuration; active = true; lastError = ""; launch()
        diskTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.state == "Live", Date().timeIntervalSince(self.lastFrameAt) > 2 { self.preview = nil; self.update("Stream stalled", "Waiting for fresh frames; the receiver will retry if the connection closes.") }
            if self.recording && !self.hasSpace() { self.lastError = "Recording stopped: free disk space is below the reserve."; self.stop() }
        }
    }

    private func hasSpace() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: config.recordingFolder),
              let bytes = attrs[.systemFreeSize] as? NSNumber else { return false }
        return bytes.int64Value > Int64(config.minimumFreeGB) * 1_000_000_000
    }

    private func launch() {
        guard active, process == nil else { return }
        if config.mode == .rtmp && !NetworkInterface.available().contains(where: { $0.address == config.address }) && config.address != "127.0.0.1" {
            update("Network unavailable", "Connect the selected interface. The saved camera address has not changed.")
            scheduleRetry(); return
        }
        var capture: URL?
        if config.recordClips {
            do { try FileManager.default.createDirectory(atPath: config.recordingFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            catch { active = false; update("Folder unavailable", error.localizedDescription); return }
            guard hasSpace() else { active = false; update("Disk space low", "Free at least \(config.minimumFreeGB) GB before recording."); return }
            let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX"); d.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let name = "FrameRelay_\(d.string(from: Date()))_\(UUID().uuidString.prefix(6)).inprogress.mkv"
            capture = URL(fileURLWithPath: config.recordingFolder).appendingPathComponent(name)
        }
        generation += 1; let run = generation; let currentCapture = capture
        let p = Process(); p.executableURL = URL(fileURLWithPath: config.ffmpegPath)
        p.arguments = config.receiverArguments(capture: capture)
        p.environment = Self.processEnvironment
        let stdout = Pipe(); let stderr = Pipe(); output = stdout; errors = stderr
        p.standardOutput = stdout; p.standardError = stderr; p.standardInput = FileHandle.nullDevice
        process = p; log = ""; frames = 0; preview = nil; recordingStarted = nil
        stderr.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                guard let self = self, self.generation == run else { return }
                self.log = String((self.log + text).suffix(5000))
            }
        }
        p.terminationHandler = { [weak self] p in DispatchQueue.main.async { self?.finished(p, currentCapture, run) } }
        do { try p.run() }
        catch { process = nil; active = false; update("Could not start", error.localizedDescription); return }
        update(config.mode == .rtmp ? "Listening" : "Connecting", config.mode == .rtmp ? "Ready for your camera's stream." : "Opening the camera stream.")
        decodeQueue.async { [weak self] in
            guard let self = self else { return }
            var bytes = Data(); bytes.reserveCapacity(self.frameBytes * 2)
            var count = 0
            while true {
                guard let chunk = try? stdout.fileHandleForReading.read(upToCount: 262144), !chunk.isEmpty else { break }
                bytes.append(chunk)
                while bytes.count >= self.frameBytes {
                    let frame = Data(bytes.prefix(self.frameBytes)); bytes.removeFirst(self.frameBytes)
                    count += 1; let n = count
                    guard let pool = self.pool else { continue }
                    var pb: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let buffer = pb else { continue }
                    CVPixelBufferLockBaseAddress(buffer, [])
                    if let base = CVPixelBufferGetBaseAddress(buffer) {
                        let stride = CVPixelBufferGetBytesPerRow(buffer)
                        frame.withUnsafeBytes { source in
                            if stride == 1920 * 4 { memcpy(base, source.baseAddress!, self.frameBytes) }
                            else { for y in 0..<1080 { memcpy(base + y * stride, source.baseAddress! + y * 1920 * 4, 1920 * 4) } }
                        }
                    }
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    self.onFrame?(buffer)
                    self.uiLock.lock()
                    let publish = n % 3 == 1 && !self.uiFramePending
                    if publish { self.uiFramePending = true }
                    self.uiLock.unlock()
                    if publish {
                        let provider = CGDataProvider(data: frame as CFData)!
                        let cg = CGImage(width: 1920, height: 1080, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: 1920 * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue).union(.byteOrder32Little),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
                        let image = NSImage(cgImage: cg, size: NSSize(width: 1920, height: 1080))
                        DispatchQueue.main.async {
                            self.uiLock.lock(); self.uiFramePending = false; self.uiLock.unlock()
                            guard self.generation == run, self.active, self.process != nil else { return }
                            self.lastFrameAt = Date()
                            self.preview = image; self.frames = n
                            if self.state != "Live" {
                                self.recording = self.config.recordClips
                                self.recordingStarted = self.recording ? Date() : nil
                                self.update("Live", self.recording ? "Receiving and recording locally." : "Preview only. Nothing is being recorded.")
                            }
                        }
                    }
                }
            }
        }
    }

    private func update(_ new: String, _ description: String) { state = new; detail = description; onStateChange?() }
    private func scheduleRetry() {
        guard active, config.autoReconnect else { active = false; return }
        retry?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.launch() }; retry = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: job)
    }
    private func finished(_ p: Process, _ capture: URL?, _ run: Int) {
        guard run == generation else { return }
        errors?.fileHandleForReading.readabilityHandler = nil
        process = nil; output = nil; errors = nil; recording = false; preview = nil; recordingStarted = nil
        if let capture = capture { finalize(capture) }
        if active {
            update("Reconnecting", "Waiting for the next camera connection.")
            if p.terminationStatus != 0 && frames == 0 { lastError = String(log.suffix(1200)) }
            scheduleRetry()
        } else { update("Offline", lastError.isEmpty ? "Receiver stopped. Your recordings are safe." : lastError) }
    }
    private func finalize(_ capture: URL) {
        let fm = FileManager.default
        let size = ((try? fm.attributesOfItem(atPath: capture.path)[.size]) as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { if fm.fileExists(atPath: capture.path) { try? fm.removeItem(at: capture) }; return }
        converting += 1
        let destination = capture.deletingPathExtension().deletingPathExtension().appendingPathExtension("mp4")
        let ffmpeg = config.ffmpegPath
        DispatchQueue.global(qos: .utility).async {
            let remux = Process(); remux.executableURL = URL(fileURLWithPath: ffmpeg)
            remux.environment = Self.processEnvironment
            remux.arguments = ["-hide_banner", "-loglevel", "error", "-i", capture.path, "-c", "copy", "-movflags", "+faststart", destination.path]
            remux.standardOutput = FileHandle.nullDevice; remux.standardError = FileHandle.nullDevice; remux.standardInput = FileHandle.nullDevice
            var success = false
            do { try remux.run(); remux.waitUntilExit(); success = remux.terminationStatus == 0 } catch {}
            if success { try? fm.removeItem(at: capture) }
            else if fm.fileExists(atPath: destination.path) { try? fm.removeItem(at: destination) }
            DispatchQueue.main.async {
                self.latestClip = success ? destination : capture; self.converting -= 1
                if !success { self.lastError = "MP4 conversion failed; the original MKV is preserved." }
                self.onStateChange?()
            }
        }
    }
    func stop() {
        active = false; preview = nil; retry?.cancel(); retry = nil; diskTimer?.invalidate(); diskTimer = nil
        if let p = process, p.isRunning {
            update("Stopping", "Finishing the current take."); p.interrupt()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if p.isRunning { p.terminate() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
        } else { update("Offline", "Receiver stopped.") }
    }
}
