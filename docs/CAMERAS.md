# Camera compatibility

Research checked 10 October 2026. “Documented” means the vendor describes the transport, not that the camera has passed this app's tests. Model region, firmware, codec and LAN behavior matter.

| Device/source | Transport | Status |
| --- | --- | --- |
| LUMIX DC-S5M2X / S5IIX, firmware 2.2, RTMP-capable model | Wi-Fi RTMP, H.264/AAC | Actual 30-second 1920×1080/25 stream captured by a development receiver. New app long-session test pending. |
| S5IIX European models listed by Panasonic | RTMPS only after security changes | Direct input unsupported by this version. Do not weaken TLS validation. |
| LUMIX GH5II | RTMP/RTMPS documented | Candidate only; firmware/region and app test pending. |
| Canon EOS R5 Mark II | RTMP/RTMPS described by Canon; Camera Connect setup | Candidate only; custom local URL and app test pending. |
| Generic FFmpeg H.264/AAC publisher | RTMP | Synthetic real-process integration tested. |
| Generic credential-free RTSP source | RTSP/TCP | Code compiles; runtime test pending. |

## S5IIX setup

Join the same trusted router as the Mac. In Setup → IN/OUT → Streaming choose Wi-Fi and a supported H.264 FHD mode. Copy the full FrameRelay destination into Streaming Address. Start FrameRelay before pressing video-record on the camera with Streaming Function ON. Stop on the camera to finish a take. Reserve the Mac's selected IP at the router for daily reuse.

The firmware-specific security supplement supersedes the older manual: wired RTP/RTSP was removed; Wi-Fi/phone USB tethering remain, and listed European variants require RTMPS. Phone USB tethering is not a Mac USB webcam input. No firmware update is performed by this app.

## Acceptance test for another device

Record a short take with motion and a clap. Verify detail, source resolution/frame rate, audio channels and lip sync. Stop and start a second take. Check both finalized files and recovery after disconnect. Then test a session of your intended duration. Supply the model, region, firmware, codec, format and test duration in a compatibility contribution; remove IPs, stream keys and personal footage from reports.

## Primary sources

- [Panasonic S5IIX security/streaming changes](https://eww.pavc.panasonic.co.jp/dscoi/DC-S5M2X/html/DC-S5M2X_DVQP2992_eng/0197.html)
- [Panasonic S5IIX streaming settings](https://eww.pavc.panasonic.co.jp/dscoi/DC-S5M2X/html/DC-S5M2X_DVQP2992_eng/0145.html)
- [Panasonic GH5II streaming function](https://eww.pavc.panasonic.co.jp/dscoi/DC-GH5M2/html/DC-GH5M2_DVQP2461_eng/0127.html)
- [Canon R5 Mark II streaming setup](https://cam.start.canon/en/C017/manual/html/UG-06_Network_0110.html)
- [Canon R5 Mark II movie features, including RTMP/RTMPS](https://personal.canon.jp/product/camera/eos/r5mk2/feature/movie)
- [FFmpeg RTMP/RTSP protocol documentation](https://ffmpeg.org/ffmpeg-protocols.html)
