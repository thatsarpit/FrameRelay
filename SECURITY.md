# Security

FrameRelay is an early preview for trusted local networks. RTMP input is unencrypted and unauthenticated; a stream path is not authentication. Do not port-forward it or expose it on public/untrusted networks. Binding is restricted to a specific private IPv4/loopback address, not every interface. This does not isolate it from other peers on that LAN.

Preferences are local, not encrypted secret storage. Credential-bearing RTSP URLs are deliberately unsupported. Avoid including tokens in URL paths/query parameters. Select only a trusted FFmpeg executable. Keep FFmpeg/macOS updated; media parsers process input from network peers.

Clips stay local and may contain sensitive images/audio. Preview-only mode saves no media. Recordings can be enabled automatically only through explicit app settings. No telemetry/upload feature exists. Crash-recovery MKVs may remain; inspect them before deletion. Normal filesystem permissions do not replace disk encryption or backups.

FrameRelay's own camera extension is not shipped in default builds. An optional separately signed VirtualCamera4Mac provider is supported via public CMIO APIs; install only the unchanged official release and use macOS's normal approval flow. That provider accepts any local producer, so other local applications can supply its frames. Its signature does not make input exclusive to FrameRelay. Both paths supply video only, with no all-app compatibility claim. FrameRelay never disables SIP, enables legacy DAL support or re-signs another publisher's extension.

For a vulnerability, use GitHub's private vulnerability reporting if enabled; otherwise contact the maintainer through their public profile without publishing exploit details or private data in an issue.
