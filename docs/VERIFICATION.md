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
