param (
    [string] $HttpdRoot = (Join-Path $env:GITHUB_WORKSPACE 'httpd')
)

$ErrorActionPreference = 'Stop'

$cmakeListsPath = Join-Path $HttpdRoot 'CMakeLists.txt'
$apReleasePath = Join-Path $HttpdRoot 'include\ap_release.h'

$cmakeLists = Get-Content -Path $cmakeListsPath -Raw
$apRelease = Get-Content -Path $apReleasePath -Raw

function Get-ReleaseComponent {
    param(
        [Parameter(Mandatory)] [string] $Contents,
        [Parameter(Mandatory)] [string] $Name
    )

    $match = [regex]::Match($Contents, "#define\s+$Name\s+(\d+)")
    if (-not $match.Success) {
        throw "Unable to determine $Name from $apReleasePath."
    }

    return [int] $match.Groups[1].Value
}

# Keep this probe whitespace-tolerant so harmless upstream formatting changes
# do not silently flip the dependency profile.
$supportsPcre2 = $cmakeLists -match '(?im)\bfind_package\s*\(\s*PCRE2\b'
$httpdVersion = [version]::new(
    (Get-ReleaseComponent -Contents $apRelease -Name 'AP_SERVER_MAJORVERSION_NUMBER'),
    (Get-ReleaseComponent -Contents $apRelease -Name 'AP_SERVER_MINORVERSION_NUMBER'),
    (Get-ReleaseComponent -Contents $apRelease -Name 'AP_SERVER_PATCHLEVEL_NUMBER')
)

$pcrePackage = if ($supportsPcre2) { 'pcre2' } else { 'pcre' }
$pcreLibPath = if ($supportsPcre2) { 'lib/pcre2-8.lib' } else { 'lib/pcre.lib' }
$pcreFlags = if ($supportsPcre2) { '-DHAVE_PCRE2' } else { '' }
# Apache's CMake cache variables remain PCRE_* even when the build uses
# find_package(PCRE2), so we intentionally keep overriding the PCRE_* names.
#
# OpenSSL 3 compatibility landed in the Apache 2.4.59 release series, so use the
# source version as the compatibility gate instead of grepping implementation
# details that can disappear in future refactors.
$disableOpenSsl = if ($httpdVersion -ge [version] '2.4.59') { 'FALSE' } else { 'TRUE' }

"supports_pcre2=$($supportsPcre2.ToString().ToLowerInvariant())" | Add-Content -Path $env:GITHUB_OUTPUT
"httpd_version=$httpdVersion" | Add-Content -Path $env:GITHUB_OUTPUT
"pcre_package=$pcrePackage" | Add-Content -Path $env:GITHUB_OUTPUT
"pcre_lib_path=$pcreLibPath" | Add-Content -Path $env:GITHUB_OUTPUT
"pcre_flags=$pcreFlags" | Add-Content -Path $env:GITHUB_OUTPUT
"disable_openssl=$disableOpenSsl" | Add-Content -Path $env:GITHUB_OUTPUT
