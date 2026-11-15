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
    assert info["UISupportedInterfaceOrientations"] == ["UIInterfaceOrientationPortrait"]
print("IPA packaging verified (unsigned; install and sign with SideStore).")
