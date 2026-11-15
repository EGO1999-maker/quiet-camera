import plistlib
import sys
import zipfile

phone_only = '--phone-only' in sys.argv
with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None
    root = 'Payload/QuietRecorder.app/'
    bundles = [(root, 'com.ego.quietrecorder', 'iPhoneOS')]
    if not phone_only:
        bundles.append((root+'Watch/QuietRecorderWatch.app/', 'com.ego.quietrecorder.watchkitapp', 'WatchOS'))
    for path, bundle, platform in bundles:
        info = plistlib.loads(archive.read(path+'Info.plist'))
        assert info['CFBundleIdentifier'] == bundle
        assert info['CFBundleShortVersionString'] == '1.0.0'
        assert info['NSMicrophoneUsageDescription']
        assert 'audio' in info['UIBackgroundModes']
        assert platform in info['CFBundleSupportedPlatforms'], info['CFBundleSupportedPlatforms']
        assert archive.read(path+info['CFBundleExecutable'])[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe')
        if platform == 'WatchOS':
            assert info['WKApplication']
            assert info['WKCompanionAppBundleIdentifier'] == 'com.ego.quietrecorder'
        print('Verified executable, microphone permission, background audio and platform:', bundle)
    if phone_only:
        assert not any(n.startswith(root+'Watch/') for n in archive.namelist())
print('Packaging verified. Unsigned build; hardware recording and Watch installation still require device tests.')
