"""Generate companion iOS + single-target watchOS project with no third-party dependencies."""
import hashlib
import json
import plistlib
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def oid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(object_name, isa, **fields):
    key = oid(object_name)
    objects[key] = {"isa": isa, **fields}
    return key

def icon(path, platform):
    path.mkdir(parents=True, exist_ok=True)
    # A pink waveform on a solid dark background, generated at native icon resolution.
    pixels = bytearray()
    heights = [120, 240, 390, 570, 390, 240, 120]
    for y in range(1024):
        pixels.append(0)
        for x in range(1024):
            color = (24, 20, 28)
            for i, height in enumerate(heights):
                cx = 242 + i * 90
                if abs(x - cx) <= 24 and abs(y - 512) <= height / 2:
                    color = (255, 186, 209)
                    break
            pixels.extend(color)
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB",1024,1024,8,2,0,0,0))
    png += chunk(b"IDAT", zlib.compress(bytes(pixels), 9)) + chunk(b"IEND", b"")
    (path / "AppIcon.png").write_bytes(png)
    (path / "Contents.json").write_text(json.dumps({"images":[{"filename":"AppIcon.png", "idiom":"universal", "platform":platform, "size":"1024x1024"}],"info":{"author":"xcode","version":1}}))

def plist(folder, watch=False):
    info = {
        "CFBundleDevelopmentRegion":"ko", "CFBundleDisplayName":"Quiet Recorder",
        "CFBundleExecutable":"$(EXECUTABLE_NAME)", "CFBundleIdentifier":"$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion":"6.0", "CFBundleName":"$(PRODUCT_NAME)",
        "CFBundlePackageType":"APPL", "CFBundleShortVersionString":"1.0.0", "CFBundleVersion":"1",
        "NSMicrophoneUsageDescription":"선택한 기기의 내장 마이크로 음성을 녹음하고 기기에 저장합니다.",
        "UIBackgroundModes":["audio"],
    }
    if watch:
        info.update(WKApplication=True, WKCompanionAppBundleIdentifier="com.ego.quietrecorder",
                    WKRunsIndependentlyOfCompanionApp=True)
    else:
        info.update(LSRequiresIPhoneOS=True, UILaunchScreen={},
                    UIApplicationSceneManifest={"UIApplicationSupportsMultipleScenes":False},
                    UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait"],
                    UIUserInterfaceStyle="Dark", UIFileSharingEnabled=True, LSSupportsOpeningDocumentsInPlace=True)
    (ROOT / folder / "Info.plist").write_bytes(plistlib.dumps(info))
    icon(ROOT / folder / "Assets.xcassets" / "AppIcon.appiconset", "watchos" if watch else "ios")

shared_names = ["RecordingModel.swift", "RecorderStore.swift", "RecorderLink.swift"]
shared_refs = [add("shared:"+n,"PBXFileReference",lastKnownFileType="sourcecode.swift",path=n,sourceTree="<group>") for n in shared_names]
shared_group = add("shared-group","PBXGroup",children=shared_refs,path="Shared",sourceTree="<group>")
targets, products, groups = [], [], [shared_group]
for platform, folder, name, bundle, entry in [
    ("iphoneos","iOS","QuietRecorder","com.ego.quietrecorder","QuietRecorderApp.swift"),
    ("watchos","Watch","QuietRecorderWatch","com.ego.quietrecorder.watchkitapp","QuietRecorderWatchApp.swift")
]:
    watch = platform == "watchos"
    plist(folder, watch)
    ref = add(folder+":entry","PBXFileReference",lastKnownFileType="sourcecode.swift",path=entry,sourceTree="<group>")
    assets = add(folder+":assets","PBXFileReference",lastKnownFileType="folder.assetcatalog",path="Assets.xcassets",sourceTree="<group>")
    groups.append(add(folder+":group","PBXGroup",children=[ref,assets],path=folder,sourceTree="<group>"))
    product = add(folder+":product","PBXFileReference",explicitFileType="wrapper.application",includeInIndex=0,path=name+".app",sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product)
    files = [add(folder+":build:"+r,"PBXBuildFile",fileRef=r) for r in shared_refs+[ref]]
    sources = add(folder+":sources","PBXSourcesBuildPhase",buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
    resources = add(folder+":resources","PBXResourcesBuildPhase",buildActionMask=2147483647,files=[add(folder+":asset-build","PBXBuildFile",fileRef=assets)],runOnlyForDeploymentPostprocessing=0)
    frameworks = add(folder+":frameworks","PBXFrameworksBuildPhase",buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
    configs=[]
    for config in ["Debug","Release"]:
        settings={"PRODUCT_BUNDLE_IDENTIFIER":bundle,"PRODUCT_NAME":name,"SDKROOT":platform,
            "SUPPORTED_PLATFORMS":"watchos watchsimulator" if watch else "iphoneos iphonesimulator",
            "TARGETED_DEVICE_FAMILY":"4" if watch else "1", "SWIFT_VERSION":"5.0",
            "INFOPLIST_FILE":folder+"/Info.plist", "GENERATE_INFOPLIST_FILE":"NO",
            "CODE_SIGN_STYLE":"Automatic", "ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon",
            "SKIP_INSTALL":"YES" if watch else "NO", "SUPPORTS_MACCATALYST":"NO",
            "LD_RUNPATH_SEARCH_PATHS":["$(inherited)","@executable_path/Frameworks"],
            "WATCHOS_DEPLOYMENT_TARGET":"10.0", "IPHONEOS_DEPLOYMENT_TARGET":"17.0",
            "SWIFT_OPTIMIZATION_LEVEL":"-Onone" if config=="Debug" else "-O",
            "DEBUG_INFORMATION_FORMAT":"dwarf" if config=="Debug" else "dwarf-with-dsym",
        }
        configs.append(add(folder+":"+config,"XCBuildConfiguration",name=config,buildSettings=settings))
    configuration = add(folder+":configs","XCConfigurationList",buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName="Release")
    targets.append(add(folder+":target","PBXNativeTarget",name=name,productName=name,productReference=product,
        productType="com.apple.product-type.application",buildConfigurationList=configuration,
        buildPhases=[sources,frameworks,resources],buildRules=[],dependencies=[]))

embed = add("embed-watch","PBXCopyFilesBuildPhase",buildActionMask=2147483647,dstPath="$(CONTENTS_FOLDER_PATH)/Watch",dstSubfolderSpec=16,
    files=[add("watch-copy","PBXBuildFile",fileRef=products[1],settings={"ATTRIBUTES":["RemoveHeadersOnCopy"]})],name="Embed Watch Content",runOnlyForDeploymentPostprocessing=0)
proxy = add("watch-proxy","PBXContainerItemProxy",containerPortal=oid("project"),proxyType=1,remoteGlobalIDString=targets[1],remoteInfo="QuietRecorderWatch")
dependency = add("watch-dependency","PBXTargetDependency",target=targets[1],targetProxy=proxy)
objects[targets[0]]["buildPhases"].append(embed)
objects[targets[0]]["dependencies"].append(dependency)
products_group=add("products","PBXGroup",children=products,name="Products",sourceTree="<group>")
main=add("main","PBXGroup",children=groups+[products_group],sourceTree="<group>")
pc=[]
for config in ["Debug","Release"]:
    pc.append(add("project:"+config,"XCBuildConfiguration",name=config,buildSettings={"CLANG_ENABLE_MODULES":"YES","CLANG_ENABLE_OBJC_ARC":"YES","SWIFT_VERSION":"5.0"}))
pc=add("project-configs","XCConfigurationList",buildConfigurations=pc,defaultConfigurationIsVisible=0,defaultConfigurationName="Release")
project=add("project","PBXProject",attributes={"LastUpgradeCheck":"1600"},buildConfigurationList=pc,
    compatibilityVersion="Xcode 14.0",developmentRegion="ko",hasScannedForEncodings=0,knownRegions=["ko","en","Base"],
    mainGroup=main,productRefGroup=products_group,projectDirPath="",projectRoot="",targets=targets)
directory=ROOT/"QuietRecorder.xcodeproj"
directory.mkdir(exist_ok=True)
(directory/"project.pbxproj").write_bytes(plistlib.dumps({"archiveVersion":"1","classes":{},"objectVersion":"56","objects":objects,"rootObject":project},sort_keys=False))
schemes=directory/"xcshareddata"/"xcschemes"
schemes.mkdir(parents=True,exist_ok=True)
reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[0]}" BuildableName="QuietRecorder.app" BlueprintName="QuietRecorder" ReferencedContainer="container:QuietRecorder.xcodeproj"/>'
(schemes/"QuietRecorder.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print("Generated iPhone and Watch companion targets")
