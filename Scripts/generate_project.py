"""Generate the dependency-free Xcode project. Writes only project files in this checkout."""
from pathlib import Path
import hashlib
ROOT = Path(__file__).resolve().parents[1]
def ident(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
objects = {}
def add(name, value): objects[ident(name)] = value; return ident(name)
def arr(items): return '(' + ', '.join(items) + ',)'
files = sorted((ROOT/'Board').glob('*.swift'))
refs, builds = [], []
for file in files:
    ref=add(file.name, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Board/'+file.name+'"; sourceTree = SOURCE_ROOT;}'); refs.append(ref)
    builds.append(add(file.name+'build', '{isa = PBXBuildFile; fileRef = '+ref+';}'))
resources=[]
for name, kind in [('Resources','folder'),('Assets.xcassets','folder.assetcatalog'),('BoardPorcelain.icon','folder.iconcomposer.icon')]:
    ref=add(name,'{isa = PBXFileReference; lastKnownFileType = '+kind+'; path = "Board/'+name+'"; sourceTree = SOURCE_ROOT;}'); refs.append(ref)
    resources.append(add(name+'build','{isa = PBXBuildFile; fileRef = '+ref+';}'))
testRef=add('testFile','{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/BoardTests.swift; sourceTree = SOURCE_ROOT;}')
testBuild=add('testBuild','{isa = PBXBuildFile; fileRef = '+testRef+';}')
appProduct=add('appProduct','{isa = PBXFileReference; explicitFileType = wrapper.application; path = "Board.app"; sourceTree = BUILT_PRODUCTS_DIR;}')
testProduct=add('testProduct','{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = BoardTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
products=add('products','{isa = PBXGroup; name = Products; children = '+arr([appProduct,testProduct])+'; sourceTree = "<group>";}')
main=add('main','{isa = PBXGroup; children = '+arr(refs+[testRef,products])+'; sourceTree = "<group>";}')
source=add('sources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+arr(builds)+'; runOnlyForDeploymentPostprocessing = 0;}')
resource=add('resources','{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+arr(resources)+'; runOnlyForDeploymentPostprocessing = 0;}')
framework=add('frameworks','{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
testSources=add('testSources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+arr([testBuild])+'; runOnlyForDeploymentPostprocessing = 0;}')
def configs(scope, extra):
    ids=[]
    for mode in ['Debug','Release']:
        settings={'CLANG_ENABLE_MODULES':'YES','MACOSX_DEPLOYMENT_TARGET':'15.0','SDKROOT':'macosx','SWIFT_VERSION':'5.0','ARCHS':'arm64','CODE_SIGN_IDENTITY':'"-"','CODE_SIGN_STYLE':'Manual','ENABLE_HARDENED_RUNTIME':'YES','SWIFT_OPTIMIZATION_LEVEL':'"-Onone"' if mode=='Debug' else '"-O"','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else '""','ENABLE_TESTABILITY':'YES','DEBUG_INFORMATION_FORMAT':'dwarf','ONLY_ACTIVE_ARCH':'YES'}|extra
        ids.append(add(scope+mode,'{isa = XCBuildConfiguration; buildSettings = {'+' '.join(k+' = '+v+';' for k,v in settings.items())+'}; name = '+mode+';}'))
    return add(scope+'config','{isa = XCConfigurationList; buildConfigurations = '+arr(ids)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
projectConfig=configs('project',{})
appConfig=configs('app',{'PRODUCT_NAME':'"Board"','PRODUCT_MODULE_NAME':'Board','PRODUCT_BUNDLE_IDENTIFIER':'com.tommyent.Board','INFOPLIST_FILE':'Board/Info.plist','ASSETCATALOG_COMPILER_APPICON_NAME':'BoardPorcelain','LD_RUNPATH_SEARCH_PATHS':'"$(inherited) @executable_path/../Frameworks"','ENABLE_APP_SANDBOX':'NO'})
testConfig=configs('test',{'PRODUCT_NAME':'BoardTests','PRODUCT_BUNDLE_IDENTIFIER':'com.tommyent.Board.tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'"$(BUILT_PRODUCTS_DIR)/Board.app/Contents/MacOS/Board"','BUNDLE_LOADER':'"$(TEST_HOST)"','LD_RUNPATH_SEARCH_PATHS':'"$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks"'})
proxy=add('proxy','{isa = PBXContainerItemProxy; containerPortal = '+ident('project')+'; proxyType = 1; remoteGlobalIDString = '+ident('app')+'; remoteInfo = Board;}')
dep=add('dependency','{isa = PBXTargetDependency; target = '+ident('app')+'; targetProxy = '+proxy+';}')
app=add('app','{isa = PBXNativeTarget; buildConfigurationList = '+appConfig+'; buildPhases = '+arr([source,framework,resource])+'; buildRules = (); dependencies = (); name = Board; productName = "Board"; productReference = '+appProduct+'; productType = "com.apple.product-type.application";}')
test=add('test','{isa = PBXNativeTarget; buildConfigurationList = '+testConfig+'; buildPhases = '+arr([testSources])+'; buildRules = (); dependencies = '+arr([dep])+'; name = BoardTests; productName = BoardTests; productReference = '+testProduct+'; productType = "com.apple.product-type.bundle.unit-test";}')
proj=add('project','{isa = PBXProject; attributes = {LastUpgradeCheck = 2700;}; buildConfigurationList = '+projectConfig+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = '+main+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+arr([app,test])+';}')
out=ROOT/'Board.xcodeproj'; out.mkdir(exist_ok=True)
(out/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+proj+';}\n')
schemes=out/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
ref=lambda id,name: f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Board.xcodeproj"/>'
(schemes/'Board.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app,'Board.app')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test,'BoardTests.xctest')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'Board.app')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'Board.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated Board.xcodeproj')
