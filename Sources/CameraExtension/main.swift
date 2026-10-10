import Foundation
import CoreMediaIO
import CoreVideo
import Security

// Camera-extension prototype. Compile verification is not installation/runtime verification.
// Only the containing app, signed by the same team, may produce frames.
func authorizedProducer(_ client: CMIOExtensionClient) -> Bool {
    guard client.signingID == "media.voyd.FrameRelay", client.pid > 0 else { return false }
    var code: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: client.pid] as CFDictionary, [], &code) == errSecSuccess, let code = code else { return false }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode = staticCode else { return false }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let dict = info as? [String: Any], let team = dict[kSecCodeInfoTeamIdentifier as String] as? String,
          let expected = Bundle.main.object(forInfoDictionaryKey: "FrameRelayTeamIdentifier") as? String,
          !expected.isEmpty, expected != "TEAM_ID", team == expected else { return false }
    var requirement: SecRequirement?
    let text = "anchor apple generic and identifier \"media.voyd.FrameRelay\" and certificate leaf[subject.OU] = \"\(expected)\""
    guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement = requirement else { return false }
    return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
}

final class RelayDevice: NSObject, CMIOExtensionDeviceSource {
    var device: CMIOExtensionDevice!
    var source: RelayStream!
    var sink: RelayStream!
    let queue = DispatchQueue(label: "FrameRelay.Camera")
    var latest: CVPixelBuffer?
    var receivedAt: UInt64 = 0
    var outputClients = 0
    var timer: DispatchSourceTimer?
    var black: CVPixelBuffer!
    var format: CMFormatDescription!
    override init() {
        super.init()
        let id = UUID(uuidString: "C8C5179A-899B-4C90-A1EE-3B01B464CA5D")!
        device = CMIOExtensionDevice(localizedName: "FrameRelay Camera", deviceID: id, legacyDeviceID: id.uuidString, source: self)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1920, 1080, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pb)
        black = pb!
        CVPixelBufferLockBaseAddress(black, [])
        memset(CVPixelBufferGetBaseAddress(black), 0, CVPixelBufferGetBytesPerRow(black) * 1080)
        CVPixelBufferUnlockBaseAddress(black, [])
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: black, formatDescriptionOut: &format)
        source = RelayStream(owner: self, sink: false)
        sink = RelayStream(owner: self, sink: true)
        try! device.addStream(source.stream); try! device.addStream(sink.stream)
    }
    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel] }
    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let p = CMIOExtensionDeviceProperties(dictionary: [:]); p.transportType = 0x76697274; p.model = "FrameRelay"; return p
    }
    func setDeviceProperties(_ properties: CMIOExtensionDeviceProperties) throws {}
    func startOutput() {
        queue.async { [self] in
            self.outputClients += 1
            guard self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .nanoseconds(33_333_333), leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in self?.emit() }; self.timer = timer; timer.resume()
        }
    }
    func stopOutput() {
        queue.async { self.outputClients = max(0, self.outputClients - 1); if self.outputClients == 0 { self.timer?.cancel(); self.timer = nil } }
    }
    func emit() {
        let now = DispatchTime.now().uptimeNanoseconds
        // Never retain a frozen private image after a producer disconnect/stall.
        let buffer = now >= receivedAt && now - receivedAt < 1_000_000_000 ? (latest ?? black!) : black!
        if now >= receivedAt && now - receivedAt >= 1_000_000_000 { latest = nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: Int64(now), timescale: 1_000_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        if CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample = sample {
            source.stream.send(sample, discontinuity: [], hostTimeInNanoseconds: now)
        }
    }
}

final class RelayStream: NSObject, CMIOExtensionStreamSource {
    unowned let owner: RelayDevice
    let isSink: Bool
    var stream: CMIOExtensionStream!
    var producer: CMIOExtensionClient?
    var consuming = false
    var generation = 0
    init(owner: RelayDevice, sink: Bool) {
        self.owner = owner; isSink = sink; super.init()
        let id = UUID(uuidString: sink ? "C8C5179A-899B-4C90-A1EE-3B01B464CA5F" : "C8C5179A-899B-4C90-A1EE-3B01B464CA5E")!
        stream = CMIOExtensionStream(localizedName: sink ? "FrameRelay Input" : "FrameRelay Video", streamID: id, direction: sink ? .sink : .source, clockType: .hostTime, source: self)
    }
    var formats: [CMIOExtensionStreamFormat] { [CMIOExtensionStreamFormat(formatDescription: owner.format, maxFrameDuration: CMTime(value: 1, timescale: 30), minFrameDuration: CMTime(value: 1, timescale: 30), validFrameDurations: nil)] }
    var availableProperties: Set<CMIOExtensionProperty> {
        var set: Set<CMIOExtensionProperty> = [.streamActiveFormatIndex, .streamFrameDuration]
        if isSink { set.formUnion([.streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup, .streamSinkBufferUnderrunCount, .streamSinkEndOfData]) }; return set
    }
    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let p = CMIOExtensionStreamProperties(dictionary: [:]); p.activeFormatIndex = 0; p.frameDuration = CMTime(value: 1, timescale: 30)
        if isSink { p.sinkBufferQueueSize = 3; p.sinkBuffersRequiredForStartup = 1; p.sinkBufferUnderrunCount = 0; p.sinkEndOfData = 0 }; return p
    }
    func setStreamProperties(_ properties: CMIOExtensionStreamProperties) throws {
        if let index = properties.activeFormatIndex, index != 0 { throw NSError(domain: "FrameRelay", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only the 1080p30 BGRA format is available."]) }
    }
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        if !isSink { return true }
        guard authorizedProducer(client) else { return false }
        if let producer = producer, producer.clientID != client.clientID { return false }
        producer = client; return true
    }
    func startStream() throws {
        if isSink {
            owner.queue.async { self.consuming = true; self.generation += 1; self.consume(self.generation) }
        } else { owner.startOutput() }
    }
    func stopStream() throws {
        if isSink { owner.queue.async { self.consuming = false; self.generation += 1; self.producer = nil; self.owner.latest = nil; self.owner.receivedAt = 0 } }
        else { owner.stopOutput() }
    }
    func consume(_ run: Int) {
        guard consuming, generation == run, let client = producer else { return }
        stream.consumeSampleBuffer(from: client) { [weak self] sample, sequence, _, more, error in
            guard let self = self else { return }
            self.owner.queue.async {
                guard self.consuming, self.generation == run else { return }
                if let sample = sample, let pb = CMSampleBufferGetImageBuffer(sample), CVPixelBufferGetWidth(pb) == 1920, CVPixelBufferGetHeight(pb) == 1080, CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA {
                    self.owner.latest = pb; self.owner.receivedAt = DispatchTime.now().uptimeNanoseconds
                    self.stream.notifyScheduledOutputChanged(CMIOExtensionScheduledOutput(sequenceNumber: sequence, hostTimeInNanoseconds: self.owner.receivedAt))
                }
                self.owner.queue.asyncAfter(deadline: .now() + (more ? .milliseconds(0) : .milliseconds(4))) { self.consume(run) }
            }
        }
    }
}

final class RelayProvider: NSObject, CMIOExtensionProviderSource {
    var provider: CMIOExtensionProvider!
    let relay = RelayDevice()
    override init() { super.init(); provider = CMIOExtensionProvider(source: self, clientQueue: nil); try! provider.addDevice(relay.device) }
    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }
    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let p = CMIOExtensionProviderProperties(dictionary: [:]); p.manufacturer = "FrameRelay"; return p
    }
    func setProviderProperties(_ properties: CMIOExtensionProviderProperties) throws {}
    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}
}
let source = RelayProvider()
CMIOExtensionProvider.startService(provider: source.provider)
CFRunLoopRun()
