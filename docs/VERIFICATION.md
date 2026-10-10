# Verification record

10 October 2026 · Apple Silicon M4 · macOS 27.0 · Swift 6.4 compiler, Swift 5 language mode.

Passed before publication:

- Receiver app build for macOS 14+ and ad-hoc signature verification.
- Native studio layout inspected; sidebar wrapping corrected. Installed receiver auto-started and bound its saved LAN address.
- Per-user login agent loaded; an actual logout/login or reboot is not yet tested.
- Camera extension compile against the installed Apple SDK; no activation test.
- Configuration validation for public/wildcard/malformed addresses, ports, paths and URL credentials.
- Independent RTMP synthetic 1920×1080/25 H.264 + AAC producers.
- Two successive audio-enabled takes: preview frames, MP4 finalization, clean full decode and re-arm.
- Audio-disabled recording: video present, no audio track.
- Preview-only session: frames present, recording directory not created.

The integration harness uses the same `ReceiverEngine` as the app. Test media is synthetic and remains in private temporary storage, outside the repository. A previous development receiver captured a real S5IIX 30-second 1080p25 stream; that is transport evidence, not a full new-app camera test.

Still required: real camera operation in this app, longer sessions, measured latency/lip sync, RTSP hardware, Intel/older macOS, real reboot/login, signed camera activation/client tests, notarized distribution. No public release should remove these qualifications without evidence.


## Separately signed provider route

The no-membership CMIO producer path for VirtualCamera4Mac v0.0.7 builds, with explicit source/sink direction validation, 1080p BGRA source negotiation and opt-in automatic connection. The downloaded unchanged release's checksum, Developer ID signature, stapled notarization and Gatekeeper assessment were checked; its app is installed separately. **Extension activation, actual producer frames and Recordly capture remain pending approval/testing.** This is not a completed webcam claim.

The synthetic runtime harness compiles and can measure dimensions, color bars, changing frame markers and timestamp rates. Merely listing a camera is not its pass condition. Camera capture requires existing authorization; the harness never grants itself permission. CI compiles it but does not activate a camera provider.

Five real network-camera MP4 takes in the local recording library passed full decode, all native 1920×1080/25 with AAC. Their approximate durations are 150.48, 116.08, 59.00, 105.80 and 105.08 seconds. One take interrupted during the old app update was remuxed without re-encoding and its recovery MKV retained. Final focus, facecam composition, latency, lip sync and long-session reliability remain unassessed; no media was uploaded.

A real shutdown hang in the original build was reproduced while replacing it. The new quit path keeps the normal run loop alive until receiver/remux work completes, then terminates; quitting the updated idle-listener app completed with no remaining app process. Receiver start is also guarded while stopping/converting. Configuration and real-engine two-take/audio/preview-only tests passed again after those changes.
