# Virtual camera providers

Status on 10 October 2026: FrameRelay supports feeding the separately signed **VirtualCamera4Mac** extension through public Core Media IO APIs. This route does not require the user to join the Apple Developer Program. The default build still excludes FrameRelay's own extension. Client interoperability must be tested on the target Mac; compilation alone is not evidence of usable video.

## No personal membership: separately signed provider

[VirtualCamera4Mac v0.0.7](https://github.com/m96-chan/VirtualCamera4Mac/releases/tag/v0.0.7) is an independent Apache-2.0 open-source project. Install its unchanged official release into `/Applications`, launch its menu-bar app, request activation and complete macOS Camera Extensions approval. Select **VirtualCamera4Mac** in FrameRelay, connect output, then select that webcam in Recordly. The provider app owns installation and removal; FrameRelay does not use another publisher's signing identity or modify its bundle. The provider UI does not have to remain open to feed its extension.

The reviewed v0.0.7 DMG SHA256 is `88846e42b6fdb96bd4b7d2a61a4b24d2600e413436d9c68c8ec8372d618126ee`. On the development Mac, its unchanged app verified with Developer ID Application **Yusuke Harada (9U26G7YWJ9)**, a stapled notarization ticket and accepted Gatekeeper assessment. This validates publisher/package integrity, not the absence of defects. It is an early hobby project with an unstable API. FrameRelay does not bundle or automatically download it.

The provider accepts any local CMIO producer. Other local apps can feed it and camera clients can consume it under macOS permissions; do not treat its input as private to FrameRelay. Choose one producer at a time. **Connect webcam automatically** is opt-in and retries after the registered device appears. Disconnect disables that preference. Recording and receiver startup have independent switches.

The host sends IOSurface-backed 1920×1080 BGRA samples at 30 fps through a bounded sink queue, requests matching source format and drops incoming frames if the queue is full. No growing frame backlog is kept. The provider supplies its standby image when input stalls. A camera's 25 fps network source is converted to a 30 fps webcam; this does not create additional motion detail. Video only: select a separate microphone in Recordly. Camera audio remains available in FrameRelay's optional original stream recordings.

Runtime verification uses the opt-in `Tests/VirtualCameraHarness/main.swift` (synthetic bars plus changing marker). Its capture mode refuses to request camera permission. Test actual dimensions and changing frames, followed by a real Recordly session, before relying on the workflow. Public source and signed package availability alone do not establish that those tests passed.


## FrameRelay's own extension — separate developer path

There is no Apple Developer Program membership or valid signing identity on the development Mac. FrameRelay's own extension remains compile-only. This limitation does not apply to the ordinary producer feeding a separately signed provider. No membership purchase is necessary for that route.

## Intended behavior

The host sends 1080p30 BGRA frames through a bounded CMIO sink queue. The extension serves a video source named **FrameRelay Camera**. Source clients can include AVFoundation-compatible applications, subject to actual application tests and macOS permission. Audio is separate; this is not a virtual microphone.

The extension checks the producer's code-signing identifier, Apple trust and matching team identifier. It emits black after one second without fresh frames and clears the stored frame after producer stop. These behaviors are implemented, not yet verified inside a running signed extension.

## Developer packaging path

Requires a qualifying Apple signing identity and matching provisioning profiles with the needed capabilities. Prepare identifiers for the host `media.voyd.FrameRelay` and extension `media.voyd.FrameRelay.CameraExtension`, host System Extension installation capability, extension App Sandbox, and the shared application group used by the signing script. Follow Apple's current capability and provisioning requirements. Profiles/certificates must stay outside this repository.

```sh
# Supply these in your own local environment; do not commit them.
export TEAM_ID=YOURTEAMID
export SIGN_IDENTITY='Your signing identity'
export HOST_PROFILE='/absolute/path/to/host.provisionprofile'
export EXTENSION_PROFILE='/absolute/path/to/extension.provisionprofile'
bash scripts/build-signed.sh
```

`TEAM_ID` must be the actual 10-character team ID. The script packages, signs inside-out and verifies the signatures; it does not validate every provisioning entitlement or notarize. This path has not been executed with real profiles. Identifier registration/capability availability and sandboxed producer validation still need a signed development test. If adopting different bundle identifiers, update the host, extension producer requirement, plists and profiles consistently.

Install a signed build into `/Applications`, then choose **Activate extension** and complete macOS's approval. The default receiver can live in the user's Applications folder, but that is not the camera-extension deployment path. There is no Recovery or SIP-disabling step. Distribution needs appropriate Developer ID signing, provisioning, notarization and testing; no notarized release is supplied.

## Required runtime checks before release

- Host activation, user approval, extension restart/deactivation and clean uninstall.
- Correctly signed producer accepted; other producers rejected, including same-identifier wrong-team code.
- Bounded frame queue, timestamps, live color and orientation at 1080p30.
- Two video consumers concurrently; stop/reconnect, host crash, stale-frame black output.
- Recordly, QuickTime and conferencing/browser clients tested individually.
- Long-session memory/CPU, sleep/wake and camera reconnect behavior.

Apple references: [camera extension guide](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o), [WWDC22 camera extensions](https://developer.apple.com/videos/play/wwdc2022/10022/), [system-extension installation](https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers), [macOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-macos).
