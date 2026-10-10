// Standalone, opt-in runtime harness. It never activates/installs extensions or
// requests camera permission. Run capture only after permission already exists.
//
// Compile from the repository root:
// swiftc -swift-version 5 -O -framework AVFoundation -framework CoreMediaIO \
//   -framework CoreMedia -framework CoreVideo Tests/VirtualCameraHarness/main.swift \
//   -o build/VirtualCameraHarness
//
// VirtualCameraHarness list
// VirtualCameraHarness produce DEVICE_UID SECONDS
// VirtualCameraHarness capture DEVICE_UID SECONDS
// Run produce and capture concurrently in separate processes. Output is JSON;
// no images, recordings, settings, or credentials are written by this harness.

import AVFoundation
import CoreMedia
import CoreMediaIO
import CoreVideo
import Darwin
import Foundation

private let width = 1920
private let height = 1080
private let fps: Int32 = 30
private let markerMagic: UInt32 = 0xC35A
// Native little-endian UInt32 values are BGRA bytes in memory.
private let bars: [UInt32] = [0xFFFFFFFF, 0xFFFFFF00, 0xFF00FFFF, 0xFF00FF00,
                              0xFFFF00FF, 0xFFFF0000, 0xFF0000FF, 0xFF000000]

private struct HarnessError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func emit(_ object: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    } catch {
        FileHandle.standardError.write(Data("JSON serialization failed: \(error)\n".utf8))
    }
}

private func fourCC(_ value: OSType) -> String {
    let bytes = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255),
                 UInt8((value >> 8) & 255), UInt8(value & 255)]
    return String(bytes: bytes, encoding: .ascii) ?? String(value)
}

private enum CMIO {
    static func address(_ selector: CMIOObjectPropertySelector,
                        scope: CMIOObjectPropertyScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: scope,
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    static func objects(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector,
                        scope: CMIOObjectPropertyScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)) -> [CMIOObjectID] {
        var property = address(selector, scope: scope)
        var byteCount: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &property, 0, nil, &byteCount) == noErr,
              byteCount > 0, byteCount % UInt32(MemoryLayout<CMIOObjectID>.size) == 0 else { return [] }
        var result = [CMIOObjectID](repeating: 0, count: Int(byteCount) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        let status = result.withUnsafeMutableBytes {
            CMIOObjectGetPropertyData(object, &property, 0, nil, byteCount, &used, $0.baseAddress!)
        }
        guard status == noErr else { return [] }
        return Array(result.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    static func string(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> String? {
        var property = address(selector)
        var result: Unmanaged<CFString>?
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(object, &property, 0, nil,
                                              UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, &result)
        guard status == noErr else { return nil }
        return result?.takeRetainedValue() as String?
    }

    static func direction(_ stream: CMIOStreamID) -> UInt32? {
        var property = address(CMIOObjectPropertySelector(kCMIOStreamPropertyDirection))
        var result: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(stream, &property, 0, nil,
                                       UInt32(MemoryLayout<UInt32>.size), &used, &result) == noErr else { return nil }
        return result // CoreMediaIO: 0 = output (producer sink), 1 = input (camera source).
    }

    static var devices: [CMIOObjectID] {
        objects(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    }

    static func uid(_ object: CMIOObjectID) -> String? {
        string(object, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID))
    }

    static func streams(_ device: CMIODeviceID) -> [CMIOStreamID] {
        let selector = CMIOObjectPropertySelector(kCMIODevicePropertyStreams)
        // Include scope-specific results for providers that omit global streams.
        let candidates = objects(device, selector)
            + objects(device, selector, scope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeInput))
            + objects(device, selector, scope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeOutput))
        var seen = Set<CMIOStreamID>()
        return candidates.filter { seen.insert($0).inserted }
    }
}

private func videoDevices() -> [AVCaptureDevice] {
    // Enumeration does not request camera access. The deprecated call also finds
    // virtual devices without making assumptions about their device-type labels.
    AVCaptureDevice.devices(for: .video)
}

private func formatInfo(_ format: AVCaptureDevice.Format) -> [String: Any] {
    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    return ["width": dimensions.width, "height": dimensions.height,
            "pixelFormat": fourCC(CMFormatDescriptionGetMediaSubType(format.formatDescription)),
            "frameRateRanges": format.videoSupportedFrameRateRanges.map {
                ["min": $0.minFrameRate, "max": $0.maxFrameRate]
            }]
}

private func listDevices() {
    emit(["mode": "list", "cameraAuthorization": AVCaptureDevice.authorizationStatus(for: .video).rawValue,
          "cameras": videoDevices().map {
              ["name": $0.localizedName, "uid": $0.uniqueID, "formats": $0.formats.map(formatInfo)] as [String: Any]
          },
          "cmioDevices": CMIO.devices.map { device in
              ["name": CMIO.string(device, CMIOObjectPropertySelector(kCMIOObjectPropertyName)) ?? "",
               "uid": CMIO.uid(device) ?? "", "streams": CMIO.streams(device).map { stream in
                   ["id": stream, "direction": CMIO.direction(stream).map { $0 == 0 ? "sink" : "source" } ?? "unknown"] as [String: Any]
               }] as [String: Any]
          }])
}

private final class Producer {
    private let device: CMIODeviceID
    private let stream: CMIOStreamID
    private let queue: CMSimpleQueue
    private let pool: CVPixelBufferPool
    private let format: CMVideoFormatDescription
    let formatSetStatus: OSStatus?

    init(uid: String) throws {
        guard let device = CMIO.devices.first(where: { CMIO.uid($0)?.caseInsensitiveCompare(uid) == .orderedSame }) else {
            throw HarnessError("CMIO device UID not found. Install and activate a signed camera provider separately.")
        }
        let candidates = CMIO.streams(device).filter { CMIO.direction($0) == 0 }
        guard candidates.count == 1, let stream = candidates.first else {
            throw HarnessError("Expected exactly one CMIO output/sink stream; found \(candidates.count). Refusing to guess a source stream.")
        }
        self.device = device
        self.stream = stream
        var description: CMVideoFormatDescription?
        let descriptionStatus = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA, width: Int32(width), height: Int32(height),
            extensions: nil, formatDescriptionOut: &description)
        guard descriptionStatus == noErr, let description else { throw HarnessError("Format creation failed: \(descriptionStatus)") }
        self.format = description

        var property = CMIO.address(CMIOObjectPropertySelector(kCMIOStreamPropertyFormatDescription))
        var settable = DarwinBoolean(false)
        if CMIOObjectIsPropertySettable(stream, &property, &settable) == noErr, settable.boolValue {
            var desiredFormat = Unmanaged.passUnretained(description).toOpaque()
            self.formatSetStatus = CMIOObjectSetPropertyData(stream, &property, 0, nil,
                UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &desiredFormat)
        } else {
            self.formatSetStatus = nil
        }
        var unmanagedQueue: Unmanaged<CMSimpleQueue>?
        let queueStatus = CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, &unmanagedQueue)
        guard queueStatus == noErr, let unmanagedQueue else { throw HarnessError("Sink buffer queue unavailable: \(queueStatus)") }
        self.queue = unmanagedQueue.takeRetainedValue()

        var pool: CVPixelBufferPool?
        let attributes: [String: Any] = [kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
        let poolStatus = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        guard poolStatus == kCVReturnSuccess, let pool else { throw HarnessError("Pixel-buffer pool creation failed: \(poolStatus)") }
        self.pool = pool
        let startStatus = CMIODeviceStartStream(device, stream)
        guard startStatus == noErr else { throw HarnessError("Sink stream start failed: \(startStatus)") }
    }

    deinit { CMIODeviceStopStream(device, stream) }

    func send(frame: UInt32) throws -> Bool {
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return false }
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferPoolAllocationThresholdKey as String: 4] as CFDictionary
        let allocationStatus = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, attributes, &pixelBuffer)
        if allocationStatus == kCVReturnWouldExceedAllocationThreshold { return false }
        guard allocationStatus == kCVReturnSuccess, let pixelBuffer else { throw HarnessError("Pixel-buffer allocation failed: \(allocationStatus)") }
        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard lockStatus == kCVReturnSuccess else { throw HarnessError("Pixel-buffer lock failed: \(lockStatus)") }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            throw HarnessError("BGRA pixel buffer has no base address")
        }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let firstRow = base.assumingMemoryBound(to: UInt32.self)
        for x in 0..<width { firstRow[x] = bars[x * bars.count / width] }
        for y in 1..<height { memcpy(base.advanced(by: y * rowBytes), base, width * 4) }
        // A 32-bit black/white stripe survives normal color conversions: fixed
        // magic followed by a changing 16-bit frame counter. Bars stay intact
        // at the image midpoint used by the capture verifier.
        let marker = (markerMagic << 16) | (frame & 0xFFFF)
        for y in (height - 64)..<(height - 32) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt32.self)
            for x in 0..<width {
                let bit = 31 - (x * 32 / width)
                row[x] = ((marker >> bit) & 1) == 1 ? 0xFFFFFFFF : 0xFF000000
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: fps),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
        guard sampleStatus == noErr, let sampleBuffer else { throw HarnessError("Sample-buffer creation failed: \(sampleStatus)") }
        let retained = Unmanaged.passRetained(sampleBuffer)
        let enqueueStatus = CMSimpleQueueEnqueue(queue, element: retained.toOpaque())
        if enqueueStatus != noErr { retained.release(); return false }
        return true
    }
}

private func produce(uid: String, seconds: Double) throws {
    let producer = try Producer(uid: uid)
    let start = ProcessInfo.processInfo.systemUptime
    var attempted: UInt32 = 0
    var enqueued = 0
    var dropped = 0
    while ProcessInfo.processInfo.systemUptime - start < seconds {
        let target = start + Double(attempted) / Double(fps)
        let delay = target - ProcessInfo.processInfo.systemUptime
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        guard ProcessInfo.processInfo.systemUptime - start < seconds else { break }
        let sent = try autoreleasepool { try producer.send(frame: attempted) }
        if sent { enqueued += 1 } else { dropped += 1 }
        attempted += 1
    }
    emit(["mode": "produce", "uid": uid, "requestedSeconds": seconds,
          "elapsedSeconds": ProcessInfo.processInfo.systemUptime - start,
          "width": width, "height": height, "pixelFormat": "BGRA", "requestedFPS": fps,
          "attemptedFrames": attempted, "enqueuedFrames": enqueued, "droppedFrames": dropped,
          "sinkFormatSetStatus": producer.formatSetStatus.map { $0 as Any } ?? NSNull(),
          "pattern": "8 color bars; bottom stripe 0xC35A plus 16-bit frame counter"])
}

private final class CaptureVerifier: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var frames = 0
    var dropped = 0
    var dimensions: [String: Int] = [:]
    var colorBarFrames = 0
    var markerFrames = 0
    var uniqueMarkers = Set<UInt32>()
    var markerTransitions = 0
    var lastMarker: UInt32?
    var firstMarkerPTS: Double?
    var lastChangedMarkerPTS: Double?
    var matchingSyntheticFrames = 0
    var firstPTS: Double?
    var lastPTS: Double?
    var nonIncreasingPTS = 0
    var invalidPTS = 0

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        dropped += 1
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frames += 1
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        if pts.isFinite {
            if let lastPTS, pts <= lastPTS { nonIncreasingPTS += 1 }
            if firstPTS == nil { firstPTS = pts }
            lastPTS = pts
        } else { invalidPTS += 1 }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let actualWidth = CVPixelBufferGetWidth(pixelBuffer)
        let actualHeight = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        dimensions["\(actualWidth)x\(actualHeight)/\(fourCC(pixelFormat))", default: 0] += 1
        guard actualWidth == width, actualHeight == height, pixelFormat == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let row = base.advanced(by: height / 2 * rowBytes).assumingMemoryBound(to: UInt8.self)
        var matches = true
        for bar in 0..<bars.count {
            let offset = (width * (bar * 2 + 1) / (bars.count * 2)) * 4
            let expected = bars[bar]
            for channel in 0..<3 {
                let value = Int((expected >> (channel * 8)) & 255)
                if abs(Int(row[offset + channel]) - value) > 20 { matches = false }
            }
        }
        if matches { colorBarFrames += 1 }
        let markerRow = base.advanced(by: (height - 48) * rowBytes).assumingMemoryBound(to: UInt8.self)
        var marker: UInt32 = 0
        for bit in 0..<32 {
            let offset = (width * (bit * 2 + 1) / 64) * 4
            let luminance = (Int(markerRow[offset]) + Int(markerRow[offset + 1]) + Int(markerRow[offset + 2])) / 3
            marker = (marker << 1) | (luminance > 127 ? 1 : 0)
        }
        if marker >> 16 == markerMagic {
            markerFrames += 1
            if matches { matchingSyntheticFrames += 1 }
            let sequence = marker & 0xFFFF
            uniqueMarkers.insert(sequence)
            if firstMarkerPTS == nil, pts.isFinite { firstMarkerPTS = pts }
            if let lastMarker, sequence != lastMarker {
                markerTransitions += 1
                if pts.isFinite { lastChangedMarkerPTS = pts }
            }
            lastMarker = sequence
        }
    }

    func summary(uid: String, seconds: Double, configuredFPS: Double?) -> [String: Any] {
        let span = (lastPTS ?? 0) - (firstPTS ?? 0)
        let changingMarkerSpan = (lastChangedMarkerPTS ?? 0) - (firstMarkerPTS ?? 0)
        return ["mode": "capture", "uid": uid, "requestedSeconds": seconds,
                "requestedWidth": width, "requestedHeight": height, "requestedPixelFormat": "BGRA", "requestedFPS": fps,
                "configuredFPS": configuredFPS.map { $0 as Any } ?? NSNull(),
                "capturedFrames": frames, "captureDroppedFrames": dropped, "actualFormats": dimensions,
                "presentationSpanSeconds": span, "measuredFPS": span > 0 ? Double(max(0, frames - 1)) / span : 0,
                "invalidPTSFrames": invalidPTS, "nonIncreasingPTSFrames": nonIncreasingPTS,
                "colorBarFrames": colorBarFrames, "syntheticMarkerFrames": markerFrames,
                "matchingSyntheticFrames": matchingSyntheticFrames,
                "uniqueFrameMarkers": uniqueMarkers.count, "markerTransitions": markerTransitions,
                "changingMarkerSpanSeconds": max(0, changingMarkerSpan),
                "measuredChangingMarkerFPS": changingMarkerSpan > 0 ? Double(markerTransitions) / changingMarkerSpan : 0,
                "lastFrameMarker": lastMarker.map { $0 as Any } ?? NSNull(),
                "verified1080pBGRASyntheticVideo": matchingSyntheticFrames > 1 && uniqueMarkers.count > 1]
    }
}

private func capture(uid: String, seconds: Double) throws {
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
        throw HarnessError("Camera access is not already authorized for this process. The harness does not request permission or display security prompts.")
    }
    guard let device = videoDevices().first(where: { $0.uniqueID.caseInsensitiveCompare(uid) == .orderedSame }) else {
        throw HarnessError("AVFoundation camera UID not found")
    }
    let matching = device.formats.filter {
        let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
        return dimensions.width == width && dimensions.height == height
    }
    guard let format = matching.first(where: {
        $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= Double(fps) && $0.maxFrameRate >= Double(fps) }
    }) ?? matching.first else { throw HarnessError("Camera does not advertise a 1920x1080 capture format") }
    let session = AVCaptureSession()
    session.beginConfiguration()
    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else { throw HarnessError("Cannot add capture input") }
    session.addInput(input)
    try device.lockForConfiguration()
    device.activeFormat = format
    // Some providers advertise a fixed 60fps format while forwarding 30fps
    // producer frames. Do not attempt an unsupported 30fps configuration;
    // report configured and measured rates independently.
    if format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= Double(fps) && $0.maxFrameRate >= Double(fps) }) {
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: fps)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: fps)
    }
    let frameDuration = CMTimeGetSeconds(device.activeVideoMinFrameDuration)
    let configuredFPS = frameDuration.isFinite && frameDuration > 0 ? 1 / frameDuration : nil
    device.unlockForConfiguration()
    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.alwaysDiscardsLateVideoFrames = true
    let verifier = CaptureVerifier()
    let queue = DispatchQueue(label: "FrameRelay.VirtualCameraHarness.capture")
    output.setSampleBufferDelegate(verifier, queue: queue)
    guard session.canAddOutput(output) else { throw HarnessError("Cannot add capture output") }
    session.addOutput(output)
    session.commitConfiguration()
    session.startRunning()
    guard session.isRunning else { throw HarnessError("Capture session did not start") }
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.05))) }
    session.stopRunning()
    // Drain callbacks before reading counters; stopRunning alone does not
    // guarantee the sample-buffer delegate's serial queue is empty.
    let summary = queue.sync { verifier.summary(uid: uid, seconds: seconds, configuredFPS: configuredFPS) }
    output.setSampleBufferDelegate(nil, queue: nil)
    emit(summary)
    if !(summary["verified1080pBGRASyntheticVideo"] as? Bool ?? false) { exit(2) }
}

do {
    let arguments = CommandLine.arguments
    if arguments.count == 2, arguments[1] == "list" {
        listDevices()
    } else if arguments.count == 4, let seconds = Double(arguments[3]), seconds.isFinite, seconds >= 0.1, seconds <= 300 {
        switch arguments[1] {
        case "produce": try produce(uid: arguments[2], seconds: seconds)
        case "capture": try capture(uid: arguments[2], seconds: seconds)
        default: throw HarnessError("Unknown mode. Use list, produce DEVICE_UID SECONDS, or capture DEVICE_UID SECONDS.")
        }
    } else {
        throw HarnessError("Usage: VirtualCameraHarness list | produce DEVICE_UID SECONDS | capture DEVICE_UID SECONDS (0.1–300)")
    }
} catch {
    emit(["error": String(describing: error)])
    exit(1)
}
