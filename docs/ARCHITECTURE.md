# Architecture

`Configuration` validates a private RTMP bind and passes arguments as an array to `Process`; no shell interpolation is used. RTSP credential URLs are rejected and are stripped before preference persistence. The user chooses a trusted external FFmpeg executable.

`ReceiverEngine` owns one FFmpeg process. It reads fixed-size 1080p BGRA frames off a serial decode queue, sends frames to the optional CMIO bridge, and publishes a throttled preview on the main queue. At most one preview update is queued. After stale frames it clears the preview; FFmpeg network timeouts and re-arm handle disconnects. The raw-frame pipe has significant bandwidth/CPU overhead; no low-latency or battery-efficiency claim is made.

Recording is a separate output of the same process. MKV packets are stream-copied and MP4 is remuxed after process termination. Successful remux permits deletion of that take's source MKV; failure preserves it. A crash can leave .inprogress.mkv files for manual recovery. No automatic library deletion or crash-recovery remux is performed. Clip names contain timestamps plus random suffixes. Recordings and app preferences are outside the repo.

Stop interrupts FFmpeg, with process-specific termination/kill fallback. Quit waits for receiver shutdown and remux. Disk reserve is checked before saving and during a live take. The selected IP is never silently changed. A per-user app lock prevents simultaneous host instances; another application binding the same port remains a connection error.

`LoginManager` manages only `~/Library/LaunchAgents/media.voyd.FrameRelay.plist`. Startup is opt-in, per-user, RunAtLoad with KeepAlive disabled. A second option explicitly starts the receiver when the app opens. The app is not a privileged service and does not bypass macOS Login Items controls.

`VirtualCamera` discovers only explicitly supported provider UIDs, selects a producer sink, requests matching 1080p BGRA source format and feeds a bounded CMIO queue. It can use a separately installed signed VirtualCamera4Mac provider without an install entitlement or user membership. Opt-in automatic connection discovers devices every three seconds and retries failures at most every ten seconds. The provider handles stale-frame output. It accepts other local producers; exclusivity/privacy must not be inferred. FrameRelay's own extension checks a matching signed producer but remains compile-only. No legacy DAL setting or virtual audio device is installed by the default build.
