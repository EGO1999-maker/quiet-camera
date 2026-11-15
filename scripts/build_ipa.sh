#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_project.py
mkdir -p build
xcodebuild -project QuietCamera.xcodeproj -scheme QuietCamera \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/QuietCamera.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  archive | tee build/build.log

# SideStore signs this app on the user's device. No Apple credentials in CI.
mkdir -p build/package/Payload
ditto build/QuietCamera.xcarchive/Products/Applications/QuietCamera.app \
  build/package/Payload/QuietCamera.app
(cd build/package && /usr/bin/zip -qry ../QuietCamera.ipa Payload)
python3 scripts/verify_ipa.py build/QuietCamera.ipa
shasum -a 256 build/QuietCamera.ipa > build/QuietCamera.ipa.sha256
