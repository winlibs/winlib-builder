param([string] $SourceRoot = 'cairo')

$ErrorActionPreference = 'Stop'

# Recent Cairo wraps name a versioned directory, which otherwise bypasses the
# explicitly checked-out Pixman tree and makes the generated SBOM inaccurate.
$wrapPath = Join-Path $SourceRoot 'subprojects/pixman.wrap'
if (Test-Path -LiteralPath $wrapPath) {
    $wrap = Get-Content -LiteralPath $wrapPath -Raw
    if ($wrap -notmatch '(?m)^directory\s*=') {
        throw 'The Cairo Pixman wrap has no directory setting'
    }
    $wrap = $wrap -replace '(?m)^directory\s*=.*$', 'directory = pixman'
    Set-Content -LiteralPath $wrapPath -Value $wrap -Encoding UTF8
}
if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'subprojects/pixman/meson.build'))) {
    throw 'The requested Pixman checkout is missing'
}

# MSVC v142 accepts C11 mode but has no _Thread_local keyword. Its native TLS
# storage-class spelling has the same lifetime as the C11 declaration here.
$tlsPath = Join-Path $SourceRoot 'src/win32/cairo-win32-thread-data.c'
if (Test-Path -LiteralPath $tlsPath) {
    $source = Get-Content -LiteralPath $tlsPath -Raw
    $declaration = 'static _Thread_local'
    if ($source.Contains($declaration)) {
        $replacement = @'
#if defined(_MSC_VER) && !defined(__clang__) && _MSC_VER < 1930
static __declspec(thread)
#else
static _Thread_local
#endif
'@
        $source = $source.Replace($declaration, $replacement)
        Set-Content -LiteralPath $tlsPath -Value $source -Encoding UTF8
    }
}
