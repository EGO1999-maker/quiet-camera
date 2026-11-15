"""Check packaging before presenting an unsigned IPA for SideStore."""
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None, "Corrupt IPA"
    root = "Payload/QuietCamera.app/"
    info = plistlib.loads(archive.read(root + "Info.plist"))
    assert info["CFBundleIdentifier"] == "com.ego.quietcamera"
    assert info["CFBundlePackageType"] == "APPL"
    binary = archive.read(root + info["CFBundleExecutable"])
    assert binary[:4] in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"), "Not a Mach-O binary"
    assert info.get("NSCameraUsageDescription")
    assert info.get("NSPhotoLibraryAddUsageDescription")
    assert info.get("NSPhotoLibraryUsageDescription")
    assert not info.get("NSMicrophoneUsageDescription")
    assert not info.get("UIBackgroundModes")
    intent_metadata = [entry for entry in archive.infolist()
                       if entry.filename.startswith(root + "Metadata.appintents/") and entry.file_size > 0]
    assert intent_metadata, "Missing App Intents metadata: the camera action would not be discoverable"
    print("App Intents metadata verified:", ", ".join(entry.filename[len(root):] for entry in intent_metadata))
    assert set(info["UISupportedInterfaceOrientations"]) == {
        "UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"
    }
print("IPA packaging verified (unsigned; install and sign with SideStore).")
