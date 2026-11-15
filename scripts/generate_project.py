"""Generate the Xcode project using only Python's standard library."""
import hashlib
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def oid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def add(object_name, isa, **fields):
    key = oid(object_name)
    objects[key] = {"isa": isa, **fields}
    return key


source_names = ["QuietCameraApp.swift", "CameraEngine.swift", "CameraView.swift", "CaptureGeometry.swift", "GalleryIndex.swift", "PhotoGalleryStore.swift", "PhotoGalleryView.swift"]
source_refs, build_refs = [], []
for name in source_names:
    ref = add(name, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=name, sourceTree="<group>")
    source_refs.append(ref)
    build_refs.append(add("build:" + name, "PBXBuildFile", fileRef=ref))
assets = add("assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path="Assets.xcassets", sourceTree="<group>")
asset_build = add("assets-build", "PBXBuildFile", fileRef=assets)
info = add("info", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>")
product = add("product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="QuietCamera.app", sourceTree="BUILT_PRODUCTS_DIR")
source_group = add("source-group", "PBXGroup", children=source_refs + [assets, info], path="QuietCamera", sourceTree="<group>")
products = add("products", "PBXGroup", children=[product], name="Products", sourceTree="<group>")
main_group = add("main", "PBXGroup", children=[source_group, products], sourceTree="<group>")
sources = add("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=build_refs, runOnlyForDeploymentPostprocessing=0)
resources = add("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[asset_build], runOnlyForDeploymentPostprocessing=0)
frameworks = add("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
project_configs, target_configs = [], []
for config in ("Debug", "Release"):
    project_configs.append(add("project-" + config, "XCBuildConfiguration", name=config, buildSettings={
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "SDKROOT": "iphoneos",
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0", "SWIFT_VERSION": "5.0",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if config == "Debug" else "",
    }))
    target_configs.append(add("target-" + config, "XCBuildConfiguration", name=config, buildSettings={
        "PRODUCT_BUNDLE_IDENTIFIER": "com.ego.quietcamera", "PRODUCT_NAME": "$(TARGET_NAME)",
        "INFOPLIST_FILE": "QuietCamera/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "TARGETED_DEVICE_FAMILY": "1",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
        "CODE_SIGN_STYLE": "Automatic", "SWIFT_VERSION": "5.0", "SKIP_INSTALL": "NO",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    }))
pc = add("project-configs", "XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
tc = add("target-configs", "XCConfigurationList", buildConfigurations=target_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target = add("target", "PBXNativeTarget", buildConfigurationList=tc, buildPhases=[sources, frameworks, resources], buildRules=[], dependencies=[], name="QuietCamera", productName="QuietCamera", productReference=product, productType="com.apple.product-type.application")
project = add("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "TargetAttributes": {target: {"CreatedOnToolsVersion": "16.0"}}}, buildConfigurationList=pc, compatibilityVersion="Xcode 14.0", developmentRegion="ko", hasScannedForEncodings=0, knownRegions=["ko", "en", "Base"], mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[target])

# Xcode accepts XML property lists as well as the usual OpenStep representation.
directory = ROOT / "QuietCamera.xcodeproj"
directory.mkdir(exist_ok=True)
(directory / "project.pbxproj").write_bytes(plistlib.dumps({"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project}, sort_keys=False))
scheme_dir = directory / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="QuietCamera.app" BlueprintName="QuietCamera" ReferencedContainer="container:QuietCamera.xcodeproj"/>'
(scheme_dir / "QuietCamera.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding="utf-8")
print("Generated QuietCamera.xcodeproj")
