import AppKit
import SwiftUI
import Combine
import Darwin

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var item: NSStatusItem!
    var subscriptions: Set<AnyCancellable> = []
    var quitting = false
    var lockFD: Int32 = -1
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Per-user singleton, independent of the repository or recording folder.
        let lockPath = FileManager.default.temporaryDirectory.appendingPathComponent("media.voyd.FrameRelay.\(getuid()).lock").path
        lockFD = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "FrameRelay")
        rebuildMenu()
        model.engine.onStateChange = { [weak self] in self?.rebuildMenu() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1110, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "FrameRelay"; window.contentView = NSHostingView(rootView: StudioView(model: model))
        window.center(); window.isReleasedWhenClosed = false; model.window = window
        NSApp.setActivationPolicy(.regular)
        model.showWindow()
        if model.config.autoStartReceiver { model.engine.start(model.config) }
    }
    func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "FrameRelay · \(model.engine.state)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        add(menu, "Open studio", #selector(show), "o")
        add(menu, model.engine.active ? "Stop receiver" : "Start receiver", #selector(toggle), "s")
        add(menu, "Copy camera address", #selector(copyAddress), "")
        add(menu, "Open recordings", #selector(recordings), "")
        menu.addItem(.separator()); add(menu, "Quit FrameRelay", #selector(quit), "q")
        item?.menu = menu
    }
    func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) { let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: key); entry.target = self }
    @objc func show() { model.showWindow() }
    @objc func toggle() { model.toggleReceiver() }
    @objc func copyAddress() { model.copyAddress() }
    @objc func recordings() { model.openRecordings() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !model.engine.isBusy { model.camera.disconnect(); return .terminateNow }
        guard !quitting else { return .terminateCancel }
        quitting = true; model.camera.disconnect(); model.engine.stop()
        // Keep the normal app run loop alive while FFmpeg exits/remuxes.
        // terminateLater can stall process completion callbacks on some hosts.
        let timer = Timer(timeInterval: 0.2, repeats: true) { timer in
            if !self.model.engine.isBusy { timer.invalidate(); NSApp.terminate(nil) }
        }
        RunLoop.main.add(timer, forMode: .common)
        return .terminateCancel
    }
}
let app = NSApplication.shared
let delegate = ApplicationDelegate()
app.delegate = delegate
let menu = NSMenu(); let root = NSMenuItem(); menu.addItem(root)
let applicationMenu = NSMenu(); root.submenu = applicationMenu
applicationMenu.addItem(withTitle: "Quit FrameRelay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
let editRoot = NSMenuItem(); menu.addItem(editRoot); let edit = NSMenu(title: "Edit"); editRoot.submenu = edit
for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key) }
app.mainMenu = menu
app.run()
