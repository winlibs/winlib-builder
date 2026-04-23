param (
    [Parameter(Mandatory)] [string] $Arch,
    [Parameter(Mandatory)] [string] $PcreLibPath,
    [Parameter(Mandatory)] [string] $AprIconvVersion
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

. (Join-Path $PSScriptRoot 'common.ps1')

function Get-FirstDirectoryWithChild {
    param(
        [Parameter(Mandatory)] [string[]] $Candidates,
        [Parameter(Mandatory)] [string] $ChildPath,
        [Parameter(Mandatory)] [string] $Description
    )

    foreach ($candidate in $Candidates | Select-Object -Unique) {
        if (Test-Path (Join-Path $candidate $ChildPath)) {
            return $candidate
        }
    }

    throw "$Description was not found. Checked: $($Candidates -join ', ')"
}

$sharedTriplet = "$Arch-windows"
$staticTriplet = "$Arch-windows-static-md"
$sharedRoot = "C:/vcpkg/installed/$sharedTriplet"
$staticRoot = "C:/vcpkg/installed/$staticTriplet"
$depsRoot = Join-Path $env:GITHUB_WORKSPACE 'deps-install'
$iconvConfigArch = if ($Arch -eq 'x64') { 'x64' } else { 'Win32' }
$pcreLibrary = Join-Path $sharedRoot $PcreLibPath
$curlLibrary = if (Test-Path (Join-Path $sharedRoot 'lib\libcurl_imp.lib')) {
    Join-Path $sharedRoot 'lib\libcurl_imp.lib'
} else {
    Join-Path $sharedRoot 'lib\libcurl.lib'
}
# Prefer versioned import libs such as lua54.lib over the generic lua.lib alias
# so mod_lua links against the concrete ABI that vcpkg installed.
$luaLibrary = Get-ChildItem -Path (Join-Path $sharedRoot 'lib') -Filter 'lua*.lib' -File |
    Sort-Object `
        @{ Expression = { if ($_.BaseName -match '\d') { 0 } else { 1 } } }, `
        @{ Expression = { $_.Name } } |
    Select-Object -First 1

if (-not $luaLibrary) {
    throw "No Lua import library was found in $(Join-Path $sharedRoot 'lib')."
}

$apriconvSourceRoot = Join-Path $env:GITHUB_WORKSPACE 'apr-iconv-source'
$apriconvOutputRoot = Join-Path $env:GITHUB_WORKSPACE 'apr-iconv-install'
$genTestChar = Join-Path $sharedRoot 'tools\apr\gen_test_char.exe'

foreach ($path in @($depsRoot, $apriconvSourceRoot, $apriconvOutputRoot)) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force
    }

    New-Item -Path $path -ItemType Directory -Force | Out-Null
}

foreach ($path in @(
    (Join-Path $sharedRoot 'include\apr.h'),
    (Join-Path $sharedRoot 'include\arch\win32\apr_private.h'),
    (Join-Path $sharedRoot 'include\lua.h'),
    (Join-Path $sharedRoot 'lib\libapr-1.lib'),
    (Join-Path $sharedRoot 'lib\libaprutil-1.lib'),
    $pcreLibrary,
    $curlLibrary,
    $luaLibrary.FullName,
    (Join-Path $staticRoot 'lib'),
    $genTestChar
)) {
    if (-not (Test-Path $path)) {
        throw "Required dependency path missing: $path"
    }
}

Copy-TreeContents -Source (Join-Path $sharedRoot 'include') -Destination (Join-Path $depsRoot 'include')
Copy-TreeContents -Source (Join-Path $sharedRoot 'lib') -Destination (Join-Path $depsRoot 'lib')
Copy-TreeContents -Source (Join-Path $sharedRoot 'bin') -Destination (Join-Path $depsRoot 'bin')
Copy-TreeContents -Source (Join-Path $sharedRoot 'share') -Destination (Join-Path $depsRoot 'share')
Copy-TreeContents -Source (Join-Path $sharedRoot 'tools') -Destination (Join-Path $depsRoot 'tools')

$generatedAprHeader = Join-Path $depsRoot 'include\apr_escape_test_char.h'
if (-not (Test-Path $generatedAprHeader)) {
    & $genTestChar | Out-File -FilePath $generatedAprHeader -Encoding ascii
}

$archive = Join-Path $env:RUNNER_TEMP "apr-iconv-$AprIconvVersion-win32-src.zip"
$archiveUri = "https://archive.apache.org/dist/apr/apr-iconv-$AprIconvVersion-win32-src.zip"
Invoke-WebRequest -Uri $archiveUri -OutFile $archive -UseBasicParsing -ErrorAction Stop

Write-Host "Downloaded APR-iconv $AprIconvVersion from $archiveUri"
Expand-Archive -Path $archive -DestinationPath $apriconvSourceRoot -Force

$apriconvRoot = Get-ChildItem -Path $apriconvSourceRoot -Directory | Select-Object -First 1
if (-not $apriconvRoot) {
    throw "APR-iconv sources were not extracted to $apriconvSourceRoot"
}

$apriconvParent = Split-Path -Path $apriconvRoot.FullName -Parent
$aprCompatRoot = Join-Path $apriconvParent 'apr'
$aprCompatReleaseRoots = @(
    (Join-Path $aprCompatRoot (Join-Path $iconvConfigArch 'Release'))
    (Join-Path $aprCompatRoot 'Release')
) | Select-Object -Unique
$apriconvBuildCandidates = @(
    (Join-Path $apriconvRoot.FullName (Join-Path $iconvConfigArch 'Release'))
    (Join-Path $apriconvRoot.FullName 'Release')
) | Select-Object -Unique

if (Test-Path $aprCompatRoot) {
    Remove-Item -Path $aprCompatRoot -Recurse -Force
}

foreach ($aprCompatReleaseRoot in $aprCompatReleaseRoots) {
    New-Item -Path $aprCompatReleaseRoot -ItemType Directory -Force | Out-Null
}

Copy-TreeContents -Source (Join-Path $depsRoot 'include') -Destination (Join-Path $aprCompatRoot 'include')
foreach ($aprCompatReleaseRoot in $aprCompatReleaseRoots) {
    Copy-Item -Path (Join-Path $depsRoot 'lib\libapr-1.lib') -Destination (Join-Path $aprCompatReleaseRoot 'libapr-1.lib') -Force
}

Push-Location $apriconvRoot.FullName
try {
    nmake /f libapriconv.mak CFG="libapriconv - $iconvConfigArch Release" RECURSE=0
} finally {
    Pop-Location
}

$apriconvBuildRoot = Get-FirstDirectoryWithChild `
    -Candidates $apriconvBuildCandidates `
    -ChildPath 'libapriconv-1.lib' `
    -Description 'APR-iconv import library'

$apriconvLibInstall = Join-Path $apriconvOutputRoot 'lib'
$apriconvBinInstall = Join-Path $apriconvOutputRoot 'bin'
$apriconvIncludeInstall = Join-Path $apriconvOutputRoot 'include'

New-Item -Path $apriconvLibInstall -ItemType Directory -Force | Out-Null
New-Item -Path $apriconvBinInstall -ItemType Directory -Force | Out-Null
Copy-TreeContents -Source (Join-Path $apriconvRoot.FullName 'include') -Destination $apriconvIncludeInstall

Get-ChildItem -Path $apriconvBuildRoot -File | ForEach-Object {
    $artifact = $_
    switch ($artifact.Extension.ToLowerInvariant()) {
        '.lib' { Copy-Item -Path $artifact.FullName -Destination $apriconvLibInstall -Force }
        '.exp' { Copy-Item -Path $artifact.FullName -Destination $apriconvLibInstall -Force }
        '.dll' { Copy-Item -Path $artifact.FullName -Destination $apriconvBinInstall -Force }
        '.pdb' { Copy-Item -Path $artifact.FullName -Destination $apriconvBinInstall -Force }
    }
}

"deps_root=$($depsRoot.Replace('\', '/'))" | Add-Content -Path $env:GITHUB_OUTPUT
"static_root=$($staticRoot.Replace('\', '/'))" | Add-Content -Path $env:GITHUB_OUTPUT
"apriconv_root=$($apriconvOutputRoot.Replace('\', '/'))" | Add-Content -Path $env:GITHUB_OUTPUT
"curl_library=$($curlLibrary.Replace('\', '/'))" | Add-Content -Path $env:GITHUB_OUTPUT
"lua_library=$($luaLibrary.FullName.Replace('\', '/'))" | Add-Content -Path $env:GITHUB_OUTPUT
