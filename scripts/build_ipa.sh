#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_project.py
mkdir -p build
swiftc QuietCamera/CaptureGeometry.swift scripts/CaptureGeometryTests.swift -o build/check-capture-geometry
build/check-capture-geometry
xcodebuild -project QuietCamera.xcodeproj -scheme QuietCamera \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/QuietCamera.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  archive | tee build/build.log

# SideStore signs this app on the user's device. No Apple credentials in CI.
mkdir -p build/package/Payload
ditto build/QuietCamera.xcarchive/Products/Applications/QuietCamera.app \
  build/package/Payload/QuietCamera.app
VERSION=$(python3 -c 'import plistlib; print(plistlib.load(open("build/package/Payload/QuietCamera.app/Info.plist", "rb"))["CFBundleShortVersionString"])')
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
IPA="QuietCamera-v${VERSION}.ipa"
(cd build/package && /usr/bin/zip -qry "../$IPA" Payload)
python3 scripts/verify_ipa.py "build/$IPA"
(cd build && shasum -a 256 "$IPA" > "$IPA.sha256")
