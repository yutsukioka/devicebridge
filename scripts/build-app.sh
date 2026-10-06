#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ "$(uname -m)" == arm64 ]] || { print -u2 'DeviceBridge requires a native arm64 host.'; exit 1; }
xcrun swift build --configuration release --arch arm64 --jobs 2
bin_dir="$(xcrun swift build --configuration release --arch arm64 --show-bin-path)"
app_dir="$PWD/artifacts/DeviceBridge.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$bin_dir/DeviceBridge" "$app_dir/Contents/MacOS/DeviceBridge"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DeviceBridge</string>
<key>CFBundleIdentifier</key><string>local.devicebridge.synthetic</string>
<key>CFBundleName</key><string>DeviceBridge</string>
<key>CFBundleDisplayName</key><string>DeviceBridge — Synthetic Demo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
[[ "$(lipo -archs "$app_dir/Contents/MacOS/DeviceBridge")" == arm64 ]]
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
print "Built local ad-hoc signed demo: $app_dir"
print 'Not notarized; no App Sandbox or production security claim.'
