# Virtual camera: implementation and signing gate

Status on 10 October 2026: host CMIO sink bridge and modern source/sink camera extension compile. **Not installed or runtime verified.** The default build intentionally ships without the extension bundle. Activation cannot turn an ad-hoc receiver into an approved virtual camera.

There is no Apple Developer Program membership or valid signing identity on the development Mac. No certificate, purchase or entitlement approval has been obtained. The receiver works independently. Do not buy membership assuming this prototype is already production-ready.

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
