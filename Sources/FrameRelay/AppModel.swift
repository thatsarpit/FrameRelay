import AppKit
import Combine

enum StudioPage: String, CaseIterable, Identifiable {
    case studio = "Studio", connection = "Connection", recordings = "Recordings", settings = "Settings", cameras = "Camera guide"
    var id: String { rawValue }
    var icon: String {
        switch self { case .studio: return "viewfinder"; case .connection: return "point.3.connected.trianglepath.dotted"; case .recordings: return "play.rectangle.on.rectangle"; case .settings: return "slider.horizontal.3"; case .cameras: return "camera.aperture" }
    }
}

final class AppModel: ObservableObject {
    @Published var page: StudioPage = .studio
    @Published var config: Configuration
    @Published var notice = ""
    let engine = ReceiverEngine()
    let camera = VirtualCamera()
    var window: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    init() {
        if let data = UserDefaults.standard.data(forKey: "configuration"), let saved = try? JSONDecoder().decode(Configuration.self, from: data) { config = saved }
        else { config = Configuration() }
        engine.onFrame = { [weak camera] frame in camera?.send(frame) }
        engine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        camera.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        $config.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { value in
            var safe = value
            if let url = URLComponents(string: safe.rtspURL), url.user != nil || url.password != nil { safe.rtspURL = "" }
            if let data = try? JSONEncoder().encode(safe) { UserDefaults.standard.set(data, forKey: "configuration") }
        }.store(in: &subscriptions)
        config.startAtLogin = LoginManager.enabled
        camera.refresh()
    }
    func toggleReceiver() { if engine.active { engine.stop() } else { engine.start(config) } }
    func showWindow() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func chooseFolder() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.canCreateDirectories = true; picker.prompt = "Use folder"
        if picker.runModal() == .OK, let url = picker.url { config.recordingFolder = url.path }
    }
    func chooseFFmpeg() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.canChooseFiles = true
        picker.prompt = "Use FFmpeg"
        if picker.runModal() == .OK, let url = picker.url { config.ffmpegPath = url.path }
    }
    func openRecordings() { NSWorkspace.shared.open(URL(fileURLWithPath: config.recordingFolder)) }
    func copyAddress() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(config.endpoint, forType: .string) }
    func setLogin(_ value: Bool) {
        do {
            try LoginManager.setEnabled(value)
            config.startAtLogin = value
            notice = value ? "FrameRelay will open at login. Receiver auto-start follows your session setting." : "Login startup disabled."
        } catch { notice = error.localizedDescription }
    }
}
