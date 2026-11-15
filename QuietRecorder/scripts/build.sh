#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_project.py
mkdir -p build
swiftc Shared/RecordingModel.swift scripts/RecordingModelTests.swift -o build/check-model
build/check-model
xcodebuild -project QuietRecorder.xcodeproj -scheme QuietRecorder \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/QuietRecorder.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  archive | tee build/build.log
mkdir -p build/package/Payload
ditto build/QuietRecorder.xcarchive/Products/Applications/QuietRecorder.app build/package/Payload/QuietRecorder.app
VERSION=$(python3 -c 'import plistlib; print(plistlib.load(open("build/package/Payload/QuietRecorder.app/Info.plist", "rb"))["CFBundleShortVersionString"])')
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
IPA="QuietRecorder-v${VERSION}.ipa"
(cd build/package && zip -qry "../$IPA" Payload)
python3 scripts/verify_ipa.py "build/$IPA"
(cd build && shasum -a 256 "$IPA" > "$IPA.sha256")
# A phone-only fallback for signing tools which cannot install a Watch companion.
python3 - "$PWD/build/$IPA" "$PWD/build/QuietRecorder-iPhone-v${VERSION}.ipa" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as source, zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as dest:
    for entry in source.infolist():
        if not entry.filename.startswith('Payload/QuietRecorder.app/Watch/'):
            dest.writestr(entry, source.read(entry.filename))
PY
python3 scripts/verify_ipa.py "build/QuietRecorder-iPhone-v${VERSION}.ipa" --phone-only
(cd build && shasum -a 256 "QuietRecorder-iPhone-v${VERSION}.ipa" > "QuietRecorder-iPhone-v${VERSION}.ipa.sha256")
