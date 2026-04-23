param (
    [Parameter(Mandatory)] [string] $Arch,
    [Parameter(Mandatory)] [string] $DepsRoot,
    [Parameter(Mandatory)] [string] $StaticRoot,
    [Parameter(Mandatory)] [string] $ApriconvRoot,
    [Parameter(Mandatory)] [string] $AprExportsRoot
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$installRoot = Join-Path $env:GITHUB_WORKSPACE 'apache-install'
$packageRoot = Join-Path $env:GITHUB_WORKSPACE 'install'
$packageIncludeRoot = Join-Path $packageRoot 'include\apache2_4'
$packageLibRoot = Join-Path $packageRoot 'lib\apache2_4'

if (Test-Path $packageRoot) {
    Remove-Item -Path $packageRoot -Recurse -Force
}

New-Item -Path $packageIncludeRoot -ItemType Directory -Force | Out-Null
New-Item -Path $packageLibRoot -ItemType Directory -Force | Out-Null

Copy-TreeContents -Source (Join-Path $DepsRoot 'include') -Destination $packageIncludeRoot
Copy-TreeContents -Source (Join-Path $ApriconvRoot 'include') -Destination $packageIncludeRoot
Copy-TreeContents -Source (Join-Path $installRoot 'include') -Destination $packageIncludeRoot

# Normalize APR's GNU-attribute fallback so MSVC consumers can compile against
# the packaged headers even when __has_attribute is predefined.
$aprHeader = Join-Path $packageIncludeRoot 'apr.h'
if (Test-Path $aprHeader) {
    $aprAttributeFallbackPattern = '(?ms)#if\s*!\(defined\(__attribute__\)\s*\|\|\s*defined\(__has_attribute\)\)\s*#define\s+__attribute__\(__x\)\s*#endif'
    $msvcAprAttributeFallbackPattern = '#if !defined\(__GNUC__\) && !defined\(__attribute__\)'
    $msvcAprAttributeFallback = @(
        '#if !defined(__GNUC__) && !defined(__attribute__)',
        '#define __attribute__(__x)',
        '#endif'
    ) -join "`r`n"

    $aprContents = Get-Content -Path $aprHeader -Raw
    $hasLegacyAttributeFallback = [regex]::IsMatch($aprContents, $aprAttributeFallbackPattern)
    $normalizedAprContents = [regex]::Replace($aprContents, $aprAttributeFallbackPattern, [System.Text.RegularExpressions.MatchEvaluator] {
        param($match)
        return $msvcAprAttributeFallback
    }, 1)

    if ($hasLegacyAttributeFallback) {
        if ([regex]::IsMatch($normalizedAprContents, $aprAttributeFallbackPattern) -or -not [regex]::IsMatch($normalizedAprContents, $msvcAprAttributeFallbackPattern)) {
            throw "Failed to normalize APR attribute fallback in $aprHeader."
        }

        Set-Content -Path $aprHeader -Value $normalizedAprContents -NoNewline
    } elseif ($aprContents -match '__has_attribute' -and -not [regex]::IsMatch($aprContents, $msvcAprAttributeFallbackPattern)) {
        throw "APR attribute fallback format changed in $aprHeader. Update the normalization rule."
    }
}

Copy-TreeContents -Source (Join-Path $DepsRoot 'lib') -Destination $packageLibRoot
Copy-TreeContents -Source (Join-Path $ApriconvRoot 'lib') -Destination $packageLibRoot
Copy-TreeContents -Source (Join-Path $installRoot 'lib') -Destination $packageLibRoot
Copy-TreeContents -Source $AprExportsRoot -Destination $packageLibRoot

$staticLibRoot = Join-Path $StaticRoot 'lib'
if (Test-Path $staticLibRoot) {
    Get-ChildItem -Path $staticLibRoot -Filter *.lib -File | ForEach-Object {
        $sharedDestination = Join-Path $packageLibRoot $_.Name
        $staticSuffix = if ($_.BaseName -match '[-.]') { '-static' } else { 'static' }
        $staticDestination = Join-Path $packageLibRoot "$($_.BaseName)$staticSuffix$($_.Extension)"

        if (Test-Path $sharedDestination) {
            Copy-Item -Path $_.FullName -Destination $staticDestination -Force
        } else {
            Copy-Item -Path $_.FullName -Destination $sharedDestination -Force
        }
    }
}

Get-ChildItem -Path $packageLibRoot -Filter 'lib*.lib' -File | ForEach-Object {
    $aliasName = $_.Name.Substring(3)
    $aliasTarget = Join-Path $packageLibRoot $aliasName
    if (-not (Test-Path $aliasTarget)) {
        Copy-Item -Path $_.FullName -Destination $aliasTarget -Force
    }
}

$expectedAprExports = @(
    'libapr-1.exp',
    'libaprutil-1.exp'
)
$missingAprExports = @($expectedAprExports | Where-Object {
    -not (Test-Path (Join-Path $packageLibRoot $_))
})

if ($missingAprExports.Count -gt 0) {
    throw "Missing APR compatibility export file(s): $($missingAprExports -join ', '). The staged APR export directory did not contain the expected SDK exports."
}

$xmlCompatTarget = Join-Path $packageLibRoot 'xml.lib'
if (-not (Test-Path $xmlCompatTarget)) {
    $xmlCompatSource = @(
        'libexpat.lib',
        'expat.lib',
        'libexpatMD.lib',
        'libexpatMT.lib',
        'libexpatw.lib',
        'libexpatwMD.lib',
        'libexpatwMT.lib'
    ) | ForEach-Object {
        $candidate = Join-Path $packageLibRoot $_
        if (Test-Path $candidate) {
            Get-Item -Path $candidate
        }
    } | Select-Object -First 1

    if (-not $xmlCompatSource) {
        throw "Unable to create xml.lib because no expected Expat library was found in $packageLibRoot."
    }

    Copy-Item -Path $xmlCompatSource.FullName -Destination $xmlCompatTarget -Force
}
