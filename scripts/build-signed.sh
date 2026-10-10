#!/bin/bash
# Explicit development packaging path; no certificates/profiles are stored in this repository.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TEAM_ID:?Provide your Apple Developer Team ID}"
: "${SIGN_IDENTITY:?Provide an Apple Development or Developer ID Application signing identity}"
: "${HOST_PROFILE:?Path to matching host provisioning profile}"
: "${EXTENSION_PROFILE:?Path to matching extension provisioning profile}"
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid team ID' >&2; exit 1; }
bash scripts/build.sh
bash scripts/check-extension.sh
app='build/FrameRelay.app'
ext="$app/Contents/Library/SystemExtensions/media.voyd.FrameRelay.CameraExtension.systemextension"
mkdir -p "$ext/Contents/MacOS"
cp build/FrameRelayCameraExtension "$ext/Contents/MacOS/"
cp Resources/CameraExtension-Info.plist "$ext/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :FrameRelayTeamIdentifier $TEAM_ID" "$ext/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CMIOExtension:CMIOExtensionMachServiceName $TEAM_ID.media.voyd.FrameRelay.CameraExtension" "$ext/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSSystemExtensionUsageDescription string Make received video available as a virtual camera.' "$app/Contents/Info.plist"
cp "$HOST_PROFILE" "$app/Contents/embedded.provisionprofile"
cp "$EXTENSION_PROFILE" "$ext/Contents/embedded.provisionprofile"
python3 - "$TEAM_ID" <<'PY'
import plistlib, sys, pathlib
team = sys.argv[1]
shared = {'com.apple.security.application-groups': [team + '.media.voyd.FrameRelay']}
for filename, extra in [('host.entitlements', {'com.apple.developer.system-extension.install': True}), ('camera.entitlements', {'com.apple.security.app-sandbox': True})]:
    pathlib.Path('build', filename).write_bytes(plistlib.dumps(shared | extra))
PY
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --entitlements build/camera.entitlements "$ext"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --entitlements build/host.entitlements "$app"
codesign --verify --deep --strict "$app"
echo 'Signed bundle packaged; provisioning/activation/client runtime must still be verified. Install in /Applications before activation.'
