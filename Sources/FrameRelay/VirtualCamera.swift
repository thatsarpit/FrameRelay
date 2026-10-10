import AppKit
import Foundation
import Combine
import CoreMediaIO
import CoreVideo
import SystemExtensions

enum CameraProvider: String, CaseIterable, Identifiable {
    case virtualCamera4Mac, frameRelay
    var id: String { rawValue }
    var title: String { self == .virtualCamera4Mac ? "VirtualCamera4Mac" : "FrameRelay Camera" }
    var uid: String { self == .virtualCamera4Mac ? "B9E1C0F2-6A2E-4B7D-9C3A-2F1E7D4A5C6B" : "C8C5179A-899B-4C90-A1EE-3B01B464CA5D" }
}

// The separately signed provider owns installation. This ordinary producer uses
// public CMIO APIs; it never modifies or re-signs the provider's extension.
final class VirtualCamera: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    static let identifier = "media.voyd.FrameRelay.CameraExtension"
    @Published var status = "Not connected"
    @Published var explanation = "Approve the separately signed VirtualCamera4Mac provider, then connect output. Your own Apple membership is not needed."
    @Published private(set) var enabled = false
    @Published private(set) var available = false
    @Published var provider: CameraProvider {
        didSet { disconnect(); UserDefaults.standard.set(provider.rawValue, forKey: "cameraProvider"); refresh() }
    }
    @Published var autoConnect: Bool {
        didSet { UserDefaults.standard.set(autoConnect, forKey: "cameraAutoConnect") }
    }
    var extensionURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions/\(Self.identifier).systemextension") }
    var canActivate: Bool { provider == .frameRelay && FileManager.default.fileExists(atPath: extensionURL.path) }
    var providerInstalled: Bool { FileManager.default.fileExists(atPath: "/Applications/VirtualCamera4Mac.app") }
    private var device: CMIODeviceID = 0
    private var stream: CMIOStreamID = 0
    private var queue: CMSimpleQueue?
    private var format: CMVideoFormatDescription?
    private let lock = NSLock()
    private var discoveryTimer: Timer?
    private var nextRetry = Date.distantPast

    override init() {
        provider = CameraProvider(rawValue: UserDefaults.standard.string(forKey: "cameraProvider") ?? "") ?? .virtualCamera4Mac
        autoConnect = UserDefaults.standard.bool(forKey: "cameraAutoConnect")
        super.init()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refresh()
            if self.autoConnect && self.available && !self.enabled && Date() >= self.nextRetry { self.connect() }
        }
    }
    deinit { discoveryTimer?.invalidate() }
    func openProvider() {
        if providerInstalled { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/VirtualCamera4Mac.app")) }
        else { NSWorkspace.shared.open(URL(string: "https://github.com/m96-chan/VirtualCamera4Mac/releases/tag/v0.0.7")!) }
    }
    func install() {
        guard canActivate else { status = "Signed build required"; return }
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.identifier, queue: .main)
        request.delegate = self; status = "Requesting activation"
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    func uninstall() {
        disconnect()
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: Self.identifier, queue: .main)
        request.delegate = self; OSSystemExtensionManager.shared.submitRequest(request)
    }
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) { status = "Approval needed"; explanation = "Approve the camera extension in System Settings. No Recovery mode is needed." }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        status = result == .completed ? "Extension activated" : "Restart required"
        explanation = result == .completed ? "Connect output, then select FrameRelay Camera in your video app." : "macOS will complete the change after a restart."
        if result == .completed { refresh() }
    }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) { status = "Activation unavailable"; explanation = error.localizedDescription }
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }

    private func objects(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector, scope: CMIOObjectPropertyScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)) -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &size, &ids) == noErr else { return [] }
        return ids
    }
    private func uid(_ object: CMIOObjectID) -> String? {
        var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard CMIOObjectGetPropertyData(object, &a, 0, nil, size, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    private func direction(_ stream: CMIOStreamID) -> UInt32? {
        var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyDirection), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(stream, &a, 0, nil, size, &size, &value) == noErr else { return nil }
        return value // 0 = output/sink; 1 = input/source.
    }
    private func findDevice() -> CMIODeviceID? {
        objects(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)).first { uid($0)?.caseInsensitiveCompare(provider.uid) == .orderedSame }
    }
    func refresh() {
        let foundDevice = findDevice()
        let found = foundDevice != nil
        if available != found { available = found }
        lock.lock(); let replaced = stream != 0 && foundDevice != device; lock.unlock()
        if enabled && (!found || replaced) { disconnect() }
        if !enabled && found && status != "Could not open output" {
            status = "Available"; explanation = "\(provider.title) is registered. Connect to send 1080p30 video; audio uses a separate input."
        } else if !found {
            status = "Approval or installation needed"
            explanation = provider == .virtualCamera4Mac ? "Open VirtualCamera4Mac and activate its signed extension. Approve it in macOS Camera Extensions." : "This provider needs a correctly signed FrameRelay extension build."
        }
    }
    // Set the advertised source format to agree with the 1080p BGRA producer.
    // A consumer can negotiate another format later; verify its captured output.
    private func configure1080p(_ source: CMIOStreamID) -> OSStatus {
        var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyFormatDescriptions), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var values: Unmanaged<CFArray>?; var size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
        let read = CMIOObjectGetPropertyData(source, &a, 0, nil, size, &size, &values)
        guard read == noErr, let formats = values?.takeRetainedValue() as? [CMFormatDescription] else { return read == noErr ? -1 : read }
        guard let matching = formats.first(where: {
            let d = CMVideoFormatDescriptionGetDimensions($0)
            return d.width == 1920 && d.height == 1080 && CMFormatDescriptionGetMediaSubType($0) == kCVPixelFormatType_32BGRA
        }) else { return -1 }
        a.mSelector = CMIOObjectPropertySelector(kCMIOStreamPropertyFormatDescription)
        var selected = Unmanaged.passUnretained(matching).toOpaque()
        return withExtendedLifetime(matching) {
            CMIOObjectSetPropertyData(source, &a, 0, nil, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &selected)
        }
    }
    func connect() {
        lock.lock(); defer { lock.unlock() }
        guard stream == 0 else { return }
        nextRetry = Date().addingTimeInterval(10)
        guard let d = findDevice() else { status = "Camera unavailable"; enabled = false; return }
        let all = objects(d, CMIOObjectPropertySelector(kCMIODevicePropertyStreams))
        let outputs = objects(d, CMIOObjectPropertySelector(kCMIODevicePropertyStreams), scope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeOutput))
        let inputs = objects(d, CMIOObjectPropertySelector(kCMIODevicePropertyStreams), scope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeInput))
        let streams = Set(all + outputs + inputs)
        let sinks = streams.filter { direction($0) == 0 }
        let sources = streams.filter { direction($0) == 1 }
        guard sinks.count == 1, sources.count == 1,
              let sink = sinks.first, let source = sources.first else {
            status = "Could not open output"; explanation = "Unexpected source/sink layout."; return
        }
        let formatStatus = configure1080p(source)
        guard formatStatus == noErr else { status = "Could not open output"; explanation = "1080p BGRA negotiation failed (\(formatStatus))."; return }
        var q: Unmanaged<CMSimpleQueue>?
        let queueStatus = CMIOStreamCopyBufferQueue(sink, { _, _, _ in }, nil, &q)
        guard queueStatus == noErr, let copied = q?.takeRetainedValue() else { status = "Could not open output"; explanation = "CMIO queue failed (\(queueStatus))."; return }
        let startStatus = CMIODeviceStartStream(d, sink)
        guard startStatus == noErr else { status = "Could not open output"; explanation = "CMIO start failed (\(startStatus))."; return }
        device = d; stream = sink; queue = copied; enabled = true
        status = "Webcam connected"; explanation = "Choose \(provider.title) in Recordly. Video: 1920×1080 at 30 fps. Select your microphone separately."
    }
    func disconnect() {
        lock.lock(); defer { lock.unlock() }
        if stream != 0 { CMIODeviceStopStream(device, stream) }
        queue = nil; format = nil; stream = 0; device = 0; enabled = false
        if status == "Webcam connected" { status = "Available" }
    }
    func send(_ pixelBuffer: CVPixelBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard stream != 0, let queue, CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue),
              CVPixelBufferGetWidth(pixelBuffer) == 1920, CVPixelBufferGetHeight(pixelBuffer) == 1080,
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return }
        if format == nil { CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format) }
        guard let format else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
        let ref = Unmanaged.passRetained(sample)
        if CMSimpleQueueEnqueue(queue, element: ref.toOpaque()) != noErr { ref.release() }
    }
}
