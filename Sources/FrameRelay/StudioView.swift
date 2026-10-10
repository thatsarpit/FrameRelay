import SwiftUI

private let ink = Color(red: 0.13, green: 0.15, blue: 0.16)
private let accent = Color(red: 0.86, green: 0.24, blue: 0.16)
private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)

struct StudioView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) { Image(systemName: "viewfinder").font(.title).foregroundStyle(accent); Text("FrameRelay").font(.system(size: 21, weight: .semibold, design: .rounded)).lineLimit(1) }
                Text("YOUR CAMERA. CONNECTED.").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                VStack(spacing: 5) {
                    ForEach(StudioPage.allCases) { page in
                        Button { model.page = page } label: {
                            HStack(spacing: 12) { Image(systemName: page.icon).frame(width: 20); Text(page.rawValue); Spacer() }
                                .font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                                .padding(12).background(model.page == page ? Color.white : Color.clear).cornerRadius(9)
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                HStack { Circle().fill(model.engine.state == "Live" ? .green : .gray).frame(width: 7, height: 7); Text(model.engine.state).font(.caption) }
                Text("Local by design\nNo account. No cloud upload.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(24).frame(width: 235).background(paper)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(model.page == .studio ? "A better seat for your camera." : model.page.rawValue).font(.system(size: 28, weight: .semibold, design: .rounded))
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("PREVIEW 0.1").font(.system(size: 9, weight: .bold)).tracking(1).padding(8).background(paper).cornerRadius(5)
                    }
                    switch model.page {
                    case .studio: studio
                    case .connection: connection
                    case .recordings: recordings
                    case .settings: settings
                    case .cameras: cameras
                    }
                    if !model.notice.isEmpty { Text(model.notice).font(.callout).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(paper).cornerRadius(10) }
                }.padding(30).frame(maxWidth: 1000, alignment: .leading)
            }.background(Color.white)
        }.foregroundStyle(ink).frame(minWidth: 1000, minHeight: 700).preferredColorScheme(.light)
    }
    private var subtitle: String {
        switch model.page {
        case .studio: return "Receive a network stream. Keep your workflow close."
        case .connection: return "One saved address, ready when your camera is."
        case .recordings: return "Your takes stay on your Mac."
        case .settings: return "Small controls for a predictable session."
        case .cameras: return "Protocol compatibility is a starting point, not a guarantee."
        }
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) { Text(title).font(.system(size: 15, weight: .semibold)); content() }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading).background(paper.opacity(0.7)).cornerRadius(13)
    }
    private var studio: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(ink)
                if let image = model.engine.preview {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).scaleEffect(x: model.config.mirrorPreview ? -1 : 1, y: 1).clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "viewfinder").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.white.opacity(0.5))
                        Text(model.engine.active ? "Ready for your next frame" : "Bring your camera into the room").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                        Text(model.engine.active ? "Start streaming on your camera." : "Start the receiver, then start your camera stream.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                VStack { HStack {
                    Label(model.engine.state.uppercased(), systemImage: model.engine.state == "Live" ? "circle.fill" : "circle")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).padding(10).background(.black.opacity(0.55)).cornerRadius(6)
                    Spacer()
                    if model.engine.recording { Label("REC", systemImage: "record.circle.fill").font(.caption.bold()).foregroundStyle(.red).padding(10).background(.black.opacity(0.7)).cornerRadius(6) }
                }; Spacer() }.padding(16)
            }.frame(height: 360)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) { Text(model.config.cameraName).font(.headline); Text(model.engine.detail).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(model.engine.active ? "Stop receiver" : "Start receiver") { model.toggleReceiver() }.buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
                    .disabled(model.engine.state == "Stopping" || (!model.engine.active && model.engine.isBusy))
            }
            HStack(alignment: .top, spacing: 14) {
                card("Camera destination") {
                    Text(model.config.endpoint).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                    Button("Copy address", systemImage: "doc.on.doc") { model.copyAddress() }.buttonStyle(.borderless).tint(accent)
                    Text("Reserve this Mac's address in your router to keep it stable.").font(.caption).foregroundStyle(.secondary)
                }
                card("Virtual camera · \(model.camera.status)") {
                    Text(model.camera.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Activate extension") { model.camera.install() }.disabled(!model.camera.canActivate)
                        Button(model.camera.enabled ? "Disconnect" : "Connect output") { if model.camera.enabled { model.camera.disconnect() } else { model.camera.connect() } }.disabled(!model.camera.available)
                    }.controlSize(.small)
                }
            }
            if !model.engine.lastError.isEmpty { Text(model.engine.lastError).font(.system(size: 11, design: .monospaced)).foregroundStyle(accent).textSelection(.enabled).lineLimit(6) }
        }
    }
    private var connection: some View {
        VStack(spacing: 18) {
            card("Source") {
                TextField("Camera name", text: $model.config.cameraName)
                Picker("Input", selection: $model.config.mode) { ForEach(InputMode.allCases) { Text($0.rawValue).tag($0) } }
                if model.config.mode == .rtmp {
                    Picker("Mac interface", selection: $model.config.address) {
                        Text("Choose an interface").tag("")
                        ForEach(NetworkInterface.available()) { Text($0.title).tag($0.address) }
                    }
                    HStack { TextField("Port", value: $model.config.port, format: .number.grouping(.never)); TextField("Stream path", text: $model.config.streamPath) }
                } else { TextField("rtsp://camera-address/stream", text: $model.config.rtspURL) }
                Text("Trusted local network only. RTMPS listening, SRT, password URLs and internet-facing receivers are not supported in this preview.").font(.caption).foregroundStyle(.secondary)
            }.disabled(model.engine.active || model.engine.isBusy)
            card("Before you press record") {
                Text("1   Connect the camera and Mac to the same trusted router.\n2   Copy the destination into the camera's streaming settings.\n3   Start the receiver here.\n4   Start streaming on your camera.\n5   Stop the camera to finish a take; FrameRelay re-arms automatically.").font(.callout).lineSpacing(9)
                Text("Stop the receiver before changing settings. A normal HDMI output on a hub cannot receive camera video.").font(.caption).foregroundStyle(.secondary)
            }
        }.textFieldStyle(.roundedBorder)
    }
    private var recordings: some View {
        VStack(spacing: 18) {
            card("Capture on your terms") {
                Toggle("Save each camera session as a clip", isOn: $model.config.recordClips)
                Toggle("Include the camera's audio", isOn: $model.config.includeAudio).disabled(!model.config.recordClips)
                Text("Applies to the next connection. Preview-only mode does not save media. Clips keep the source resolution and frame rate; the live preview is converted to 1080p30.").font(.caption).foregroundStyle(.secondary)
            }.disabled(model.engine.active || model.engine.isBusy)
            card("Local library") {
                Text(model.config.recordingFolder).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                HStack { Button("Choose folder…") { model.chooseFolder() }.disabled(model.engine.active || model.engine.isBusy); Button("Open in Finder") { model.openRecordings() } }
                if let clip = model.engine.latestClip { Divider(); Text("Latest finished take").font(.caption).foregroundStyle(.secondary); Button(clip.lastPathComponent, systemImage: "play.circle") { NSWorkspace.shared.open(clip) } }
                Text("While recording: MKV for crash resilience. After the take: MP4 remux without re-encoding. If conversion fails, the MKV is kept. Disk reserve stops capture before storage fills.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var settings: some View {
        VStack(spacing: 18) {
            card("Session") {
                Toggle("Mirror the preview", isOn: $model.config.mirrorPreview)
                Text("Preview only; recordings and virtual-camera frames stay unmirrored.").font(.caption).foregroundStyle(.secondary)
                Toggle("Reconnect when the camera returns", isOn: $model.config.autoReconnect).disabled(model.engine.active)
                Toggle("Open FrameRelay at login", isOn: Binding(get: { model.config.startAtLogin }, set: { model.setLogin($0) }))
                Toggle("Start receiver when FrameRelay opens", isOn: $model.config.autoStartReceiver)
                Text("Off by default. When enabled, a connected camera can begin a local recording if saving clips is also enabled.").font(.caption).foregroundStyle(.secondary)
            }
            card("Recording safety") {
                Stepper("Reserve \(model.config.minimumFreeGB) GB of free space", value: $model.config.minimumFreeGB, in: 1...100).disabled(model.engine.active)
                Text("Check interrupted .inprogress.mkv files before deleting them. They may contain a recoverable take.").font(.caption).foregroundStyle(.secondary)
            }
            card("Video engine") {
                Text(model.config.ffmpegPath).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Button("Choose FFmpeg…") { model.chooseFFmpeg() }.disabled(model.engine.active || model.engine.isBusy)
                Text("FFmpeg is an external dependency and is not bundled. Only select an executable you trust. No telemetry, accounts or automatic uploads.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var cameras: some View {
        VStack(spacing: 18) {
            card("LUMIX S5IIX · tested transport") {
                Text("Firmware 2.2: Wi-Fi RTMP, H.264 1920×1080/25 + AAC. A real 30-second stream was received in development. The new app's live-camera endurance and virtual-camera output still need testing.").font(.callout)
                Text("Setup → IN/OUT → Streaming. Choose Wi-Fi, join the router, choose FHD/6M/25p or 30p, enter FrameRelay's destination, enable streaming, then press video record. Start FrameRelay first.").font(.callout)
                Text("Firmware 2.2 changes: wired RTP/RTSP removed. European models require RTMPS; this preview cannot receive those directly.").font(.caption).foregroundStyle(.secondary)
                Link("Panasonic firmware-specific guide ↗", destination: URL(string: "https://eww.pavc.panasonic.co.jp/dscoi/DC-S5M2X/html/DC-S5M2X_DVQP2992_eng/0197.html")!)
            }
            card("Other sources · test before relying on them") {
                Text("RTMP push: configurable H.264 camera or encoder on your LAN.\nRTSP pull: a credential-free camera endpoint that FFmpeg can decode.\nAudio recording: AAC is the recommended MP4-compatible input.").font(.callout).lineSpacing(8)
                Text("A matching protocol does not establish model compatibility. Record and inspect a short test for detail, motion, sync and disconnect behavior. USB UVC cameras, HDMI capture, RTMPS listeners and SRT are outside this preview's input modes.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
