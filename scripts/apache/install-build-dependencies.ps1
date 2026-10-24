param (
    [Parameter(Mandatory)] [string] $Arch,
    [Parameter(Mandatory)] [string] $PcrePackage
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# Both linkage variants must use the same reviewed security backport. The
# overlay's distinct version also invalidates vcpkg's old binary cache entries.
$env:VCPKG_OVERLAY_PORTS = Join-Path $PSScriptRoot 'vcpkg-ports'
"VCPKG_OVERLAY_PORTS=$env:VCPKG_OVERLAY_PORTS" | Add-Content $env:GITHUB_ENV

if ($Arch -eq 'arm64') {
    $overlay = Join-Path $env:RUNNER_TEMP 'winlib-vcpkg-triplets'
    New-Item $overlay -ItemType Directory -Force | Out-Null
    $toolset = switch -Regex ($env:VCToolsVersion) { '^14\.2' { 'v142' }; '^14\.[34]' { 'v143' }; '^14\.5' { 'v145' }; default { throw 'ARM64 toolchain has not been selected' } }
    # CMake can otherwise prefer the runner's native GNU-style clang over MSVC.
    # Pin both compiler paths so vcpkg's compiler checks and ports use this lane.
    $compiler = (Get-Command cl.exe).Source.Replace('\', '/')
    $chainload = (Join-Path $overlay 'msvc-arm64.cmake').Replace('\', '/')
    @(
        "set(CMAKE_C_COMPILER `"$compiler`" CACHE FILEPATH `"`" FORCE)",
        "set(CMAKE_CXX_COMPILER `"$compiler`" CACHE FILEPATH `"`" FORCE)",
        'include("C:/vcpkg/scripts/toolchains/windows.cmake")'
    ) | Set-Content $chainload
    foreach ($linkage in 'dynamic', 'static') {
        $name = if ($linkage -eq 'static') { 'arm64-windows-static-md' } else { 'arm64-windows' }
        @(
            'set(VCPKG_TARGET_ARCHITECTURE arm64)',
            'set(VCPKG_CRT_LINKAGE dynamic)',
            'set(VCPKG_BUILD_TYPE release)',
            "set(VCPKG_LIBRARY_LINKAGE $linkage)",
            "set(VCPKG_PLATFORM_TOOLSET $toolset)",
            "set(VCPKG_PLATFORM_TOOLSET_VERSION $($env:VCToolsVersion.TrimEnd('\')))",
            "set(VCPKG_CMAKE_SYSTEM_VERSION $($env:WindowsSDKVersion.TrimEnd('\')))",
            # Keep the complete compiler/SDK environment imported above. v142
            # has no native ARM64-hosted vcvars environment for vcpkg to load.
            'set(VCPKG_LOAD_VCVARS_ENV OFF)',
            'set(VCPKG_ENV_PASSTHROUGH_UNTRACKED PATH INCLUDE LIB LIBPATH)',
            "set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE `"$chainload`")"
        ) | Set-Content (Join-Path $overlay "$name.cmake")
    }
    $env:VCPKG_OVERLAY_TRIPLETS = $overlay
    "VCPKG_OVERLAY_TRIPLETS=$overlay" | Add-Content $env:GITHUB_ENV
}

$sharedTriplet = "$Arch-windows"
$staticTriplet = "$Arch-windows-static-md"
$aprExportsRoot = Join-Path $env:GITHUB_WORKSPACE 'apache-apr-exports'
$sharedAprPackages = @(
    'apr[private-headers]',
    'apr-util[crypto]'
)
$sharedPackages = @(
    'brotli',
    'curl[openssl,http2,brotli]',
    'expat',
    'jansson',
    'lua[tools]',
    'nghttp2',
    'openssl',
    $PcrePackage,
    'zlib'
)
$staticPackages = @(
    'apr',
    'apr-util',
    'expat',
    $PcrePackage,
    'zlib'
)

if (Test-Path $aprExportsRoot) {
    Remove-Item -Path $aprExportsRoot -Recurse -Force
}
New-Item -Path $aprExportsRoot -ItemType Directory -Force | Out-Null

& vcpkg install --triplet $sharedTriplet @sharedPackages

# The PHP SDK package layout still expects APR export files, but vcpkg does
# not install them. Build APR locally instead of restoring it from binary cache,
# then stage the exports before any later vcpkg operation can affect buildtrees.
$hadBinarySources = Test-Path Env:VCPKG_BINARY_SOURCES
$originalBinarySources = $env:VCPKG_BINARY_SOURCES
try {
    $env:VCPKG_BINARY_SOURCES = 'clear'
    & vcpkg install --triplet $sharedTriplet @sharedAprPackages
} finally {
    if ($hadBinarySources) {
        $env:VCPKG_BINARY_SOURCES = $originalBinarySources
    } else {
        Remove-Item Env:VCPKG_BINARY_SOURCES -ErrorAction SilentlyContinue
    }
}

$aprExportSpecs = @(
    [pscustomobject] @{
        BuildTree = Join-Path 'C:/vcpkg/buildtrees/apr' "$sharedTriplet-rel"
        FileName = 'libapr-1.exp'
    },
    [pscustomobject] @{
        BuildTree = Join-Path 'C:/vcpkg/buildtrees/apr-util' "$sharedTriplet-rel"
        FileName = 'libaprutil-1.exp'
    }
)

foreach ($exportSpec in $aprExportSpecs) {
    if (-not (Test-Path $exportSpec.BuildTree)) {
        throw "APR export buildtree was not produced: $($exportSpec.BuildTree)"
    }

    $exportFile = Get-ChildItem -Path $exportSpec.BuildTree -Filter $exportSpec.FileName -File -Recurse |
        Select-Object -First 1

    if (-not $exportFile) {
        throw "APR export file $($exportSpec.FileName) was not found in $($exportSpec.BuildTree)."
    }

    Copy-Item -Path $exportFile.FullName -Destination (Join-Path $aprExportsRoot $exportSpec.FileName) -Force
}

& vcpkg install --triplet $staticTriplet @staticPackages
