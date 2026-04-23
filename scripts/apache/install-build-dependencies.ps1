param (
    [Parameter(Mandatory)] [string] $Arch,
    [Parameter(Mandatory)] [string] $PcrePackage
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

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
