import Foundation
import Combine
import CoreMediaIO
import CoreVideo
import SystemExtensions

// A bounded CMIO sink queue carries frames to the signed camera extension.
final class VirtualCamera: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    static let identifier = "media.voyd.FrameRelay.CameraExtension"
    static let deviceUID = "C8C5179A-899B-4C90-A1EE-3B01B464CA5D"
    @Published var status = "Not installed"
    @Published var explanation = "A signed camera extension is required. Preview and recording work independently."
    @Published var enabled = false
    @Published var available = false
    var extensionURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions/\(Self.identifier).systemextension") }
    var canActivate: Bool { FileManager.default.fileExists(atPath: extensionURL.path) }
    private var device: CMIODeviceID = 0
    private var stream: CMIOStreamID = 0
    private var queue: CMSimpleQueue?
    private let lock = NSLock()

    func install() {
        guard canActivate else {
            status = "Signed build required"; explanation = "This receiver-only build does not include an installable camera extension. See the signing guide."; return
        }
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.identifier, queue: .main)
        request.delegate = self; status = "Requesting activation"
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    func uninstall() {
        disconnect()
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: Self.identifier, queue: .main)
        request.delegate = self; OSSystemExtensionManager.shared.submitRequest(request)
    }
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        status = "Approval needed"; explanation = "Approve the camera extension in System Settings. No Recovery mode is needed."
    }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        status = result == .completed ? "Extension activated" : "Restart required"
        explanation = result == .completed ? "Connect the virtual-camera output, then choose FrameRelay Camera in your video app." : "macOS will complete the change after a restart."
        if result == .completed { refresh() }
    }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        status = "Activation unavailable"; explanation = error.localizedDescription
    }
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
    func refresh() {
        let found = objects(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)).first { uid($0) == Self.deviceUID }
        available = found != nil
        if found != nil { status = "Available"; explanation = "FrameRelay Camera is registered with macOS." }
        else if status == "Available" { status = "Not installed" }
    }
    func connect() {
        lock.lock(); defer { lock.unlock() }
        guard stream == 0 else { return }
        guard let d = objects(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)).first(where: { uid($0) == Self.deviceUID }),
              let s = objects(d, CMIOObjectPropertySelector(kCMIODevicePropertyStreams), scope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeOutput)).first else {
            status = "Camera unavailable"; explanation = "Install and approve a correctly signed extension first."; enabled = false; return
        }
        var q: Unmanaged<CMSimpleQueue>?
        guard CMIOStreamCopyBufferQueue(s, nil, nil, &q) == noErr, let q = q?.takeRetainedValue(), CMIODeviceStartStream(d, s) == noErr else {
            status = "Could not open output"; enabled = false; return
        }
        device = d; stream = s; queue = q; enabled = true
        status = "Virtual camera on"; explanation = "Choose FrameRelay Camera in your video app. Audio uses a separate input."
    }
    func disconnect() {
        lock.lock(); defer { lock.unlock() }
        if stream != 0 { CMIODeviceStopStream(device, stream) }
        queue = nil; stream = 0; device = 0; enabled = false
        if status == "Virtual camera on" { status = "Available" }
    }
    func send(_ pixelBuffer: CVPixelBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard stream != 0, let queue = queue, CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return }
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format) == noErr, let format = format else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample = sample else { return }
        let ref = Unmanaged.passRetained(sample)
        if CMSimpleQueueEnqueue(queue, element: ref.toOpaque()) != noErr { ref.release() }
    }
}
